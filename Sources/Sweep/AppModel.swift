import AppKit
import Observation
import SweepCore
import SwiftUI

enum AppPhase: Equatable {
    case home
    case scanning
    case results
    case cleaning
    case done
}

enum SidebarDestination: Hashable {
    case overview
    case explorer
    case category(JunkCategory)
}

enum ScopeChoice: Hashable {
    case entireDisk
    case home
    case folder(String)

    var engineScope: ScanScope {
        switch self {
        case .entireDisk: .entireDisk
        case .home: .home
        case .folder(let path): .folder(path)
        }
    }

    var title: String {
        switch self {
        case .entireDisk: "Entire Disk"
        case .home: "Home Folder"
        case .folder(let path): (path as NSString).lastPathComponent
        }
    }
}

extension DeleteMode {
    static let storageKey = "deleteMode"

    static var preferred: DeleteMode {
        UserDefaults.standard.string(forKey: storageKey).flatMap(DeleteMode.init(rawValue:)) ?? .moveToTrash
    }

    var title: String {
        switch self {
        case .moveToTrash: "Move to Trash"
        case .deletePermanently: "Delete Immediately"
        }
    }

    var symbol: String {
        switch self {
        case .moveToTrash: "trash"
        case .deletePermanently: "xmark.bin"
        }
    }
}

struct CategorySummary: Identifiable {
    let category: JunkCategory
    let items: [CleanupItem]
    let totalSize: Int64
    let safetyBytes: [Safety: Int64]

    var id: JunkCategory { category }
    var largestItemSize: Int64 { items.first?.size ?? 0 }
}

struct ScanResults {
    let items: [CleanupItem]
    let tree: SpaceTree?
    let volume: VolumeInfo
    let docker: DockerStatus
    let filesScanned: Int
    let directoriesScanned: Int
    let bytesScanned: Int64
    let inaccessibleDirectories: Int
    let duration: TimeInterval

    init(report: ScanReport) {
        items = report.items
        tree = report.tree
        volume = report.volume
        docker = report.docker
        filesScanned = report.stats.files
        directoriesScanned = report.stats.directories
        bytesScanned = report.stats.bytes
        inaccessibleDirectories = report.stats.inaccessibleDirectories
        duration = report.stats.duration
    }

    init(items: [CleanupItem], tree: SpaceTree?, volume: VolumeInfo, docker: DockerStatus, filesScanned: Int, directoriesScanned: Int, bytesScanned: Int64, duration: TimeInterval) {
        self.items = items
        self.tree = tree
        self.volume = volume
        self.docker = docker
        self.filesScanned = filesScanned
        self.directoriesScanned = directoriesScanned
        self.bytesScanned = bytesScanned
        self.inaccessibleDirectories = 0
        self.duration = duration
    }
}

struct CleanFailureEntry: Identifiable {
    let id: String
    let title: String
    let reason: String
}

struct CleanOutcome {
    let bytesFreed: Int64
    let cleanedItemIDs: Set<String>
    let failures: [CleanFailureEntry]
    let movedToTrash: Bool
    let trashedPaths: [String]

    init(bytesFreed: Int64, cleanedItemIDs: Set<String>, failures: [CleanFailureEntry], movedToTrash: Bool, trashedPaths: [String] = []) {
        self.bytesFreed = bytesFreed
        self.cleanedItemIDs = cleanedItemIDs
        self.failures = failures
        self.movedToTrash = movedToTrash
        self.trashedPaths = trashedPaths
    }

    init(report: CleanReport) {
        bytesFreed = report.bytesFreed
        cleanedItemIDs = report.cleanedItemIDs
        failures = report.failures.map { CleanFailureEntry(id: $0.id, title: $0.title, reason: $0.reason) }
        movedToTrash = report.movedToTrash
        trashedPaths = report.trashedPaths
    }
}

struct CleanTick: Sendable {
    let completed: Int
    let total: Int
    let bytesFreed: Int64
    let bytesProcessed: Int64
    let currentTitle: String
}

struct LiveCleanProgress {
    var completed: Int
    var total: Int
    var bytesFreed: Int64
    var bytesProcessed: Int64 = 0
    var targetBytes: Int64
    var currentTitle: String

    var fraction: Double {
        if targetBytes > 0 { return min(1, Double(bytesProcessed) / Double(targetBytes)) }
        return total == 0 ? 0 : Double(completed) / Double(total)
    }
}

@Observable
@MainActor
final class AppModel {
    var phase: AppPhase = .home
    private(set) var destination: SidebarDestination = .overview
    var scope: ScopeChoice = .entireDisk
    var progress = ScanProgress(phase: .walking)
    private(set) var scanStartedAt = Date()
    private(set) var results: ScanResults?
    private(set) var startupVolume = VolumeInfo.forPath("/")
    private(set) var summaries: [CategorySummary] = []
    private(set) var totalJunkBytes: Int64 = 0
    private(set) var visibleItemCount = 0
    private(set) var selection: Set<String> = []
    private(set) var selectedBytes: Int64 = 0
    private(set) var selectedCountByCategory: [JunkCategory: Int] = [:]
    private(set) var selectedBytesByCategory: [JunkCategory: Int64] = [:]
    private(set) var ignoredKeys: [String] = []
    private(set) var hasFullDiskAccess = SweepEngine.hasFullDiskAccess()
    var cleanProgress = LiveCleanProgress(completed: 0, total: 0, bytesFreed: 0, targetBytes: 0, currentTitle: "")
    private(set) var outcome: CleanOutcome?
    var isConfirmingClean = false
    private(set) var isRefreshingDocker = false
    private(set) var backgroundDeletion = SweepEngine.backgroundDeletion.status
    var explorerNodeID: Int32 = 0

    @ObservationIgnored private let engine = SweepEngine()
    @ObservationIgnored private var itemsByID: [String: CleanupItem] = [:]
    @ObservationIgnored private var summaryIndex: [JunkCategory: Int] = [:]
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanWasCancelled = false
    @ObservationIgnored private var backgroundDeletionWatcher: Task<Void, Never>?

    private static let ignoredKeysStorageKey = "ignoredPaths"

    init() {
        ignoredKeys = UserDefaults.standard.stringArray(forKey: Self.ignoredKeysStorageKey) ?? []
        watchBackgroundDeletion()
        SweepEngine.resumePendingDeletions()
    }

    var volume: VolumeInfo {
        guard let scanned = results?.volume, scanned.name != startupVolume.name else { return startupVolume }
        return scanned
    }

    private func watchBackgroundDeletion() {
        backgroundDeletionWatcher = Task { [weak self] in
            for await status in SweepEngine.backgroundDeletion.statusUpdates() {
                guard let self else { return }
                self.backgroundDeletion = status
                self.startupVolume = VolumeInfo.forPath("/")
            }
        }
    }

    func deleteTrashedItems(_ paths: [String]) async -> DeletionResult {
        #if DEBUG
        if DemoMode.isEnabled { return DeletionResult(failedEntries: 0, firstError: nil) }
        #endif
        return await engine.emptyTrash(paths)
    }
    var hasResults: Bool { results != nil }
    var canStartScan: Bool { phase != .scanning && phase != .cleaning }
    var canClean: Bool { (phase == .results || phase == .done) && !selection.isEmpty }
    var selectedCount: Int { selection.count }
    var tree: SpaceTree? { results?.tree }
    var docker: DockerStatus? { results?.docker }

    func summary(for category: JunkCategory) -> CategorySummary? {
        summaryIndex[category].map { summaries[$0] }
    }

    func isSelected(_ id: String) -> Bool { selection.contains(id) }

    var selectedItems: [CleanupItem] {
        summaries.flatMap { $0.items.filter { selection.contains($0.id) } }
    }

    var recommendedIDs: Set<String> {
        Set(summaries.flatMap { $0.items.filter(\.recommended).map(\.id) })
    }

    var isSmartSelectionActive: Bool {
        let recommended = recommendedIDs
        return !recommended.isEmpty && recommended == selection
    }

    func navigate(to destination: SidebarDestination) {
        self.destination = destination
        if phase == .done { phase = .results }
    }

    func refreshFullDiskAccess() {
        hasFullDiskAccess = SweepEngine.hasFullDiskAccess()
        if phase == .home { startupVolume = VolumeInfo.forPath("/") }
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(SweepEngine.fullDiskAccessSettingsURL)
    }

    func startScan() {
        guard canStartScan else { return }
        scanWasCancelled = false
        progress = ScanProgress(phase: .walking)
        scanStartedAt = Date()
        withAnimation(.smooth(duration: 0.45)) { phase = .scanning }
        scanTask = Task { [weak self] in await self?.runScan() }
    }

    func cancelScan() {
        guard phase == .scanning else { return }
        scanWasCancelled = true
        engine.cancel()
        scanTask?.cancel()
        withAnimation(.smooth(duration: 0.4)) { phase = results == nil ? .home : .results }
    }

    private func runScan() async {
        let scanned = await performScan(scope: scope.engineScope)
        guard !scanWasCancelled, let scanned else { return }
        apply(scanned)
    }

    private func performScan(scope: ScanScope) async -> ScanResults? {
        let reportProgress: @Sendable (ScanProgress) -> Void = { [weak self] update in
            Task { @MainActor in self?.receive(update) }
        }
        #if DEBUG
        if DemoMode.isEnabled {
            return await DemoData.scan(engine: engine, progress: reportProgress) { [weak self] tree in
                Task { @MainActor in self?.attachDemoTree(tree) }
            }
        }
        #endif
        let report = await engine.scan(scope: scope, progress: reportProgress)
        return ScanResults(report: report)
    }

    private func receive(_ update: ScanProgress) {
        guard phase == .scanning, !scanWasCancelled else { return }
        progress = update
    }

    private func apply(_ scanned: ScanResults) {
        results = scanned
        explorerNodeID = 0
        outcome = nil
        itemsByID = Dictionary(scanned.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        rebuildSummaries()
        replaceSelection(with: recommendedIDs)
        destination = .overview
        withAnimation(.smooth(duration: 0.5)) { phase = .results }
    }

    private func ignoreKey(for item: CleanupItem) -> String { item.path ?? item.id }

    private func rebuildSummaries() {
        let ignored = Set(ignoredKeys)
        let visible = (results?.items ?? []).filter { !ignored.contains(ignoreKey(for: $0)) }
        let grouped = Dictionary(grouping: visible, by: \.category)
        summaries = grouped.map { category, items in
            var safetyBytes: [Safety: Int64] = [:]
            for item in items { safetyBytes[item.safety, default: 0] += item.size }
            return CategorySummary(
                category: category,
                items: items.sorted { $0.size > $1.size },
                totalSize: items.reduce(0) { $0 + $1.size },
                safetyBytes: safetyBytes
            )
        }
        .sorted { $0.totalSize > $1.totalSize }
        summaryIndex = Dictionary(uniqueKeysWithValues: summaries.enumerated().map { ($1.category, $0) })
        totalJunkBytes = summaries.reduce(0) { $0 + $1.totalSize }
        visibleItemCount = visible.count
        let visibleIDs = Set(visible.map(\.id))
        replaceSelection(with: selection.intersection(visibleIDs))
        if case .category(let category) = destination, summaryIndex[category] == nil {
            destination = .overview
        }
    }

    func setChecked<S: Sequence>(_ ids: S, _ checked: Bool) where S.Element == String {
        var updated = selection
        if checked {
            updated.formUnion(ids.filter { itemsByID[$0] != nil })
        } else {
            updated.subtract(ids)
        }
        replaceSelection(with: updated)
    }

    func toggle(_ id: String) {
        setChecked([id], !selection.contains(id))
    }

    func smartSelect() {
        replaceSelection(with: recommendedIDs)
    }

    func selectAll() {
        replaceSelection(with: Set(summaries.flatMap { $0.items.map(\.id) }))
    }

    func deselectAll() {
        replaceSelection(with: [])
    }

    private func replaceSelection(with ids: Set<String>) {
        var bytes: Int64 = 0
        var counts: [JunkCategory: Int] = [:]
        var bytesByCategory: [JunkCategory: Int64] = [:]
        for id in ids {
            guard let item = itemsByID[id] else { continue }
            bytes += item.size
            counts[item.category, default: 0] += 1
            bytesByCategory[item.category, default: 0] += item.size
        }
        selection = ids
        selectedBytes = bytes
        selectedCountByCategory = counts
        selectedBytesByCategory = bytesByCategory
    }

    func ignore(_ ids: [String]) {
        let keys = ids.compactMap { itemsByID[$0] }.map(ignoreKey(for:))
        let fresh = keys.filter { !ignoredKeys.contains($0) }
        guard !fresh.isEmpty else { return }
        ignoredKeys.append(contentsOf: fresh)
        persistIgnoredKeys()
        withAnimation(.smooth) { rebuildSummaries() }
    }

    func unignore(_ key: String) {
        ignoredKeys.removeAll { $0 == key }
        persistIgnoredKeys()
        rebuildSummaries()
    }

    func unignoreAll() {
        ignoredKeys.removeAll()
        persistIgnoredKeys()
        rebuildSummaries()
    }

    private func persistIgnoredKeys() {
        UserDefaults.standard.set(ignoredKeys, forKey: Self.ignoredKeysStorageKey)
    }

    func requestClean() {
        guard canClean else { return }
        if phase == .done { phase = .results }
        isConfirmingClean = true
    }

    func clean() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        isConfirmingClean = false
        let mode = DeleteMode.preferred
        cleanProgress = LiveCleanProgress(completed: 0, total: items.count, bytesFreed: 0, targetBytes: items.reduce(0) { $0 + $1.size }, currentTitle: items.first?.title ?? "")
        withAnimation(.smooth(duration: 0.4)) { phase = .cleaning }
        Task { [weak self] in
            guard let self else { return }
            let finished = await self.performClean(items, mode: mode)
            self.finishClean(finished)
        }
    }

    private func performClean(_ items: [CleanupItem], mode: DeleteMode) async -> CleanOutcome {
        let reportProgress: @Sendable (CleanTick) -> Void = { [weak self] update in
            Task { @MainActor in self?.receive(update) }
        }
        #if DEBUG
        if DemoMode.isEnabled {
            return await DemoData.simulateClean(items, mode: mode, progress: reportProgress)
        }
        #endif
        let report = await engine.clean(items, mode: mode) { update in
            reportProgress(CleanTick(completed: update.completed, total: update.total, bytesFreed: update.bytesFreed, bytesProcessed: update.bytesProcessed, currentTitle: update.currentTitle))
        }
        return CleanOutcome(report: report)
    }

    private func receive(_ update: CleanTick) {
        guard phase == .cleaning else { return }
        cleanProgress.completed = update.completed
        cleanProgress.total = update.total
        cleanProgress.bytesFreed = update.bytesFreed
        cleanProgress.bytesProcessed = update.bytesProcessed
        cleanProgress.currentTitle = update.currentTitle
    }

    private func finishClean(_ finished: CleanOutcome) {
        outcome = finished
        removeItems(finished.cleanedItemIDs)
        startupVolume = VolumeInfo.forPath("/")
        withAnimation(.smooth(duration: 0.5)) { phase = .done }
    }

    private func removeItems(_ ids: Set<String>) {
        guard let current = results, !ids.isEmpty else { return }
        let remaining = current.items.filter { !ids.contains($0.id) }
        results = ScanResults(
            items: remaining,
            tree: current.tree,
            volume: VolumeInfo.forPath("/"),
            docker: current.docker,
            filesScanned: current.filesScanned,
            directoriesScanned: current.directoriesScanned,
            bytesScanned: current.bytesScanned,
            duration: current.duration
        )
        for id in ids { itemsByID[id] = nil }
        replaceSelection(with: selection.subtracting(ids))
        rebuildSummaries()
    }

    func backToResults() {
        withAnimation(.smooth(duration: 0.4)) { phase = results == nil ? .home : .results }
    }

    func goHome() {
        guard phase != .scanning, phase != .cleaning else { return }
        withAnimation(.smooth(duration: 0.4)) { phase = .home }
    }

    func mergeDockerItems(_ items: [CleanupItem], status: DockerStatus) {
        guard let current = results else { return }
        let kept = current.items.filter { $0.category != .docker }
        let merged = kept + items
        results = ScanResults(
            items: merged,
            tree: current.tree,
            volume: current.volume,
            docker: status,
            filesScanned: current.filesScanned,
            directoriesScanned: current.directoriesScanned,
            bytesScanned: current.bytesScanned,
            duration: current.duration
        )
        itemsByID = Dictionary(merged.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        rebuildSummaries()
        setChecked(items.filter(\.recommended).map(\.id), true)
    }

    #if DEBUG
    func attachDemoTree(_ tree: SpaceTree) {
        guard let current = results else { return }
        results = ScanResults(
            items: current.items,
            tree: tree,
            volume: current.volume,
            docker: current.docker,
            filesScanned: current.filesScanned,
            directoriesScanned: current.directoriesScanned,
            bytesScanned: current.bytesScanned,
            duration: current.duration
        )
    }
    #endif

    func setRefreshingDocker(_ refreshing: Bool) {
        isRefreshingDocker = refreshing
    }
}

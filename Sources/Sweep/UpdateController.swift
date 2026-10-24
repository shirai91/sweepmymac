import AppKit
import Observation
import SweepCore

@Observable
@MainActor
final class UpdateController {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case downloading(Double)
        case ready
        case installing
        case failed(String)
    }

    static let checksAutomaticallyKey = "checksForUpdatesAutomatically"
    static let downloadsAutomaticallyKey = "downloadsUpdatesAutomatically"
    static let skippedVersionKey = "skippedUpdateVersion"

    private(set) var status: Status = .idle
    private(set) var available: AvailableUpdate?
    private(set) var lastChecked: Date?
    var isPromptRequested = false

    @ObservationIgnored let installer = UpdateInstaller(bundle: .main)
    @ObservationIgnored private var prepared: PreparedUpdate?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var download: Task<Void, Never>?
    @ObservationIgnored private var postponedVersion: AppVersion?

    init() {
        UserDefaults.standard.register(defaults: [
            Self.checksAutomaticallyKey: true,
            Self.downloadsAutomaticallyKey: true,
        ])
    }

    var isEnabled: Bool { installer != nil }
    var currentVersion: String { installer?.currentVersion.description ?? "development build" }
    var canInstallInPlace: Bool { installer?.canReplaceInstalledApp ?? false }
    var isBusy: Bool {
        switch status {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    var releaseNotes: AttributedString? {
        guard let body = available?.release.body, !body.isEmpty,
              let text = available?.release.inlineMarkdownNotes else { return nil }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(body)
    }
    private var checksAutomatically: Bool { UserDefaults.standard.bool(forKey: Self.checksAutomaticallyKey) }
    private var downloadsAutomatically: Bool { UserDefaults.standard.bool(forKey: Self.downloadsAutomaticallyKey) }
    private var skippedVersion: AppVersion? {
        UserDefaults.standard.string(forKey: Self.skippedVersionKey).flatMap(AppVersion.init)
    }

    func start() {
        guard isEnabled, !hasStarted else { return }
        hasStarted = true
        guard checksAutomatically else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            await self?.check(userInitiated: false)
        }
    }

    func checkNow() {
        Task { await check(userInitiated: true) }
    }

    func check(userInitiated: Bool) async {
        guard let installer, !isBusy, status != .ready || userInitiated else { return }
        status = .checking
        do {
            let update = try await ReleaseFeed.sweep.update(newerThan: installer.currentVersion, userAgent: "Sweep/\(installer.currentVersion)")
            lastChecked = Date()
            guard let update else {
                available = nil
                status = .upToDate
                if userInitiated { isPromptRequested = true }
                return
            }
            if available != update { discardPrepared() }
            available = update
            status = prepared == nil ? .idle : .ready
            guard userInitiated || !isPostponed(update.version) else { return }
            if downloadsAutomatically && installer.canReplaceInstalledApp && prepared == nil {
                downloadUpdate(promptWhenReady: true)
            } else {
                isPromptRequested = true
            }
        } catch {
            status = .failed(error.localizedDescription)
            if userInitiated { isPromptRequested = true }
        }
    }

    func downloadUpdate(promptWhenReady: Bool = false) {
        guard let installer, let update = available, download == nil else { return }
        status = .downloading(0)
        download = Task { [weak self] in
            do {
                guard let progress = self?.downloadProgressHandler() else { return }
                let result = try await installer.prepare(update, progress: progress)
                guard let self else { return }
                self.prepared = result
                self.status = .ready
            } catch {
                self?.status = .failed(error.localizedDescription)
            }
            guard let self else { return }
            self.download = nil
            if promptWhenReady && !self.isPostponed(update.version) { self.isPromptRequested = true }
        }
    }

    private func downloadProgressHandler() -> @Sendable (Double) -> Void {
        { [weak self] fraction in
            Task { @MainActor in self?.receiveDownloadProgress(fraction) }
        }
    }

    private func receiveDownloadProgress(_ fraction: Double) {
        guard case .downloading = status else { return }
        status = .downloading(fraction)
    }

    func installAndRelaunch() {
        guard let installer, let prepared else { return }
        status = .installing
        do {
            try installer.installAndRelaunch(prepared, afterExitOf: ProcessInfo.processInfo.processIdentifier)
            isPromptRequested = false
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                NSApp.terminate(nil)
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func openReleasePage() {
        let page = available?.release.htmlUrl ?? URL(string: "https://github.com/shirai91/sweepmymac/releases/latest")!
        NSWorkspace.shared.open(page)
        isPromptRequested = false
    }

    func remindLater() {
        postponedVersion = available?.version
        isPromptRequested = false
        if case .failed = status { status = .idle }
        if status == .upToDate { status = .idle }
    }

    func skipThisVersion() {
        if let version = available?.version {
            UserDefaults.standard.set(version.description, forKey: Self.skippedVersionKey)
        }
        download?.cancel()
        download = nil
        discardPrepared()
        status = .idle
        isPromptRequested = false
    }

    private func isPostponed(_ version: AppVersion) -> Bool {
        version == postponedVersion || version == skippedVersion
    }

    private func discardPrepared() {
        if let prepared { installer?.discard(prepared) }
        prepared = nil
    }
}

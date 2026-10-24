#if DEBUG
import AppKit
import SweepCore
import SwiftUI

enum DemoMode {
    static var isEnabled: Bool { environment("SWEEP_DEMO") == "1" }
    static var route: String? { environment("SWEEP_DEMO_ROUTE") }
    static var appearance: String? { environment("SWEEP_DEMO_APPEARANCE") }
    static var dockerStopped: Bool { environment("SWEEP_DEMO_DOCKER_STOPPED") == "1" }
    static var bulkItems: Bool { environment("SWEEP_DEMO_BULK") == "1" }
    static var snapshotPath: String? { environment("SWEEP_DEMO_SNAPSHOT") }
    static var autoscanFolder: String? { environment("SWEEP_AUTOSCAN_FOLDER") }
    static var snapshotDelay: Double { environment("SWEEP_DEMO_SNAPSHOT_DELAY").flatMap(Double.init) ?? 2.5 }

    private static func environment(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }
}

@MainActor
enum DemoAutopilot {
    static func run(_ model: AppModel, openSettings: () -> Void) async {
        guard DemoMode.isEnabled || DemoMode.autoscanFolder != nil else { return }
        applyAppearance()
        if let folder = DemoMode.autoscanFolder {
            model.scope = .folder(folder)
        }
        if DemoMode.route == "settings" {
            openSettings()
        } else {
            await navigate(model)
        }
        await DemoSnapshot.captureIfRequested()
    }

    private static func navigate(_ model: AppModel) async {
        guard let route = DemoMode.route, route != "home" else { return }
        model.startScan()
        guard route != "scanning" else { return }
        await waitUntil { model.phase == .results }
        try? await Task.sleep(for: .milliseconds(400))
        switch route {
        case "explorer":
            model.navigate(to: .explorer)
        case "confirm":
            model.requestClean()
        case "cleaning", "done":
            guard DemoMode.isEnabled else { return }
            model.clean()
        default:
            if route.hasPrefix("category:"), let category = JunkCategory(rawValue: String(route.dropFirst("category:".count))) {
                model.navigate(to: .category(category))
            }
        }
    }

    private static func applyAppearance() {
        switch DemoMode.appearance {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }

    private static func waitUntil(_ condition: () -> Bool) async {
        while !condition() {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}

@MainActor
enum DemoSnapshot {
    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    static func captureIfRequested() async {
        guard let path = DemoMode.snapshotPath else { return }
        try? await Task.sleep(for: .seconds(DemoMode.snapshotDelay))
        let visible = NSApp.windows.filter { $0.isVisible && $0.frame.width > 300 }
        if DemoMode.route == "settings", let settings = visible.first(where: { $0.frame.width < 700 }) {
            write(windowNumber: settings.windowNumber, to: path)
            exit(0)
        }
        if let main = visible.first(where: { $0.sheetParent == nil }) {
            write(windowNumber: main.windowNumber, to: path)
        }
        if let sheet = visible.first(where: { $0.sheetParent != nil }) {
            write(windowNumber: sheet.windowNumber, to: path.replacingOccurrences(of: ".png", with: "-sheet.png"))
        }
        exit(0)
    }

    private static func write(windowNumber: Int, to path: String) {
        guard let image = windowImage(number: windowNumber) else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private static func windowImage(number: Int) -> CGImage? {
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        let includingWindow: UInt32 = 1 << 3
        let boundsIgnoreFraming: UInt32 = 1 << 0
        let bestResolution: UInt32 = 1 << 3
        return create(.null, includingWindow, UInt32(number), boundsIgnoreFraming | bestResolution)?.takeRetainedValue()
    }
}

enum DemoData {
    static func scan(engine: SweepEngine, progress: @escaping @Sendable (ScanProgress) -> Void, treeReady: @escaping @Sendable (SpaceTree) -> Void) async -> ScanResults {
        let duration: TimeInterval = DemoMode.route == "scanning" ? 3600 : 2.6
        let treeFolder = ProcessInfo.processInfo.environment["SWEEP_DEMO_TREE"] ?? NSHomeDirectory() + "/Library"
        Task.detached(priority: .userInitiated) {
            let report = await SweepEngine().scan(scope: .folder(treeFolder), progress: { _ in })
            treeReady(report.tree)
        }
        await simulateProgress(duration: duration, progress: progress)
        let docker = DemoMode.dockerStopped
            ? DockerStatus(installed: true, running: false, message: nil)
            : DockerStatus(installed: true, running: true, message: nil)
        var items = makeItems()
        if DemoMode.dockerStopped { items.removeAll { $0.category == .docker } }
        return ScanResults(
            items: items,
            tree: nil,
            volume: VolumeInfo.forPath("/"),
            docker: docker,
            filesScanned: 2_481_337,
            directoriesScanned: 412_906,
            bytesScanned: 612_400_000_000,
            duration: 7.4
        )
    }

    private static func simulateProgress(duration: TimeInterval, progress: @Sendable (ScanProgress) -> Void) async {
        let start = Date()
        let samplePaths = [
            "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer",
            NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData/Sweep-bcdefghijklmnop/Build/Intermediates.noindex",
            NSHomeDirectory() + "/projects/storefront/node_modules/@babel/core/lib/transformation/file",
            NSHomeDirectory() + "/Library/Caches/com.spotify.client/Data/ab/cd/ef",
            "/System/Library/Frameworks/CoreML.framework/Versions/A/Resources",
            NSHomeDirectory() + "/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
        ]
        var tick = 0
        while Date().timeIntervalSince(start) < duration {
            let elapsed = Date().timeIntervalSince(start)
            let fraction = min(elapsed / 2.6, 1)
            let phase: ScanPhase = fraction < 0.62 ? .walking : fraction < 0.82 ? .analyzing : fraction < 0.93 ? .duplicates : .docker
            let files = Int(elapsed * 336_000)
            progress(ScanProgress(
                phase: duration > 100 ? .walking : phase,
                filesScanned: files,
                directoriesScanned: files / 6,
                bytesScanned: Int64(elapsed * 82_000_000_000),
                currentPath: samplePaths[tick % samplePaths.count] + "/\(files % 997)",
                elapsed: elapsed
            ))
            tick += 1
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    static func simulateClean(_ items: [CleanupItem], mode: DeleteMode, progress: @escaping @Sendable (CleanTick) -> Void) async -> CleanOutcome {
        let stepDelay: Duration = DemoMode.route == "cleaning" ? .seconds(30) : .milliseconds(max(20, 2400 / max(items.count, 1)))
        var freed: Int64 = 0
        var processed: Int64 = 0
        var cleaned: Set<String> = []
        var failures: [CleanFailureEntry] = []
        let failingID = items.first { $0.path?.hasPrefix("/Library") ?? false }?.id
        for (index, item) in items.enumerated() {
            progress(CleanTick(completed: index, total: items.count, bytesFreed: freed, bytesProcessed: processed, currentTitle: item.title))
            try? await Task.sleep(for: stepDelay)
            if item.id == failingID {
                failures.append(CleanFailureEntry(id: item.id, title: item.title, reason: "Permission denied. Sweep needs administrator rights to remove files in /Library."))
            } else {
                freed += item.size
                cleaned.insert(item.id)
            }
            processed += item.size
        }
        progress(CleanTick(completed: items.count, total: items.count, bytesFreed: freed, bytesProcessed: processed, currentTitle: "Done"))
        try? await Task.sleep(for: .milliseconds(300))
        let trashed = mode == .moveToTrash ? items.compactMap(\.path).map { NSHomeDirectory() + "/.Trash/" + ($0 as NSString).lastPathComponent } : []
        return CleanOutcome(bytesFreed: freed, cleanedItemIDs: cleaned, failures: failures, movedToTrash: mode == .moveToTrash, trashedPaths: trashed)
    }

    private static let home = NSHomeDirectory()
    private static let gb: Int64 = 1_000_000_000
    private static let mb: Int64 = 1_000_000

    private static func daysAgo(_ days: Double) -> Date {
        Date().addingTimeInterval(-days * 86_400)
    }

    private static func pathItem(_ category: JunkCategory, _ title: String, _ detail: String, _ path: String, _ size: Int64, count: Int = 1, days: Double, safety: Safety = .safe, recommended: Bool = true, bundle: String? = nil) -> CleanupItem {
        let fullPath = path.hasPrefix("~") ? home + path.dropFirst() : path
        return CleanupItem(
            id: "\(category.rawValue):\(fullPath)",
            category: category,
            title: title,
            detail: detail,
            path: fullPath,
            size: size,
            itemCount: count,
            lastModified: daysAgo(days),
            safety: safety,
            recommended: recommended,
            action: .removePaths([fullPath]),
            bundleIdentifier: bundle
        )
    }

    private static func dockerItem(_ title: String, _ detail: String, _ size: Int64, action: DockerAction, days: Double, safety: Safety = .safe, recommended: Bool = true) -> CleanupItem {
        CleanupItem(
            id: "docker:\(title)",
            category: .docker,
            title: title,
            detail: detail,
            path: nil,
            size: size,
            lastModified: daysAgo(days),
            safety: safety,
            recommended: recommended,
            action: .docker(action)
        )
    }

    static func makeItems() -> [CleanupItem] {
        var items: [CleanupItem] = appCaches() + devCaches() + xcode() + buildArtifacts() + docker() + misc()
        if DemoMode.bulkItems { items += bulkBuildArtifacts() }
        return items
    }

    private static func appCaches() -> [CleanupItem] {
        [
            pathItem(.appCaches, "Google Chrome", "Browser cache", "~/Library/Caches/Google/Chrome", 2_140 * mb, count: 18_204, days: 0.2, bundle: "com.google.Chrome"),
            pathItem(.appCaches, "Spotify", "Offline music cache", "~/Library/Caches/com.spotify.client", 3_420 * mb, count: 4_102, days: 1, bundle: "com.spotify.client"),
            pathItem(.appCaches, "Slack", "Cached files and images", "~/Library/Application Support/Slack/Cache", 1_210 * mb, count: 9_311, days: 0.5, bundle: "com.tinyspeck.slackmacgap"),
            pathItem(.appCaches, "Visual Studio Code", "Cached extension data", "~/Library/Application Support/Code/CachedData", 640 * mb, count: 2_008, days: 3, bundle: "com.microsoft.VSCode"),
            pathItem(.appCaches, "Safari", "Web page cache", "~/Library/Caches/com.apple.Safari", 382 * mb, count: 3_550, days: 0.1, bundle: "com.apple.Safari"),
            pathItem(.appCaches, "Figma", "Rendered file cache", "~/Library/Application Support/Figma/DesktopProfile/Cache", 512 * mb, count: 1_204, days: 4, bundle: "com.figma.Desktop"),
            pathItem(.appCaches, "Microsoft Teams", "Media and web cache", "~/Library/Containers/com.microsoft.teams2/Data/Library/Caches", 870 * mb, count: 6_660, days: 2, bundle: "com.microsoft.teams2"),
            pathItem(.appCaches, "Discord", "Cache and GPU cache", "~/Library/Application Support/discord/Cache", 291 * mb, count: 2_870, days: 6, bundle: "com.hnc.Discord"),
            pathItem(.appCaches, "zoom.us", "Downloaded resources", "~/Library/Caches/us.zoom.xos", 152 * mb, count: 410, days: 12, bundle: "us.zoom.xos"),
            pathItem(.appCaches, "Music", "Artwork cache", "~/Library/Caches/com.apple.Music", 96 * mb, count: 1_820, days: 20, bundle: "com.apple.Music"),
        ]
    }

    private static func devCaches() -> [CleanupItem] {
        [
            pathItem(.devCaches, "npm cache", "Downloaded package tarballs", "~/.npm/_cacache", 4_210 * mb, count: 61_402, days: 1),
            pathItem(.devCaches, "Homebrew", "Downloaded bottles and source archives", "~/Library/Caches/Homebrew", 2_730 * mb, count: 214, days: 9),
            pathItem(.devCaches, "Gradle", "Dependency and build caches", "~/.gradle/caches", 3_120 * mb, count: 48_920, days: 33),
            pathItem(.devCaches, "Yarn", "Offline package mirror", "~/Library/Caches/Yarn", 1_640 * mb, count: 22_110, days: 15),
            pathItem(.devCaches, "Go build cache", "Compiled package objects", "~/Library/Caches/go-build", 1_120 * mb, count: 8_840, days: 5),
            pathItem(.devCaches, "CocoaPods", "Pod specs and downloads", "~/Library/Caches/CocoaPods", 942 * mb, count: 12_002, days: 64),
            pathItem(.devCaches, "pip", "Wheel and HTTP cache", "~/Library/Caches/pip", 820 * mb, count: 3_301, days: 41),
            pathItem(.devCaches, "Cargo registry", "Crate sources (re-downloaded on build)", "~/.cargo/registry", 2_240 * mb, count: 39_870, days: 22, safety: .review, recommended: false),
        ]
    }

    private static func xcode() -> [CleanupItem] {
        [
            pathItem(.xcode, "Sweep", "DerivedData", "~/Library/Developer/Xcode/DerivedData/Sweep-bcdefghijklmnop", 1_870 * mb, count: 14_200, days: 0.3),
            pathItem(.xcode, "Wallet", "DerivedData", "~/Library/Developer/Xcode/DerivedData/Wallet-aqzkxjvuyhbdtp", 3_310 * mb, count: 26_004, days: 18),
            pathItem(.xcode, "Storefront iOS", "DerivedData", "~/Library/Developer/Xcode/DerivedData/StorefrontiOS-hgfedcbazyxwvu", 2_480 * mb, count: 21_870, days: 47),
            pathItem(.xcode, "iOS 17.5 (21F90)", "Device support files", "~/Library/Developer/Xcode/iOS DeviceSupport/iPhone15,2 17.5 (21F90)", 4_820 * mb, count: 3_002, days: 140),
            pathItem(.xcode, "iOS 16.4 (20E247)", "Device support files", "~/Library/Developer/Xcode/iOS DeviceSupport/iPhone14,5 16.4 (20E247)", 3_910 * mb, count: 2_870, days: 420),
            pathItem(.xcode, "Simulator caches", "CoreSimulator caches", "~/Library/Developer/CoreSimulator/Caches", 2_310 * mb, count: 1_440, days: 6),
            CleanupItem(id: "xcode:unavailable-simulators", category: .xcode, title: "Unavailable simulators", detail: "7 simulators for runtimes that are no longer installed", path: nil, size: 6_140 * mb, itemCount: 7, lastModified: daysAgo(210), safety: .safe, recommended: true, action: .deleteUnavailableSimulators),
            pathItem(.xcode, "Archives from 2023", "App archives with dSYMs", "~/Library/Developer/Xcode/Archives/2023", 1_830 * mb, count: 22, days: 380, safety: .review, recommended: false),
        ]
    }

    private static func buildArtifacts() -> [CleanupItem] {
        [
            pathItem(.buildArtifacts, "node_modules", "storefront", "~/projects/storefront/node_modules", 1_240 * mb, count: 88_120, days: 2),
            pathItem(.buildArtifacts, "node_modules", "dashboard", "~/projects/dashboard/node_modules", 862 * mb, count: 61_400, days: 54),
            pathItem(.buildArtifacts, "target", "api-gateway (Rust)", "~/projects/api-gateway/target", 3_410 * mb, count: 12_870, days: 9),
            pathItem(.buildArtifacts, ".next", "blog", "~/projects/blog/.next", 421 * mb, count: 3_204, days: 31),
            pathItem(.buildArtifacts, "build", "android-app (Gradle)", "~/projects/android-app/app/build", 1_120 * mb, count: 9_870, days: 77),
            pathItem(.buildArtifacts, "__pycache__", "ml-lab", "~/projects/ml-lab/__pycache__", 38 * mb, count: 410, days: 120),
            pathItem(.buildArtifacts, ".build", "swift-collections", "~/projects/swift-collections/.build", 694 * mb, count: 5_420, days: 160),
        ]
    }

    private static func docker() -> [CleanupItem] {
        [
            dockerItem("<none>:<none>", "Dangling images · 14 layers", 2_310 * mb, action: .removeImage(id: "sha256:9f2a"), days: 40),
            dockerItem("node:20-bookworm", "Unused image", 1_100 * mb, action: .removeImage(id: "sha256:1a7b"), days: 63),
            dockerItem("postgres:15", "Unused image", 425 * mb, action: .removeImage(id: "sha256:77cd"), days: 95, safety: .review, recommended: false),
            dockerItem("redis-dev", "Stopped container (redis:7)", 64 * mb, action: .removeContainer(id: "c0ffee"), days: 30),
            dockerItem("pgdata_old", "Unused volume", 3_210 * mb, action: .removeVolume(name: "pgdata_old"), days: 180, safety: .caution, recommended: false),
            dockerItem("Build cache", "BuildKit cache", 5_620 * mb, action: .pruneBuildCache, days: 3),
        ]
    }

    private static func misc() -> [CleanupItem] {
        logsAndTrash() + installersAndLargeFiles() + duplicatesAndLeftovers() + backupsAndClutter()
    }

    private static func logsAndTrash() -> [CleanupItem] {
        let trash = CleanupItem(id: "trash:user", category: .trash, title: "Trash", detail: "132 items", path: home + "/.Trash", size: 2_840 * mb, itemCount: 132, lastModified: daysAgo(5), safety: .safe, recommended: true, action: .emptyTrash([home + "/.Trash"]))
        let logs: [CleanupItem] = [
            pathItem(.logs, "User logs", "Diagnostic logs", "~/Library/Logs", 322 * mb, count: 1_240, days: 1),
            pathItem(.logs, "Crash reports", "DiagnosticReports", "~/Library/Logs/DiagnosticReports", 141 * mb, count: 380, days: 4),
            pathItem(.logs, "System logs", "Shared diagnostic logs", "/Library/Logs", 214 * mb, count: 820, days: 2, safety: .review, recommended: false),
        ]
        return logs + [trash]
    }

    private static func installersAndLargeFiles() -> [CleanupItem] {
        [
            pathItem(.installers, "Xcode_15.4.xip", "Downloaded installer", "~/Downloads/Xcode_15.4.xip", 7_210 * mb, days: 150),
            pathItem(.installers, "Docker.dmg", "Disk image", "~/Downloads/Docker.dmg", 611 * mb, days: 90),
            pathItem(.installers, "googlechrome.dmg", "Disk image", "~/Downloads/googlechrome.dmg", 221 * mb, days: 300),
            pathItem(.installers, "zoomusInstallerFull.pkg", "Installer package", "~/Downloads/zoomusInstallerFull.pkg", 95 * mb, days: 240),
            pathItem(.largeOld, "Screen Recording 2023-04-11.mov", "Not opened in 18 months", "~/Movies/Screen Recording 2023-04-11 at 10.02.14.mov", 6_420 * mb, days: 550, safety: .review, recommended: false),
            pathItem(.largeOld, "ubuntu-22.04-desktop-amd64.iso", "Not opened in a year", "~/Downloads/ubuntu-22.04-desktop-amd64.iso", 4_710 * mb, days: 400, safety: .review, recommended: false),
            pathItem(.largeOld, "Backup-2021.zip", "Not opened in 3 years", "~/Documents/Backup-2021.zip", 12_100 * mb, days: 1_100, safety: .caution, recommended: false),
        ]
    }

    private static func duplicatesAndLeftovers() -> [CleanupItem] {
        [
            pathItem(.duplicates, "design-assets.zip", "2 identical copies", "~/Downloads/design-assets (1).zip", 1_310 * mb, count: 2, days: 70, safety: .review, recommended: false),
            pathItem(.duplicates, "IMG_4021.HEIC", "3 identical copies", "~/Pictures/Exports/IMG_4021 copy.HEIC", 24 * mb, count: 3, days: 200, safety: .review, recommended: false),
            pathItem(.duplicates, "Quarterly Report.pdf", "2 identical copies", "~/Desktop/Quarterly Report copy.pdf", 18 * mb, count: 2, days: 30, safety: .review, recommended: false),
            pathItem(.appLeftovers, "Adobe Creative Cloud", "Support files of a removed app", "~/Library/Application Support/Adobe", 1_920 * mb, count: 8_210, days: 260, safety: .review, recommended: true, bundle: "com.adobe.acc.AdobeCreativeCloud"),
            pathItem(.appLeftovers, "Sketch", "Support files of a removed app", "~/Library/Application Support/com.bohemiancoding.sketch3", 420 * mb, count: 1_102, days: 410, safety: .review, recommended: true, bundle: "com.bohemiancoding.sketch3"),
            pathItem(.mailAttachments, "Mail Downloads", "Attachments opened from Mail", "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads", 762 * mb, count: 1_940, days: 8, bundle: "com.apple.mail"),
        ]
    }

    private static func backupsAndClutter() -> [CleanupItem] {
        [
            pathItem(.iosBackups, "iPhone backup (Mar 2022)", "Backup of an old iPhone", "~/Library/Application Support/MobileSync/Backup/00008030-001A2B3C4D5E", 18_400 * mb, count: 140_220, days: 900, safety: .caution, recommended: false),
            pathItem(.iosBackups, "iPad Software Update", "Downloaded iPadOS firmware", "~/Library/iTunes/iPad Software Updates/iPad_64bit_17.4.ipsw", 5_910 * mb, days: 300),
            pathItem(.systemClutter, ".DS_Store files", "Finder view settings", "~/.DS_Store", 12 * mb, count: 2_402, days: 1),
            pathItem(.systemClutter, "Old temporary files", "Older than 3 days", "/private/var/folders/xy/T", 540 * mb, count: 4_310, days: 14),
        ]
    }

    private static func bulkBuildArtifacts() -> [CleanupItem] {
        (0..<1_500).map(bulkItem)
    }

    private static func bulkItem(_ index: Int) -> CleanupItem {
        let megabytes = Int64(20 + (index * 37) % 400)
        let name = "experiment-\(index)"
        return pathItem(.buildArtifacts, "node_modules", name, "~/projects/archive/\(name)/node_modules", megabytes * mb, count: 1_000 + index, days: Double(index % 400))
    }
}
#endif

import CoreServices
import Foundation

struct JunkAnalyzer {
    let walk: WalkResult
    let factory: ItemFactory
    let home: String

    init(walk: WalkResult, home: String, now: Date = Date()) {
        self.walk = walk
        self.home = home
        self.factory = ItemFactory(tree: walk.tree, home: home, now: now)
    }

    private var tree: SpaceTree { walk.tree }

    func analyze() -> [CleanupItem] {
        var items: [CleanupItem] = []
        items += appLeftoverItems()
        items += libraryCaches()
        items += chromiumStyleCaches()
        items += developerCaches()
        items += dotCacheFolders()
        items += xcodeItems()
        items += logItems()
        items += trashItem()
        items += mailAttachmentItems()
        items += iosItems()
        items += temporaryFileItems()
        items += dsStoreItem()
        items += installerItems()
        items += buildArtifactItems()
        items += largeOldFileItems()
        return removingOverlaps(items)
    }

    func removingOverlaps(_ items: [CleanupItem], claimed: inout ClaimedPaths) -> [CleanupItem] {
        items.compactMap { item in
            guard case .removePaths(let paths) = item.action else { return item }
            let free = paths.filter { !claimed.covers($0) }
            if free.count == paths.count {
                claimed.claim(paths)
                return item
            }
            guard !free.isEmpty, paths.count > 1 else { return nil }
            claimed.claim(free)
            return factory.groupItem(id: item.id, paths: free, category: item.category, title: item.title, detail: item.detail, safety: item.safety, recommended: item.recommended, displayPath: item.path, bundleIdentifier: item.bundleIdentifier)
        }
    }

    private func removingOverlaps(_ items: [CleanupItem]) -> [CleanupItem] {
        var claimed = ClaimedPaths()
        return removingOverlaps(items, claimed: &claimed)
    }

    private func libraryCaches() -> [CleanupItem] {
        factory.children(of: home + "/Library/Caches").compactMap { path in
            let name = (path as NSString).lastPathComponent
            if name.hasPrefix("com.tungpham.sweep") { return nil }
            if KnownLocations.xcodeCacheNames.contains(name) {
                return factory.pathItem(path: path, category: .xcode, title: "Xcode cache · \(name)", detail: "Xcode rebuilds this cache", safety: .safe, recommended: true)
            }
            if KnownLocations.developerCacheNames.contains(name) {
                return factory.pathItem(path: path, category: .devCaches, title: "\(name) cache", detail: "Developer tool cache · rebuilt on demand", safety: .safe, recommended: true)
            }
            let isApple = name.hasPrefix("com.apple.")
            let bundleID = looksLikeBundleIdentifier(name) ? name : nil
            return factory.pathItem(
                path: path,
                category: .appCaches,
                title: name,
                detail: isApple ? "macOS cache · may be in use by the system" : "App cache · quit the app before cleaning",
                safety: isApple ? .review : .safe,
                recommended: !isApple,
                bundleIdentifier: bundleID
            )
        }
    }

    private func chromiumStyleCaches() -> [CleanupItem] {
        let support = home + "/Library/Application Support"
        guard let supportNode = tree.lookup(support) else { return [] }
        var items: [CleanupItem] = []
        for app in tree.childIDs(of: supportNode) {
            let appName = tree.name(of: app)
            if appName == "MobileSync" || appName == "com.apple.TCC" { continue }
            var cachePaths: [String] = []
            collectCacheFolders(in: app, depth: 0, into: &cachePaths)
            guard !cachePaths.isEmpty else { continue }
            let item = factory.groupItem(
                id: "appsupport-cache:" + appName,
                paths: cachePaths,
                category: appName == "Code" || appName == "Cursor" || appName.hasPrefix("Code - ") || appName == "Windsurf" || appName == "VSCodium" ? .devCaches : .appCaches,
                title: "\(appName) · web caches",
                detail: plural(cachePaths.count, "cache folder") + " (Cache, Code Cache, GPUCache…) · quit the app first",
                safety: .safe,
                recommended: true,
                displayPath: support + "/" + appName,
                bundleIdentifier: looksLikeBundleIdentifier(appName) ? appName : nil
            )
            if let item { items.append(item) }
        }
        return items
    }

    private func collectCacheFolders(in node: Int32, depth: Int, into paths: inout [String]) {
        guard depth < 5 else { return }
        for child in tree.childIDs(of: node) {
            let name = tree.name(of: child)
            if KnownLocations.chromiumCacheFolderNames.contains(name) {
                paths.append(tree.path(of: child))
            } else if name == "Service Worker", let storage = tree.childIDs(of: child).first(where: { tree.name(of: $0) == "CacheStorage" }) {
                paths.append(tree.path(of: storage))
            } else if !name.hasSuffix(".app") {
                collectCacheFolders(in: child, depth: depth + 1, into: &paths)
            }
        }
    }

    private func developerCaches() -> [CleanupItem] {
        KnownLocations.developerCaches.compactMap { cache in
            factory.pathItem(
                path: home + "/" + cache.relativePath,
                category: cache.relativePath.hasSuffix("_logs") || cache.relativePath.hasSuffix("daemon") ? .logs : .devCaches,
                title: cache.title,
                detail: cache.detail,
                safety: cache.safety,
                recommended: cache.recommended
            )
        }
    }

    private func dotCacheFolders() -> [CleanupItem] {
        factory.children(of: home + "/.cache").compactMap { path in
            let name = (path as NSString).lastPathComponent
            let isModelStore = KnownLocations.reviewDotCacheNames.contains(name)
            return factory.pathItem(
                path: path,
                category: .devCaches,
                title: "~/.cache/\(name)",
                detail: isModelStore ? "Downloaded models or datasets · large to download again" : "Tool cache · rebuilt on demand",
                safety: isModelStore ? .review : .safe,
                recommended: !isModelStore
            )
        }
    }

    private func xcodeItems() -> [CleanupItem] {
        let developer = home + "/Library/Developer"
        var items: [CleanupItem] = []
        for path in factory.children(of: developer + "/Xcode/DerivedData") {
            let folder = (path as NSString).lastPathComponent
            let project = folder.split(separator: "-").dropLast().joined(separator: "-")
            let title = project.isEmpty ? folder : project
            items += [factory.pathItem(path: path, category: .xcode, title: "DerivedData · \(title)", detail: "Build products and indexes · Xcode rebuilds them", safety: .safe, recommended: true)].compactMap { $0 }
        }
        for platform in ["iOS", "watchOS", "tvOS", "visionOS", "macOS"] {
            for path in factory.children(of: developer + "/Xcode/\(platform) DeviceSupport") {
                let version = (path as NSString).lastPathComponent
                let age = factory.daysSince(factory.size(ofPath: path)?.modified)
                if let item = factory.pathItem(path: path, category: .xcode, title: "\(platform) device support \(version)", detail: "Debug symbols · Xcode copies them again when you connect that device", safety: .safe, recommended: age > 60) {
                    items.append(item)
                }
            }
        }
        for path in factory.children(of: developer + "/Xcode/Archives") {
            if let item = factory.pathItem(path: path, category: .xcode, title: "Archives from \((path as NSString).lastPathComponent)", detail: "App archives · keep them if you need to symbolicate crash logs", safety: .review, recommended: false) {
                items.append(item)
            }
        }
        let wholeFolders: [(String, String, String)] = [
            (developer + "/CoreSimulator/Caches", "Simulator caches", "Dyld and runtime caches · rebuilt on demand"),
            (developer + "/Xcode/UserData/Previews", "SwiftUI preview data", "Preview simulators · Xcode makes them again"),
            (developer + "/XCTestDevices", "Test device clones", "Clones made by parallel testing"),
            (developer + "/Xcode/Products", "Xcode products", "Built products · Xcode makes them again"),
            (developer + "/Xcode/DocumentationCache", "Documentation cache", "Xcode downloads it again"),
            (home + "/Library/Caches/com.apple.dt.Xcode.sourcecontrol.Git", "Xcode source control cache", "Rebuilt on demand"),
        ]
        for (path, title, detail) in wholeFolders {
            if let item = factory.pathItem(path: path, category: .xcode, title: title, detail: detail, safety: .safe, recommended: true) {
                items.append(item)
            }
        }
        items += unavailableSimulators(devicesPath: developer + "/CoreSimulator/Devices")
        return items
    }

    private func unavailableSimulators(devicesPath: String) -> [CleanupItem] {
        guard factory.exists(devicesPath), FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun") else { return [] }
        guard let output = ProcessRunner.run("/usr/bin/xcrun", ["simctl", "list", "devices", "unavailable", "-j"], timeout: 15),
              output.status == 0,
              let json = try? JSONSerialization.jsonObject(with: output.stdout) as? [String: Any],
              let runtimes = json["devices"] as? [String: [[String: Any]]] else { return [] }
        let udids = runtimes.values.flatMap { $0 }.compactMap { $0["udid"] as? String }
        guard !udids.isEmpty else { return [] }
        return [factory.groupItem(
            id: "simulators:unavailable",
            paths: udids.map { devicesPath + "/" + $0 },
            category: .xcode,
            title: "Unavailable simulators",
            detail: plural(udids.count, "simulator") + " whose runtime is no longer installed",
            safety: .safe,
            recommended: true,
            displayPath: devicesPath,
            action: { _ in .deleteUnavailableSimulators }
        )].compactMap { $0 }
    }

    private func logItems() -> [CleanupItem] {
        var items: [CleanupItem] = []
        let logs = home + "/Library/Logs"
        for path in factory.children(of: logs) {
            let name = (path as NSString).lastPathComponent
            let title = name == "DiagnosticReports" ? "Crash reports" : name
            if let item = factory.pathItem(path: path, category: .logs, title: title, detail: "Log files · safe to remove", safety: .safe, recommended: true, minimumBytes: 100_000, bundleIdentifier: looksLikeBundleIdentifier(name) ? name : nil) {
                items.append(item)
            }
        }
        return items
    }

    private func trashItem() -> [CleanupItem] {
        let trash = home + "/.Trash"
        let children = factory.children(of: trash)
        guard !children.isEmpty else { return [] }
        return [factory.groupItem(
            id: "trash:user",
            paths: children,
            category: .trash,
            title: "Trash",
            detail: plural(children.count, "item") + " you already moved to the Trash",
            safety: .safe,
            recommended: true,
            minimumBytes: 1,
            displayPath: trash,
            action: { .emptyTrash($0) }
        )].compactMap { $0 }
    }

    private func mailAttachmentItems() -> [CleanupItem] {
        [
            home + "/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
            home + "/Library/Mail Downloads",
        ].compactMap {
            factory.pathItem(path: $0, category: .mailAttachments, title: "Mail Downloads", detail: "Attachments Mail saved when you opened them · the originals stay in Mail", safety: .safe, recommended: true)
        }
    }

    private func iosItems() -> [CleanupItem] {
        var items: [CleanupItem] = []
        for path in factory.children(of: home + "/Library/Application Support/MobileSync/Backup") {
            let info = NSDictionary(contentsOfFile: path + "/Info.plist")
            let device = info?["Device Name"] as? String ?? "iOS device"
            let date = info?["Last Backup Date"] as? Date
            let when = date.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "unknown date"
            if let item = factory.pathItem(path: path, category: .iosBackups, title: "Backup of \(device)", detail: "Local backup from \(when) · delete only if you have a newer one", safety: .caution, recommended: false) {
                items.append(item)
            }
        }
        for folder in ["iPhone Software Updates", "iPad Software Updates", "iPod Software Updates"] {
            if let item = factory.pathItem(path: home + "/Library/iTunes/" + folder, category: .iosBackups, title: folder, detail: "Firmware files Finder downloaded · it downloads them again if needed", safety: .safe, recommended: true) {
                items.append(item)
            }
        }
        return items
    }

    private func temporaryFileItems() -> [CleanupItem] {
        guard let temp = Self.userTemporaryDirectory() else { return [] }
        let stale = factory.children(of: temp).filter { path in
            factory.daysSince(factory.size(ofPath: path)?.modified) >= 3
        }
        return [factory.groupItem(
            id: "temp:user",
            paths: stale,
            category: .systemClutter,
            title: "Old temporary files",
            detail: plural(stale.count, "item") + " older than 3 days in your temporary folder",
            safety: .safe,
            recommended: true,
            displayPath: temp
        )].compactMap { $0 }
    }

    private func dsStoreItem() -> [CleanupItem] {
        let paths = walk.findings.dsStorePaths
        guard !paths.isEmpty else { return [] }
        return [CleanupItem(
            id: "clutter:dsstore",
            category: .systemClutter,
            title: ".DS_Store files",
            detail: plural(paths.count, "Finder view settings file") + " · Finder makes them again",
            path: nil,
            size: walk.findings.dsStoreBytes,
            itemCount: paths.count,
            safety: .safe,
            recommended: false,
            action: .removePaths(paths)
        )]
    }

    private func installerItems() -> [CleanupItem] {
        walk.findings.installers.compactMap { record in
            let kind = (record.path as NSString).pathExtension.uppercased()
            let inDownloadArea = record.path.hasPrefix(home + "/Downloads/") || record.path.hasPrefix(home + "/Desktop/")
            if kind == "ISO", !inDownloadArea { return nil }
            let modified = Date(timeIntervalSince1970: TimeInterval(record.modified))
            let age = factory.daysSince(modified)
            return CleanupItem(
                id: "path:" + record.path,
                category: .installers,
                title: (record.path as NSString).lastPathComponent,
                detail: "\(kind) installer · " + factory.ageText(modified).replacingOccurrences(of: "used", with: "saved"),
                path: record.path,
                size: record.size,
                lastModified: modified,
                safety: .review,
                recommended: age > 14 && inDownloadArea,
                action: .removePaths([record.path])
            )
        }
    }

    private func largeOldFileItems() -> [CleanupItem] {
        walk.findings.bigFiles.compactMap { record in
            let lastUsedSeconds = max(record.modified, record.accessed)
            let lastUsed = Date(timeIntervalSince1970: TimeInterval(lastUsedSeconds))
            let age = factory.daysSince(lastUsed)
            let qualifies = record.size >= 1_000_000_000 || (record.size >= 250_000_000 && age >= 180)
            guard qualifies, !isInsidePackage(record.path) else { return nil }
            return CleanupItem(
                id: "path:" + record.path,
                category: .largeOld,
                title: (record.path as NSString).lastPathComponent,
                detail: "Large file · " + factory.ageText(lastUsed),
                path: record.path,
                size: record.size,
                lastModified: lastUsed,
                safety: .review,
                recommended: false,
                action: .removePaths([record.path])
            )
        }
    }

    private func isInsidePackage(_ path: String) -> Bool {
        let packageSuffixes = [".app/", ".photoslibrary/", ".musiclibrary/", ".tvlibrary/", ".fcpbundle/", ".logicx/", ".band/", ".git/", ".docker/", "/Docker.raw", ".pvm/", ".utm/", ".vmwarevm/"]
        return packageSuffixes.contains { path.contains($0) }
    }

    private func buildArtifactItems() -> [CleanupItem] {
        guard let homeNode = tree.lookup(home) ?? (tree.rootPath.hasPrefix(home) ? 0 : nil) else { return [] }
        var items: [CleanupItem] = []
        var tinyCachePaths: [String] = []
        let count = tree.nodeCount
        for index in 1..<max(1, count) {
            let node = Int32(index)
            guard let rules = KnownLocations.artifactRules[tree.name(of: node)], let parent = tree.parent(of: node) else { continue }
            guard let rule = rules.first(where: { $0.matches(walk.markers[Int(parent)]) }) else { continue }
            guard isProjectArea(node, homeNode: homeNode), !hasArtifactAncestor(node) else { continue }
            let path = tree.path(of: node)
            if rule.isTinyCache {
                tinyCachePaths.append(path)
                continue
            }
            let projectPath = tree.path(of: parent)
            let projectActivity = projectLastActivity(parent, excluding: node)
            let stale = factory.daysSince(projectActivity) >= rule.staleDays
            let projectName = (projectPath as NSString).lastPathComponent
            let item = factory.pathItem(
                path: path,
                category: .buildArtifacts,
                title: "\(projectName)/\(rule.name)",
                detail: "\(rule.restoreHint) · project " + factory.ageText(projectActivity),
                safety: rule.safety,
                recommended: stale && rule.safety == .safe,
                minimumBytes: 5_000_000
            )
            if let item { items.append(item) }
        }
        if let tiny = factory.groupItem(
            id: "artifacts:tiny-caches",
            paths: tinyCachePaths,
            category: .buildArtifacts,
            title: "Python & tool caches",
            detail: plural(tinyCachePaths.count, "__pycache__, .pytest_cache or similar folder"),
            safety: .safe,
            recommended: true
        ) {
            items.append(tiny)
        }
        return items
    }

    private func projectLastActivity(_ project: Int32, excluding artifact: Int32) -> Date? {
        var newest: Date? = tree.ownNewestFiles[Int(project)] > 0 ? Date(timeIntervalSince1970: TimeInterval(tree.ownNewestFiles[Int(project)])) : nil
        for child in tree.childIDs(of: project) where child != artifact {
            let name = tree.name(of: child)
            if KnownLocations.artifactRules[name] != nil || name == ".git" { continue }
            if let modified = tree.lastModified(of: child), newest.map({ modified > $0 }) ?? true {
                newest = modified
            }
        }
        return newest ?? tree.lastModified(of: project)
    }

    private func isProjectArea(_ node: Int32, homeNode: Int32) -> Bool {
        var cursor = node
        var topBelowHome: Int32?
        while let parent = tree.parent(of: cursor) {
            if parent == homeNode {
                topBelowHome = cursor
                break
            }
            cursor = parent
        }
        if homeNode == 0, tree.rootPath != home {
            return !tree.path(of: node).contains("/Library/")
        }
        guard let top = topBelowHome else { return false }
        let topName = tree.name(of: top)
        return !topName.hasPrefix(".") && topName != "Library" && topName != "Applications"
    }

    private func hasArtifactAncestor(_ node: Int32) -> Bool {
        var cursor = tree.parent(of: node)
        while let current = cursor, current != 0 {
            if KnownLocations.artifactRules[tree.name(of: current)] != nil { return true }
            let name = tree.name(of: current)
            if name.hasSuffix(".app") || name == ".git" { return true }
            cursor = tree.parent(of: current)
        }
        return false
    }

    private func appLeftoverItems() -> [CleanupItem] {
        let library = home + "/Library"
        let sources: [(String, String)] = [
            (library + "/Containers", ""),
            (library + "/Application Support", ""),
            (library + "/Saved Application State", ".savedState"),
            (library + "/HTTPStorages", ""),
            (library + "/WebKit", ""),
        ]
        var pathsByBundle: [String: [String]] = [:]
        for (folder, suffix) in sources {
            for path in factory.children(of: folder) {
                var name = (path as NSString).lastPathComponent
                if !suffix.isEmpty {
                    guard name.hasSuffix(suffix) else { continue }
                    name = String(name.dropLast(suffix.count))
                }
                guard looksLikeBundleIdentifier(name), !isSystemBundle(name) else { continue }
                pathsByBundle[name, default: []].append(path)
            }
        }
        let leftovers = pathsByBundle.filter { !isInstalled($0.key) }
        return leftovers.compactMap { bundleID, paths in
            factory.groupItem(
                id: "leftover:" + bundleID,
                paths: paths,
                category: .appLeftovers,
                title: bundleID,
                detail: "No installed app uses \(bundleID) · " + plural(paths.count, "folder"),
                safety: .review,
                recommended: false,
                displayPath: paths.count == 1 ? paths[0] : nil,
                bundleIdentifier: bundleID
            )
        }
    }

    private func looksLikeBundleIdentifier(_ name: String) -> Bool {
        let parts = name.split(separator: ".")
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        let top = parts[0].lowercased()
        return ["com", "org", "net", "io", "app", "dev", "co", "me", "de", "uk", "us", "jp", "cn", "ru", "fr", "ch", "ai", "tv", "info", "ca", "au", "nz", "vn", "se", "nl", "it", "es", "pl"].contains(top)
    }

    private func isSystemBundle(_ bundleID: String) -> Bool {
        bundleID.hasPrefix("com.apple.") || bundleID.hasPrefix("com.tungpham.sweep")
    }

    private func isInstalled(_ bundleID: String) -> Bool {
        var candidate = bundleID
        while candidate.split(separator: ".").count >= 3 {
            if let urls = LSCopyApplicationURLsForBundleIdentifier(candidate as CFString, nil)?.takeRetainedValue() as? [URL], !urls.isEmpty {
                return true
            }
            guard let lastDot = candidate.lastIndex(of: ".") else { break }
            candidate = String(candidate[..<lastDot])
        }
        let parts = bundleID.split(separator: ".")
        if parts.count >= 2 {
            let vendorPrefix = parts.prefix(2).joined(separator: ".") + "."
            if InstalledApps.shared.bundleIdentifiers.contains(where: { $0.hasPrefix(vendorPrefix) && bundleID.lowercased().contains(($0.split(separator: ".").last ?? "").lowercased()) }) {
                return true
            }
        }
        return false
    }

    private func plural(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }

    static func userTemporaryDirectory() -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count) > 0 else { return nil }
        let path = String(cString: buffer)
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return trimmed.hasPrefix("/var/") ? "/private" + trimmed : trimmed
    }
}

struct ClaimedPaths {
    private var paths: Set<String> = []

    mutating func claim(_ newPaths: [String]) {
        paths.formUnion(newPaths)
    }

    func covers(_ path: String) -> Bool {
        var candidate = Substring(path)
        while !candidate.isEmpty {
            if paths.contains(String(candidate)) { return true }
            guard let slash = candidate.lastIndex(of: "/") else { break }
            candidate = candidate[..<slash]
        }
        return false
    }
}

final class InstalledApps: @unchecked Sendable {
    static let shared = InstalledApps()

    lazy var bundleIdentifiers: Set<String> = {
        var identifiers: Set<String> = []
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", NSHomeDirectory() + "/Applications", "/Applications/Setapp"]
        for folder in folders {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for name in names where name.hasSuffix(".app") {
                if let identifier = Bundle(path: folder + "/" + name)?.bundleIdentifier {
                    identifiers.insert(identifier)
                }
            }
        }
        return identifiers
    }()
}

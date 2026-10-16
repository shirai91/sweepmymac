import Foundation

struct ItemFactory {
    let tree: SpaceTree
    let home: String
    let now: Date

    func size(ofPath path: String) -> (bytes: Int64, files: Int, modified: Date?)? {
        if let node = tree.lookup(path) {
            return (tree.size(of: node), tree.fileCount(of: node), tree.lastModified(of: node))
        }
        guard isInsideScanRoot(path) else { return nil }
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) != S_IFDIR else { return nil }
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
        return (Int64(info.st_blocks) * 512, 1, modified)
    }

    func isInsideScanRoot(_ path: String) -> Bool {
        let root = tree.rootPath
        return root == "/" || path == root || path.hasPrefix(root + "/")
    }

    func exists(_ path: String) -> Bool {
        tree.lookup(path) != nil
    }

    func children(of path: String) -> [String] {
        guard exists(path), let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        return names.map { path + "/" + $0 }
    }

    func pathItem(
        path: String,
        category: JunkCategory,
        title: String,
        detail: String,
        safety: Safety,
        recommended: Bool,
        minimumBytes: Int64 = 1_000_000,
        bundleIdentifier: String? = nil
    ) -> CleanupItem? {
        guard let measured = size(ofPath: path), measured.bytes >= minimumBytes else { return nil }
        return CleanupItem(
            id: "path:" + path,
            category: category,
            title: title,
            detail: detail,
            path: path,
            size: measured.bytes,
            itemCount: max(1, measured.files),
            lastModified: measured.modified,
            safety: safety,
            recommended: recommended,
            action: .removePaths([path]),
            bundleIdentifier: bundleIdentifier
        )
    }

    func groupItem(
        id: String,
        paths: [String],
        category: JunkCategory,
        title: String,
        detail: String,
        safety: Safety,
        recommended: Bool,
        minimumBytes: Int64 = 1_000_000,
        displayPath: String? = nil,
        bundleIdentifier: String? = nil,
        action: (([String]) -> CleanAction)? = nil
    ) -> CleanupItem? {
        var bytes: Int64 = 0
        var files = 0
        var newest: Date?
        var kept: [String] = []
        for path in paths {
            guard let measured = size(ofPath: path) else { continue }
            bytes += measured.bytes
            files += max(1, measured.files)
            if let modified = measured.modified, newest.map({ modified > $0 }) ?? true { newest = modified }
            kept.append(path)
        }
        guard !kept.isEmpty, bytes >= minimumBytes else { return nil }
        return CleanupItem(
            id: id,
            category: category,
            title: title,
            detail: detail,
            path: displayPath ?? (kept.count == 1 ? kept[0] : nil),
            size: bytes,
            itemCount: files,
            lastModified: newest,
            safety: safety,
            recommended: recommended,
            action: action?(kept) ?? .removePaths(kept),
            bundleIdentifier: bundleIdentifier
        )
    }

    func daysSince(_ date: Date?) -> Int {
        guard let date else { return Int.max }
        return max(0, Int(now.timeIntervalSince(date) / 86_400))
    }

    func ageText(_ date: Date?) -> String {
        guard let date else { return "unknown age" }
        let days = daysSince(date)
        switch days {
        case 0: return "used today"
        case 1: return "used yesterday"
        case 2..<60: return "used \(days) days ago"
        case 60..<730: return "used \(days / 30) months ago"
        default: return "used \(days / 365) years ago"
        }
    }

    func displayPath(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

import Foundation

public struct SpaceNode: Identifiable, Hashable, Sendable {
    public let id: Int32
    public let name: String
    public let path: String
    public let size: Int64
    public let fileCount: Int
    public let directFileBytes: Int64
    public let hasChildren: Bool
    public let lastModified: Date?
}

public final class SpaceTree: @unchecked Sendable {
    let names: [String]
    let parents: [Int32]
    let totalSizes: [Int64]
    let fileCounts: [Int32]
    let ownSizes: [Int64]
    let newestFiles: [Int64]
    let ownNewestFiles: [Int64]
    let childStart: [Int32]
    let childIndex: [Int32]
    public let rootPath: String

    init(rootPath: String, names: [String], parents: [Int32], ownSizes: [Int64], ownFileCounts: [Int32], newestFiles: [Int64]? = nil) {
        self.rootPath = rootPath
        self.names = names
        self.parents = parents
        self.ownSizes = ownSizes
        let count = names.count
        var totals = ownSizes
        var files = ownFileCounts
        let ownNewest = newestFiles ?? [Int64](repeating: 0, count: names.count)
        var newest = ownNewest
        var childCounts = [Int32](repeating: 0, count: count + 1)
        if count > 1 {
            for i in stride(from: count - 1, through: 1, by: -1) {
                let p = Int(parents[i])
                totals[p] &+= totals[i]
                files[p] &+= files[i]
                if newest[i] > newest[p] { newest[p] = newest[i] }
                childCounts[p] += 1
            }
        }
        var start = [Int32](repeating: 0, count: count + 1)
        var running: Int32 = 0
        for i in 0..<count {
            start[i] = running
            running += childCounts[i]
        }
        start[count] = running
        var fill = start
        var index = [Int32](repeating: 0, count: Int(running))
        if count > 1 {
            for i in 1..<count {
                let p = Int(parents[i])
                index[Int(fill[p])] = Int32(i)
                fill[p] += 1
            }
        }
        self.totalSizes = totals
        self.fileCounts = files
        self.newestFiles = newest
        self.ownNewestFiles = ownNewest
        self.childStart = start
        self.childIndex = index
    }

    public var nodeCount: Int { names.count }

    public var root: SpaceNode { node(0) }

    public func node(_ id: Int32) -> SpaceNode {
        let i = Int(id)
        return SpaceNode(
            id: id,
            name: i == 0 ? rootPath : names[i],
            path: path(of: id),
            size: totalSizes[i],
            fileCount: Int(fileCounts[i]),
            directFileBytes: ownSizes[i],
            hasChildren: childStart[i + 1] > childStart[i],
            lastModified: lastModified(of: id)
        )
    }

    public func children(of id: Int32) -> [SpaceNode] {
        childIDs(of: id).map(node).sorted { $0.size > $1.size }
    }

    public func parent(of id: Int32) -> Int32? {
        id == 0 ? nil : parents[Int(id)]
    }

    public func size(of id: Int32) -> Int64 { totalSizes[Int(id)] }

    public func fileCount(of id: Int32) -> Int { Int(fileCounts[Int(id)]) }

    public func name(of id: Int32) -> String { names[Int(id)] }

    public func lastModified(of id: Int32) -> Date? {
        let seconds = newestFiles[Int(id)]
        return seconds > 0 ? Date(timeIntervalSince1970: TimeInterval(seconds)) : nil
    }

    func childIDs(of id: Int32) -> ArraySlice<Int32> {
        let i = Int(id)
        return childIndex[Int(childStart[i])..<Int(childStart[i + 1])]
    }

    public func path(of id: Int32) -> String {
        if id == 0 { return rootPath }
        var parts: [String] = []
        var cursor = Int(id)
        while cursor != 0 {
            parts.append(names[cursor])
            cursor = Int(parents[cursor])
        }
        let suffix = parts.reversed().joined(separator: "/")
        return rootPath == "/" ? "/" + suffix : rootPath + "/" + suffix
    }

    public func lookup(_ path: String) -> Int32? {
        let normalized = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        if normalized == rootPath { return 0 }
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        guard normalized.hasPrefix(prefix) else { return nil }
        var current: Int32 = 0
        for component in normalized.dropFirst(prefix.count).split(separator: "/") {
            guard let next = childIDs(of: current).first(where: { names[Int($0)] == component }) else { return nil }
            current = next
        }
        return current
    }

    public func ancestors(of id: Int32) -> [SpaceNode] {
        var chain: [Int32] = []
        var cursor: Int32? = id
        while let c = cursor {
            chain.append(c)
            cursor = parent(of: c)
        }
        return chain.reversed().map(node)
    }
}

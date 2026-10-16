import CryptoKit
import Foundation

struct DuplicateFinder {
    let candidates: [FileRecord]
    let home: String
    let cancel: CancelFlag
    var maximumBytesToHash: Int64 = 40_000_000_000

    func findDuplicates() -> [CleanupItem] {
        let groups = sameSizeGroups()
        guard !groups.isEmpty else { return [] }
        let sampled = groups.flatMap { group in
            split(group) { Self.sampleDigest(of: $0) }
        }
        var budget = maximumBytesToHash
        var confirmed: [[FileRecord]] = []
        for group in sampled.sorted(by: { $0[0].size > $1[0].size }) {
            guard !cancel.isCancelled else { break }
            let cost = group[0].size * Int64(group.count)
            guard cost <= budget else { continue }
            budget -= cost
            confirmed += split(group) { Self.fullDigest(of: $0) }
        }
        return confirmed.flatMap(items(for:))
    }

    private func sameSizeGroups() -> [[FileRecord]] {
        var bySize: [Int64: [FileRecord]] = [:]
        for record in candidates where !Self.isExcluded(record.path) {
            bySize[record.size, default: []].append(record)
        }
        return bySize.values.compactMap { group in
            var seen: Set<UInt64> = []
            let distinct = group.filter { seen.insert(UInt64(UInt32(bitPattern: $0.deviceID)) << 40 ^ $0.fileID).inserted }
            return distinct.count > 1 ? distinct : nil
        }
    }

    private func split(_ group: [FileRecord], by digest: @Sendable (String) -> String?) -> [[FileRecord]] {
        let digests = ConcurrentMap.map(group.map(\.path), transform: digest)
        var buckets: [String: [FileRecord]] = [:]
        for (record, value) in zip(group, digests) {
            guard let value else { continue }
            buckets[value, default: []].append(record)
        }
        return buckets.values.filter { $0.count > 1 }
    }

    private func items(for group: [FileRecord]) -> [CleanupItem] {
        let ordered = group.sorted { lhs, rhs in
            if Self.isLikelyCopy(lhs.path) != Self.isLikelyCopy(rhs.path) { return !Self.isLikelyCopy(lhs.path) }
            if lhs.modified != rhs.modified { return lhs.modified < rhs.modified }
            return lhs.path.count < rhs.path.count
        }
        let original = ordered[0]
        let originalDisplay = original.path.hasPrefix(home) ? "~" + original.path.dropFirst(home.count) : original.path
        return ordered.dropFirst().map { copy in
            CleanupItem(
                id: "dup:" + copy.path,
                category: .duplicates,
                title: (copy.path as NSString).lastPathComponent,
                detail: "Same content as \(originalDisplay)",
                path: copy.path,
                size: copy.size,
                lastModified: Date(timeIntervalSince1970: TimeInterval(copy.modified)),
                safety: .review,
                recommended: false,
                action: .removePaths([copy.path])
            )
        }
    }

    private static func isLikelyCopy(_ path: String) -> Bool {
        let name = (path as NSString).deletingPathExtension.lowercased()
        return name.hasSuffix(" copy") || name.range(of: #"\(\d+\)$"#, options: .regularExpression) != nil
            || name.range(of: #" copy \d+$"#, options: .regularExpression) != nil || path.contains("/Downloads/")
    }

    private static func isExcluded(_ path: String) -> Bool {
        let markers = [".app/", ".photoslibrary/", ".git/", "/node_modules/", ".xcarchive/", ".framework/", ".bundle/", ".musiclibrary/", "/.venv/", "/venv/"]
        return markers.contains { path.contains($0) }
    }

    static func sampleDigest(of path: String) -> String? {
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)
        var info = stat()
        guard fstat(fd, &info) == 0 else { return nil }
        let size = Int64(info.st_size)
        let chunk = 64 * 1024
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: chunk)
        let offsets: [Int64] = [0, max(0, size / 2 - Int64(chunk / 2)), max(0, size - Int64(chunk))]
        for offset in offsets {
            let count = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress, chunk, off_t(offset)) }
            guard count >= 0 else { return nil }
            buffer.withUnsafeBytes { hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[0..<count])) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func fullDigest(of path: String) -> String? {
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)
        let chunk = 4 * 1024 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 16)
        defer { buffer.deallocate() }
        var hasher = SHA256()
        while true {
            let count = read(fd, buffer, chunk)
            if count < 0 { return nil }
            if count == 0 { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: count))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum ConcurrentMap {
    static func map<Input: Sendable, Output: Sendable>(_ inputs: [Input], transform: @Sendable (Input) -> Output) -> [Output] {
        let results = UnsafeMutableBufferPointer<Output?>.allocate(capacity: inputs.count)
        results.initialize(repeating: nil)
        defer { results.deallocate() }
        inputs.withUnsafeBufferPointer { source in
            DispatchQueue.concurrentPerform(iterations: source.count) { index in
                results[index] = transform(source[index])
            }
        }
        return results.map { $0! }
    }
}

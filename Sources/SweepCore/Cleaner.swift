import Foundation

struct Cleaner {
    let mode: DeleteMode
    var docker = DockerService()
    var backgroundDeleter = BackgroundDeleter.shared
    var fastDeleter = FastDeleter()
    var maximumParallelItems = 4

    func clean(_ items: [CleanupItem], progress: @escaping @Sendable (CleanProgress) -> Void) async -> CleanReport {
        let tally = CleanTally(total: items.count)
        progress(tally.snapshot(currentTitle: items.first?.title ?? ""))
        await withTaskGroup(of: Void.self) { group in
            var iterator = items.makeIterator()
            func scheduleNext() -> Bool {
                guard let item = iterator.next() else { return false }
                group.addTask {
                    let result = await perform(item)
                    progress(tally.record(item, result: result))
                }
                return true
            }
            for _ in 0..<maximumParallelItems where !scheduleNext() { break }
            while await group.next() != nil {
                _ = scheduleNext()
            }
        }
        return tally.report(movedToTrash: mode == .moveToTrash)
    }

    func perform(_ item: CleanupItem) async -> ItemCleanResult {
        switch item.action {
        case .removePaths(let paths):
            return removeAll(paths, totalBytes: item.size, permanently: mode == .deletePermanently)
        case .emptyTrash(let paths):
            return removeAll(paths, totalBytes: item.size, permanently: true)
        case .docker(let action):
            do {
                try await docker.perform(action)
                return ItemCleanResult(outcome: .success)
            } catch {
                return ItemCleanResult(outcome: .failure(error.localizedDescription))
            }
        case .deleteUnavailableSimulators:
            guard let output = ProcessRunner.run("/usr/bin/xcrun", ["simctl", "delete", "unavailable"], timeout: 300) else {
                return ItemCleanResult(outcome: .failure("xcrun simctl did not respond"))
            }
            return ItemCleanResult(outcome: output.status == 0 ? .success : .failure(output.errorText))
        }
    }

    func emptyTrash(_ paths: [String]) -> DeletionResult {
        var failures = 0
        var firstError: String?
        for path in paths {
            guard TrashLocation.contains(path) else {
                failures += 1
                firstError = firstError ?? "\((path as NSString).lastPathComponent) is not in the Trash"
                continue
            }
            if case .failed(let reason) = deletePermanently(path, bytes: 0) {
                failures += 1
                firstError = firstError ?? reason
            }
        }
        return DeletionResult(failedEntries: failures, firstError: firstError)
    }

    private func removeAll(_ paths: [String], totalBytes: Int64, permanently: Bool) -> ItemCleanResult {
        let bytesPerPath = paths.isEmpty ? 0 : totalBytes / Int64(paths.count)
        var reasons: [String] = []
        var failedCount = 0
        var trashedPaths: [String] = []
        for path in paths {
            switch remove(path, bytes: bytesPerPath, permanently: permanently) {
            case .removed:
                continue
            case .trashed(let location):
                trashedPaths.append(location)
            case .failed(let reason):
                failedCount += 1
                if reasons.count < 3 { reasons.append(reason) }
            }
        }
        guard failedCount > 0 else { return ItemCleanResult(outcome: .success, trashedPaths: trashedPaths) }
        let summary = reasons.joined(separator: "\n")
        if failedCount == paths.count {
            return ItemCleanResult(outcome: .failure(summary), trashedPaths: trashedPaths)
        }
        let removedFraction = Double(paths.count - failedCount) / Double(paths.count)
        return ItemCleanResult(outcome: .partial("\(failedCount) of \(paths.count) could not be removed. " + summary, fractionRemoved: removedFraction), trashedPaths: trashedPaths)
    }

    private func remove(_ path: String, bytes: Int64, permanently: Bool) -> RemovalResult {
        guard !PathGuard.isProtected(path) else { return .failed("Sweep never removes \(path)") }
        var info = stat()
        guard lstat(path, &info) == 0 else {
            return errno == ENOENT ? .removed : .failed(FastDeleter.describe(errno, path))
        }
        return permanently ? deletePermanently(path, bytes: bytes) : moveToTrash(path)
    }

    private func deletePermanently(_ path: String, bytes: Int64) -> RemovalResult {
        if backgroundDeleter.stage(path, bytes: bytes) == .staged { return .removed }
        let result = fastDeleter.delete(path)
        return result.succeeded ? .removed : .failed(result.firstError ?? "\((path as NSString).lastPathComponent) could not be removed")
    }

    private func moveToTrash(_ path: String) -> RemovalResult {
        var location: NSURL?
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &location)
            return location?.path.map(RemovalResult.trashed) ?? .removed
        } catch {
            return .failed(Self.describe(error, path: path))
        }
    }

    private static func describe(_ error: Error, path: String) -> String {
        let name = (path as NSString).lastPathComponent
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteNoPermissionError || nsError.code == 513 {
            return "\(name): permission denied. Give Sweep Full Disk Access, or quit the app that uses it."
        }
        return "\(name): \(nsError.localizedDescription)"
    }
}

enum RemovalResult {
    case removed
    case trashed(String)
    case failed(String)
}

struct ItemCleanResult: Sendable {
    let outcome: CleanOutcome
    var trashedPaths: [String] = []
}

enum TrashLocation {
    static func contains(_ path: String) -> Bool {
        let normalized = (path as NSString).standardizingPath
        let userTrash = ScanPipeline.realHomeDirectory() + "/.Trash/"
        if normalized.hasPrefix(userTrash) { return true }
        let components = normalized.split(separator: "/")
        return components.count >= 4 && components[0] == "Volumes" && components[2] == ".Trashes"
    }
}

enum CleanOutcome: Sendable {
    case success
    case partial(String, fractionRemoved: Double)
    case failure(String)
}

enum PathGuard {
    static func isProtected(_ path: String) -> Bool {
        let normalized = (path as NSString).standardizingPath
        let components = normalized.split(separator: "/")
        if components.count < 3 { return true }
        let home = ScanPipeline.realHomeDirectory()
        let protectedExact: Set<String> = [
            home, home + "/Library", home + "/Documents", home + "/Desktop", home + "/Downloads", home + "/Pictures",
            home + "/Movies", home + "/Music", home + "/Applications", home + "/Library/Application Support",
            home + "/Library/Caches", home + "/Library/Containers", home + "/Library/Mobile Documents", home + "/projects",
            home + "/.Trash", home + "/Library/Developer", home + "/Library/Logs",
        ]
        if protectedExact.contains(normalized) { return true }
        let protectedTrees = ["/System", "/usr", "/bin", "/sbin", "/private/etc", "/Library/Apple", "/Applications"]
        return protectedTrees.contains { normalized == $0 || normalized.hasPrefix($0 + "/") }
    }
}

final class CleanTally: @unchecked Sendable {
    private let lock = NSLock()
    private let total: Int
    private var completed = 0
    private var bytesFreed: Int64 = 0
    private var cleaned: Set<String> = []
    private var failures: [CleanFailure] = []
    private var trashedPaths: [String] = []

    init(total: Int) { self.total = total }

    func snapshot(currentTitle: String) -> CleanProgress {
        lock.lock()
        defer { lock.unlock() }
        return CleanProgress(completed: completed, total: total, bytesFreed: bytesFreed, currentTitle: currentTitle)
    }

    func record(_ item: CleanupItem, result: ItemCleanResult) -> CleanProgress {
        lock.lock()
        defer { lock.unlock() }
        completed += 1
        trashedPaths += result.trashedPaths
        switch result.outcome {
        case .success:
            bytesFreed += item.size
            cleaned.insert(item.id)
        case .partial(let reason, let fraction):
            bytesFreed += Int64(Double(item.size) * fraction)
            failures.append(CleanFailure(id: item.id, title: item.title, reason: reason))
        case .failure(let reason):
            failures.append(CleanFailure(id: item.id, title: item.title, reason: reason))
        }
        return CleanProgress(completed: completed, total: total, bytesFreed: bytesFreed, currentTitle: item.title)
    }

    func report(movedToTrash: Bool) -> CleanReport {
        lock.lock()
        defer { lock.unlock() }
        return CleanReport(bytesFreed: bytesFreed, cleanedItemIDs: cleaned, failures: failures, movedToTrash: movedToTrash, trashedPaths: trashedPaths)
    }
}

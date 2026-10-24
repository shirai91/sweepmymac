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
                    let result = await perform(item) { bytes in
                        if let update = tally.advance(item, by: bytes) { progress(update) }
                    }
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

    func perform(_ item: CleanupItem, onFreed: @escaping FreedBytesHandler = { _ in }) async -> ItemCleanResult {
        switch item.action {
        case .removePaths(let paths):
            return removeAll(paths, totalBytes: item.size, permanently: mode == .deletePermanently, onFreed: onFreed)
        case .emptyTrash(let paths):
            return removeAll(paths, totalBytes: item.size, permanently: true, onFreed: onFreed)
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
            if case .failed(let reason) = deleteInBackground(path) {
                failures += 1
                firstError = firstError ?? reason
            }
        }
        return DeletionResult(failedEntries: failures, firstError: firstError)
    }

    private func removeAll(_ paths: [String], totalBytes: Int64, permanently: Bool, onFreed: @escaping FreedBytesHandler) -> ItemCleanResult {
        let bytesPerPath = paths.isEmpty ? 0 : totalBytes / Int64(paths.count)
        var reasons: [String] = []
        var failedCount = 0
        var trashedPaths: [String] = []
        for path in paths {
            switch remove(path, permanently: permanently, onFreed: onFreed) {
            case .removed:
                continue
            case .trashed(let location):
                onFreed(bytesPerPath)
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

    private func remove(_ path: String, permanently: Bool, onFreed: @escaping FreedBytesHandler) -> RemovalResult {
        guard !PathGuard.isProtected(path) else { return .failed("Sweep never removes \(path)") }
        var info = stat()
        guard lstat(path, &info) == 0 else {
            return errno == ENOENT ? .removed : .failed(FastDeleter.describe(errno, path))
        }
        return permanently ? deleteNow(path, onFreed: onFreed) : moveToTrash(path)
    }

    private func deleteNow(_ path: String, onFreed: @escaping FreedBytesHandler) -> RemovalResult {
        let target = backgroundDeleter.moveIntoStaging(path) ?? path
        return removalResult(of: fastDeleter.delete(target, onFreed: onFreed), path: path)
    }

    private func deleteInBackground(_ path: String) -> RemovalResult {
        if backgroundDeleter.stage(path, bytes: 0) == .staged { return .removed }
        return removalResult(of: fastDeleter.delete(path), path: path)
    }

    private func removalResult(of deletion: DeletionResult, path: String) -> RemovalResult {
        deletion.succeeded ? .removed : .failed(deletion.firstError ?? "\((path as NSString).lastPathComponent) could not be removed")
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
    private static let minimumUpdateInterval: UInt64 = 50_000_000

    private let lock = NSLock()
    private let total: Int
    private var completed = 0
    private var bytesFreed: Int64 = 0
    private var bytesProcessed: Int64 = 0
    private var freedByItemInFlight: [String: Int64] = [:]
    private var lastUpdate: UInt64 = 0
    private var cleaned: Set<String> = []
    private var failures: [CleanFailure] = []
    private var trashedPaths: [String] = []

    init(total: Int) { self.total = total }

    func snapshot(currentTitle: String) -> CleanProgress {
        lock.lock()
        defer { lock.unlock() }
        return progress(currentTitle: currentTitle)
    }

    func advance(_ item: CleanupItem, by bytes: Int64) -> CleanProgress? {
        lock.lock()
        defer { lock.unlock() }
        let alreadyFreed = freedByItemInFlight[item.id, default: 0]
        let added = min(bytes, item.size - alreadyFreed)
        guard added > 0 else { return nil }
        freedByItemInFlight[item.id] = alreadyFreed + added
        bytesFreed += added
        bytesProcessed += added
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastUpdate >= Self.minimumUpdateInterval else { return nil }
        lastUpdate = now
        return progress(currentTitle: item.title)
    }

    func record(_ item: CleanupItem, result: ItemCleanResult) -> CleanProgress {
        lock.lock()
        defer { lock.unlock() }
        completed += 1
        trashedPaths += result.trashedPaths
        let alreadyFreed = freedByItemInFlight.removeValue(forKey: item.id) ?? 0
        bytesProcessed += item.size - alreadyFreed
        switch result.outcome {
        case .success:
            bytesFreed += item.size - alreadyFreed
            cleaned.insert(item.id)
        case .partial(let reason, let fraction):
            bytesFreed += max(0, Int64(Double(item.size) * fraction) - alreadyFreed)
            failures.append(CleanFailure(id: item.id, title: item.title, reason: reason))
        case .failure(let reason):
            failures.append(CleanFailure(id: item.id, title: item.title, reason: reason))
        }
        lastUpdate = DispatchTime.now().uptimeNanoseconds
        return progress(currentTitle: item.title)
    }

    func report(movedToTrash: Bool) -> CleanReport {
        lock.lock()
        defer { lock.unlock() }
        return CleanReport(bytesFreed: bytesFreed, cleanedItemIDs: cleaned, failures: failures, movedToTrash: movedToTrash, trashedPaths: trashedPaths)
    }

    private func progress(currentTitle: String) -> CleanProgress {
        CleanProgress(completed: completed, total: total, bytesFreed: bytesFreed, bytesProcessed: bytesProcessed, currentTitle: currentTitle)
    }
}

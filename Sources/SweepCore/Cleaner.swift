import Foundation

struct Cleaner {
    let mode: DeleteMode
    var docker = DockerService()
    var maximumParallelItems = 4

    func clean(_ items: [CleanupItem], progress: @escaping @Sendable (CleanProgress) -> Void) async -> CleanReport {
        let tally = CleanTally(total: items.count)
        progress(tally.snapshot(currentTitle: items.first?.title ?? ""))
        await withTaskGroup(of: Void.self) { group in
            var iterator = items.makeIterator()
            func scheduleNext() -> Bool {
                guard let item = iterator.next() else { return false }
                group.addTask {
                    let outcome = await perform(item)
                    progress(tally.record(item, outcome: outcome))
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

    func perform(_ item: CleanupItem) async -> CleanOutcome {
        switch item.action {
        case .removePaths(let paths):
            return removeAll(paths, permanently: mode == .deletePermanently)
        case .emptyTrash(let paths):
            return removeAll(paths, permanently: true)
        case .docker(let action):
            do {
                try await docker.perform(action)
                return .success
            } catch {
                return .failure(error.localizedDescription)
            }
        case .deleteUnavailableSimulators:
            guard let output = ProcessRunner.run("/usr/bin/xcrun", ["simctl", "delete", "unavailable"], timeout: 300) else {
                return .failure("xcrun simctl did not respond")
            }
            return output.status == 0 ? .success : .failure(output.errorText)
        }
    }

    private func removeAll(_ paths: [String], permanently: Bool) -> CleanOutcome {
        var failures: [String] = []
        var failedCount = 0
        for path in paths {
            if let reason = remove(path, permanently: permanently) {
                failedCount += 1
                if failures.count < 3 { failures.append(reason) }
            }
        }
        if failedCount == 0 { return .success }
        let summary = failedCount == paths.count ? failures.joined(separator: "\n") : "\(failedCount) of \(paths.count) could not be removed. " + failures.joined(separator: "\n")
        return failedCount == paths.count ? .failure(summary) : .partial(summary, fractionRemoved: Double(paths.count - failedCount) / Double(paths.count))
    }

    private func remove(_ path: String, permanently: Bool) -> String? {
        guard !PathGuard.isProtected(path) else { return "Sweep never removes \(path)" }
        var info = stat()
        guard lstat(path, &info) == 0 else { return errno == ENOENT ? nil : String(cString: strerror(errno)) }
        let url = URL(fileURLWithPath: path)
        let manager = FileManager.default
        do {
            if permanently {
                try manager.removeItem(at: url)
            } else {
                try manager.trashItem(at: url, resultingItemURL: nil)
            }
            return nil
        } catch {
            guard permanently else { return Self.describe(error, path: path) }
            Self.makeWritable(path)
            do {
                try manager.removeItem(at: url)
                return nil
            } catch {
                return lstat(path, &info) == 0 ? Self.describe(error, path: path) : nil
            }
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

    private static func makeWritable(_ path: String) {
        chmod(path, 0o755)
        guard let enumerator = FileManager.default.enumerator(atPath: path) else { return }
        for case let relative as String in enumerator {
            let full = path + "/" + relative
            var info = stat()
            guard lstat(full, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { continue }
            chmod(full, mode_t(info.st_mode | S_IWUSR | S_IXUSR | S_IRUSR))
        }
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

    init(total: Int) { self.total = total }

    func snapshot(currentTitle: String) -> CleanProgress {
        lock.lock()
        defer { lock.unlock() }
        return CleanProgress(completed: completed, total: total, bytesFreed: bytesFreed, currentTitle: currentTitle)
    }

    func record(_ item: CleanupItem, outcome: CleanOutcome) -> CleanProgress {
        lock.lock()
        defer { lock.unlock() }
        completed += 1
        switch outcome {
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
        return CleanReport(bytesFreed: bytesFreed, cleanedItemIDs: cleaned, failures: failures, movedToTrash: movedToTrash)
    }
}

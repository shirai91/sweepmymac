import Foundation

public struct BackgroundDeletionStatus: Sendable, Equatable {
    public let pendingItems: Int
    public let pendingBytes: Int64
    public let freedBytes: Int64

    public var isIdle: Bool { pendingItems == 0 }
}

enum StagingOutcome: Equatable {
    case staged
    case unavailable
}

public final class BackgroundDeleter: @unchecked Sendable {
    public static let shared = BackgroundDeleter(stagingRoot: BackgroundDeleter.defaultStagingRoot)

    static var defaultStagingRoot: String {
        ScanPipeline.realHomeDirectory() + "/Library/Caches/com.tungpham.sweep/Deleting"
    }

    private struct Job {
        let path: String
        let bytes: Int64
    }

    let stagingRoot: String
    private let deleter: FastDeleter
    private let lock = NSLock()
    private var jobs: [Job] = []
    private var pendingBytes: Int64 = 0
    private var freedBytes: Int64 = 0
    private var workerRunning = false
    private var jobsInProgress = 0
    private var observers: [UUID: AsyncStream<BackgroundDeletionStatus>.Continuation] = [:]
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    init(stagingRoot: String, deleter: FastDeleter = FastDeleter()) {
        self.stagingRoot = stagingRoot
        self.deleter = deleter
    }

    public var status: BackgroundDeletionStatus {
        lock.lock()
        defer { lock.unlock() }
        return currentStatus()
    }

    public func statusUpdates() -> AsyncStream<BackgroundDeletionStatus> {
        AsyncStream { continuation in
            let token = UUID()
            lock.lock()
            observers[token] = continuation
            let snapshot = currentStatus()
            lock.unlock()
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.observers[token] = nil
                self.lock.unlock()
            }
        }
    }

    public func resumePendingDeletions() {
        guard let leftovers = try? FileManager.default.contentsOfDirectory(atPath: stagingRoot), !leftovers.isEmpty else { return }
        enqueue(leftovers.map { Job(path: stagingRoot + "/" + $0, bytes: 0) })
    }

    public func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if jobs.isEmpty && !workerRunning {
                lock.unlock()
                continuation.resume()
                return
            }
            idleWaiters.append(continuation)
            lock.unlock()
        }
    }

    func stage(_ path: String, bytes: Int64) -> StagingOutcome {
        guard prepareStagingRoot(), isOnStagingVolume(path) else { return .unavailable }
        let name = UUID().uuidString + "-" + (path as NSString).lastPathComponent
        let destination = stagingRoot + "/" + name
        guard rename(path, destination) == 0 else { return .unavailable }
        enqueue([Job(path: destination, bytes: bytes)])
        return .staged
    }

    private func prepareStagingRoot() -> Bool {
        var info = stat()
        if lstat(stagingRoot, &info) == 0 {
            return (info.st_mode & S_IFMT) == S_IFDIR
        }
        do {
            try FileManager.default.createDirectory(atPath: stagingRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            return true
        } catch {
            return false
        }
    }

    private func isOnStagingVolume(_ path: String) -> Bool {
        var item = stat()
        var staging = stat()
        guard lstat(path, &item) == 0, stat(stagingRoot, &staging) == 0 else { return false }
        return item.st_dev == staging.st_dev
    }

    private func enqueue(_ newJobs: [Job]) {
        lock.lock()
        jobs.append(contentsOf: newJobs)
        pendingBytes += newJobs.reduce(0) { $0 + $1.bytes }
        let shouldStart = !workerRunning
        workerRunning = true
        let snapshot = currentStatus()
        let listeners = Array(observers.values)
        lock.unlock()
        listeners.forEach { $0.yield(snapshot) }
        guard shouldStart else { return }
        let worker = Thread { [self] in drain() }
        worker.name = "sweep.background-delete"
        worker.qualityOfService = .utility
        worker.start()
    }

    private func drain() {
        while let job = nextJob() {
            _ = deleter.delete(job.path)
            finish(job)
        }
    }

    private func nextJob() -> Job? {
        lock.lock()
        defer { lock.unlock() }
        guard !jobs.isEmpty else {
            workerRunning = false
            let waiters = idleWaiters
            idleWaiters = []
            waiters.forEach { $0.resume() }
            return nil
        }
        jobsInProgress = 1
        return jobs.removeFirst()
    }

    private func finish(_ job: Job) {
        lock.lock()
        jobsInProgress = 0
        pendingBytes = jobs.isEmpty ? 0 : pendingBytes - job.bytes
        freedBytes += job.bytes
        let snapshot = currentStatus()
        let listeners = Array(observers.values)
        lock.unlock()
        listeners.forEach { $0.yield(snapshot) }
    }

    private func currentStatus() -> BackgroundDeletionStatus {
        BackgroundDeletionStatus(pendingItems: jobs.count + jobsInProgress, pendingBytes: pendingBytes, freedBytes: freedBytes)
    }
}

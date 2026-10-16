import Foundation

public final class SweepEngine: @unchecked Sendable {
    private let cancelFlag = CancelFlag()

    public init() {}

    public func cancel() { cancelFlag.cancel() }

    public func scan(scope: ScanScope, progress: @escaping @Sendable (ScanProgress) -> Void) async -> ScanReport {
        cancelFlag.reset()
        let flag = cancelFlag
        return await Task.detached(priority: .userInitiated) {
            await ScanPipeline(scope: scope, cancel: flag, progress: progress).run()
        }.value
    }

    public func clean(_ items: [CleanupItem], mode: DeleteMode, progress: @escaping @Sendable (CleanProgress) -> Void) async -> CleanReport {
        await Task.detached(priority: .userInitiated) {
            await Cleaner(mode: mode).clean(items, progress: progress)
        }.value
    }

    public static func hasFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let probes = [
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
            home + "/Library/Safari/Bookmarks.plist",
            home + "/Library/Containers/com.apple.stocks",
        ]
        for probe in probes {
            let fd = open(probe, O_RDONLY)
            if fd >= 0 {
                close(fd)
                return true
            }
        }
        return false
    }

    public static let fullDiskAccessSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func reset() {
        lock.lock()
        cancelled = false
        lock.unlock()
    }
}

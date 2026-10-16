import Foundation

public struct DeletionResult: Sendable, Equatable {
    public let failedEntries: Int
    public let firstError: String?

    public var succeeded: Bool { failedEntries == 0 }

    public init(failedEntries: Int, firstError: String?) {
        self.failedEntries = failedEntries
        self.firstError = firstError
    }

    static let success = DeletionResult(failedEntries: 0, firstError: nil)
}

public struct FastDeleter: Sendable {
    public var threadCount: Int

    public init(threadCount: Int = 4) {
        self.threadCount = max(1, threadCount)
    }

    public func delete(_ path: String) -> DeletionResult {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            return errno == ENOENT ? .success : DeletionResult(failedEntries: 1, firstError: Self.describe(errno, path))
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            guard unlink(path) == 0 || errno == ENOENT else {
                return DeletionResult(failedEntries: 1, firstError: Self.describe(errno, path))
            }
            return .success
        }
        let run = TreeDeletion(root: path)
        run.removeFiles(threads: threadCount)
        run.removeDirectories()
        run.restorePermissionsOfSurvivors()
        return run.result
    }

    static func describe(_ code: Int32, _ path: String) -> String {
        "\((path as NSString).lastPathComponent): \(String(cString: strerror(code)))"
    }
}

private final class TreeDeletion: @unchecked Sendable {
    private struct Directory {
        let path: String
        let depth: Int
    }

    private struct PermissionChange {
        let path: String
        let originalMode: mode_t
    }

    private let condition = NSCondition()
    private var pending: [Directory]
    private var directories: [Directory]
    private var activeWorkers = 0
    private var failures = 0
    private var firstError: String?
    private var permissionChanges: [PermissionChange] = []

    init(root: String) {
        let rootDirectory = Directory(path: root, depth: 0)
        pending = [rootDirectory]
        directories = [rootDirectory]
    }

    var result: DeletionResult {
        DeletionResult(failedEntries: failures, firstError: firstError)
    }

    func removeFiles(threads: Int) {
        let group = DispatchGroup()
        for _ in 0..<threads {
            group.enter()
            let worker = Thread { [self] in
                while let directory = nextDirectory() {
                    let found = emptyFiles(of: directory)
                    finish(found)
                }
                group.leave()
            }
            worker.qualityOfService = Thread.current.qualityOfService
            worker.start()
        }
        group.wait()
    }

    func removeDirectories() {
        let byDepth = Dictionary(grouping: directories, by: \.depth)
        for depth in byDepth.keys.sorted(by: >) {
            let level = byDepth[depth] ?? []
            DispatchQueue.concurrentPerform(iterations: level.count) { index in
                let path = level[index].path
                if rmdir(path) != 0, errno != ENOENT {
                    recordFailure(errno, path)
                }
            }
        }
    }

    func restorePermissionsOfSurvivors() {
        for change in permissionChanges.reversed() {
            fchmodat(AT_FDCWD, change.path, change.originalMode, AT_SYMLINK_NOFOLLOW)
        }
    }

    private func nextDirectory() -> Directory? {
        condition.lock()
        defer { condition.unlock() }
        while pending.isEmpty && activeWorkers > 0 {
            condition.wait()
        }
        guard let next = pending.popLast() else {
            condition.broadcast()
            return nil
        }
        activeWorkers += 1
        return next
    }

    private func finish(_ subdirectories: [Directory]) {
        condition.lock()
        pending.append(contentsOf: subdirectories)
        directories.append(contentsOf: subdirectories)
        activeWorkers -= 1
        condition.broadcast()
        condition.unlock()
    }

    private func emptyFiles(of directory: Directory) -> [Directory] {
        guard let fd = openGrantingAccess(directory.path) else { return [] }
        defer { close(fd) }
        var subdirectories: [Directory] = []
        var files: [String] = []
        for (name, isDirectory) in Self.entries(of: fd) {
            if isDirectory {
                subdirectories.append(Directory(path: directory.path + "/" + name, depth: directory.depth + 1))
            } else {
                files.append(name)
            }
        }
        var grantedWriteAccess = false
        for name in files {
            if unlinkat(fd, name, 0) == 0 || errno == ENOENT { continue }
            let code = errno
            guard (code == EACCES || code == EPERM), !grantedWriteAccess else {
                recordFailure(code, directory.path + "/" + name)
                continue
            }
            grantedWriteAccess = true
            grantOwnerAccess(descriptor: fd, path: directory.path)
            if unlinkat(fd, name, 0) != 0, errno != ENOENT {
                recordFailure(errno, directory.path + "/" + name)
            }
        }
        if !subdirectories.isEmpty {
            grantOwnerAccess(descriptor: fd, path: directory.path)
        }
        return subdirectories
    }

    private func openGrantingAccess(_ path: String) -> Int32? {
        let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        var fd = open(path, flags)
        if fd < 0, errno == EACCES {
            var info = stat()
            if lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR {
                let original = info.st_mode & 0o7777
                if fchmodat(AT_FDCWD, path, original | S_IRWXU, AT_SYMLINK_NOFOLLOW) == 0 {
                    remember(PermissionChange(path: path, originalMode: original))
                    fd = open(path, flags)
                }
            }
        }
        guard fd >= 0 else {
            if errno != ENOENT { recordFailure(errno, path) }
            return nil
        }
        return fd
    }

    private func grantOwnerAccess(descriptor fd: Int32, path: String) {
        var info = stat()
        guard fstat(fd, &info) == 0 else { return }
        let original = info.st_mode & 0o7777
        guard original & S_IRWXU != S_IRWXU, fchmod(fd, original | S_IRWXU) == 0 else { return }
        remember(PermissionChange(path: path, originalMode: original))
    }

    private static func entries(of fd: Int32) -> [(String, Bool)] {
        let duplicate = dup(fd)
        guard duplicate >= 0, let stream = fdopendir(duplicate) else {
            if duplicate >= 0 { close(duplicate) }
            return []
        }
        defer { closedir(stream) }
        var found: [(String, Bool)] = []
        while let entry = readdir(stream) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                String(decoding: raw.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            if name == "." || name == ".." { continue }
            var isDirectory = entry.pointee.d_type == DT_DIR
            if entry.pointee.d_type == DT_UNKNOWN {
                var info = stat()
                isDirectory = fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
            }
            found.append((name, isDirectory))
        }
        return found
    }

    private func remember(_ change: PermissionChange) {
        condition.lock()
        permissionChanges.append(change)
        condition.unlock()
    }

    private func recordFailure(_ code: Int32, _ path: String) {
        condition.lock()
        failures += 1
        if firstError == nil { firstError = FastDeleter.describe(code, path) }
        condition.unlock()
    }
}

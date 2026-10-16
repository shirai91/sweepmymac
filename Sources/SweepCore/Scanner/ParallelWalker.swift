import Foundation
import Synchronization

struct ProjectMarkers: OptionSet, Sendable {
    let rawValue: UInt32

    static let nodePackage = ProjectMarkers(rawValue: 1 << 0)
    static let cargo = ProjectMarkers(rawValue: 1 << 1)
    static let cocoaPods = ProjectMarkers(rawValue: 1 << 2)
    static let swiftPackage = ProjectMarkers(rawValue: 1 << 3)
    static let gradle = ProjectMarkers(rawValue: 1 << 4)
    static let python = ProjectMarkers(rawValue: 1 << 5)
    static let flutter = ProjectMarkers(rawValue: 1 << 6)
    static let goModule = ProjectMarkers(rawValue: 1 << 7)
    static let maven = ProjectMarkers(rawValue: 1 << 8)
    static let xcodeProject = ProjectMarkers(rawValue: 1 << 9)
    static let composer = ProjectMarkers(rawValue: 1 << 10)
    static let ruby = ProjectMarkers(rawValue: 1 << 11)
    static let cmake = ProjectMarkers(rawValue: 1 << 12)
    static let elixir = ProjectMarkers(rawValue: 1 << 13)
    static let terraform = ProjectMarkers(rawValue: 1 << 14)
    static let dotnet = ProjectMarkers(rawValue: 1 << 15)
    static let vcs = ProjectMarkers(rawValue: 1 << 16)

    static let byFileName: [String: ProjectMarkers] = [
        "package.json": .nodePackage,
        "Cargo.toml": .cargo,
        "Podfile": .cocoaPods,
        "Package.swift": .swiftPackage,
        "build.gradle": .gradle,
        "build.gradle.kts": .gradle,
        "settings.gradle": .gradle,
        "settings.gradle.kts": .gradle,
        "gradlew": .gradle,
        "pyproject.toml": .python,
        "setup.py": .python,
        "setup.cfg": .python,
        "requirements.txt": .python,
        "Pipfile": .python,
        "tox.ini": .python,
        "pubspec.yaml": .flutter,
        "go.mod": .goModule,
        "pom.xml": .maven,
        "composer.json": .composer,
        "Gemfile": .ruby,
        "CMakeLists.txt": .cmake,
        "mix.exs": .elixir,
        "main.tf": .terraform,
        ".terraform.lock.hcl": .terraform,
        ".git": .vcs,
    ]

    static func forEntry(named name: String, isDirectory: Bool) -> ProjectMarkers {
        if let marker = byFileName[name] { return marker }
        if isDirectory, name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") { return .xcodeProject }
        if !isDirectory, name.hasSuffix(".csproj") || name.hasSuffix(".sln") || name.hasSuffix(".fsproj") { return .dotnet }
        return []
    }
}

struct FileRecord: Sendable {
    let path: String
    let size: Int64
    let modified: Int64
    let accessed: Int64
    let fileID: UInt64
    let deviceID: Int32
}

struct WalkerFindings: Sendable {
    var bigFiles: [FileRecord] = []
    var installers: [FileRecord] = []
    var dsStorePaths: [String] = []
    var dsStoreBytes: Int64 = 0

    mutating func absorb(_ other: WalkerFindings) {
        bigFiles += other.bigFiles
        installers += other.installers
        dsStorePaths += other.dsStorePaths
        dsStoreBytes += other.dsStoreBytes
    }
}

struct WalkResult: Sendable {
    let tree: SpaceTree
    let markers: [ProjectMarkers]
    let findings: WalkerFindings
    let files: Int
    let directories: Int
    let bytes: Int64
    let inaccessible: Int
}

struct WalkConfiguration: Sendable {
    var root: String
    var skippedPaths: Set<String>
    var userAreaPrefix: String
    var excludedUserAreaPaths: Set<String>
    var bigFileThreshold: Int64 = 10 * 1_000_000
    var installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]
}

final class ParallelWalker: @unchecked Sendable {
    private struct Job {
        let node: Int32
        let name: String
        let path: String
        let inUserArea: Bool
    }

    private struct Subdirectory {
        let name: String
        let path: String
        let inUserArea: Bool
    }

    private struct DirectoryContents {
        var ownBytes: Int64 = 0
        var fileCount: Int32 = 0
        var newestFile: Int64 = 0
        var markers = ProjectMarkers()
        var subdirectories: [Subdirectory] = []
        var readable = true
    }

    private let configuration: WalkConfiguration
    private let cancel: CancelFlag
    private let condition = NSCondition()
    private var stack: [Job] = []
    private var activeWorkers = 0
    private var finished = false
    private var sharedTarget = 32
    private let maximumLocalDepth = 40

    private var names: [String] = []
    private var parents: [Int32] = []
    private var ownBytes: [Int64] = []
    private var fileCounts: [Int32] = []
    private var newestFiles: [Int64] = []
    private var markers: [ProjectMarkers] = []
    private var inaccessible = 0

    let filesSeen = Atomic<Int>(0)
    let directoriesSeen = Atomic<Int>(0)
    let bytesSeen = Atomic<Int64>(0)
    private let currentPathBox = Mutex<String>("")
    private let hardLinkKeys = Mutex<Set<UInt64>>([])

    init(configuration: WalkConfiguration, cancel: CancelFlag) {
        self.configuration = configuration
        self.cancel = cancel
    }

    var currentPath: String { currentPathBox.withLock { $0 } }

    static var defaultWorkerCount: Int {
        if let override = ProcessInfo.processInfo.environment["SWEEP_WORKERS"].flatMap(Int.init), override > 0 { return override }
        return max(4, ProcessInfo.processInfo.activeProcessorCount)
    }

    func run(workerCount: Int = ParallelWalker.defaultWorkerCount) -> WalkResult {
        let rootInUserArea = isUserArea(configuration.root)
        Self.raiseOpenFileLimit()
        sharedTarget = workerCount * 3
        appendNode(name: configuration.root, parent: 0)
        stack.append(Job(node: 0, name: configuration.root, path: configuration.root, inUserArea: rootInUserArea))

        let findingsBox = Mutex(WalkerFindings())
        let group = DispatchGroup()
        for index in 0..<workerCount {
            group.enter()
            let thread = Thread { [self] in
                let local = workerLoop()
                findingsBox.withLock { $0.absorb(local) }
                group.leave()
            }
            thread.name = "sweep.walker.\(index)"
            thread.qualityOfService = .userInitiated
            thread.stackSize = 1 << 20
            thread.start()
        }
        group.wait()

        let tree = SpaceTree(rootPath: configuration.root, names: names, parents: parents, ownSizes: ownBytes, ownFileCounts: fileCounts, newestFiles: newestFiles)
        return WalkResult(
            tree: tree,
            markers: markers,
            findings: findingsBox.withLock { $0 },
            files: filesSeen.load(ordering: .relaxed),
            directories: directoriesSeen.load(ordering: .relaxed),
            bytes: bytesSeen.load(ordering: .relaxed),
            inaccessible: inaccessible
        )
    }

    private static func raiseOpenFileLimit() {
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return }
        let wanted = min(rlim_t(10_240), limit.rlim_max)
        guard limit.rlim_cur < wanted else { return }
        limit.rlim_cur = wanted
        setrlimit(RLIMIT_NOFILE, &limit)
    }

    private func workerLoop() -> WalkerFindings {
        let reader = BulkDirectoryReader()
        var findings = WalkerFindings()
        var processed = 0
        var job = nextJob(finishedPrevious: false)
        while let current = job {
            let fd = BulkDirectoryReader.openDirectory(current.path)
            walk(current, descriptor: fd, depth: 0, reader: reader, findings: &findings, processed: &processed)
            if fd >= 0 { close(fd) }
            job = nextJob(finishedPrevious: true)
        }
        return findings
    }

    private func walk(_ job: Job, descriptor fd: Int32, depth: Int, reader: BulkDirectoryReader, findings: inout WalkerFindings, processed: inout Int) {
        var contents = DirectoryContents()
        if fd < 0 {
            contents.readable = false
        } else if !cancel.isCancelled {
            contents = enumerate(job, descriptor: fd, reader: reader, findings: &findings)
        }
        processed += 1
        if processed & 255 == 0 {
            currentPathBox.withLock { $0 = job.path }
        }
        let localJobs = commit(contents, for: job, keepLocal: depth < maximumLocalDepth)
        for child in localJobs {
            let childDescriptor = BulkDirectoryReader.openDirectory(named: child.name, in: fd)
            walk(child, descriptor: childDescriptor, depth: depth + 1, reader: reader, findings: &findings, processed: &processed)
            if childDescriptor >= 0 { close(childDescriptor) }
        }
    }

    private func nextJob(finishedPrevious: Bool) -> Job? {
        condition.lock()
        defer { condition.unlock() }
        if finishedPrevious { activeWorkers -= 1 }
        while true {
            if let next = stack.popLast() {
                activeWorkers += 1
                return next
            }
            if activeWorkers == 0 || finished {
                finished = true
                condition.broadcast()
                return nil
            }
            condition.wait()
        }
    }

    private func commit(_ contents: DirectoryContents, for job: Job, keepLocal: Bool) -> [Job] {
        condition.lock()
        defer { condition.unlock() }
        let index = Int(job.node)
        ownBytes[index] = contents.ownBytes
        fileCounts[index] = contents.fileCount
        newestFiles[index] = contents.newestFile
        markers[index] = contents.markers
        if !contents.readable { inaccessible += 1 }
        guard !contents.subdirectories.isEmpty else { return [] }
        var local: [Job] = []
        var shared = 0
        for subdirectory in contents.subdirectories {
            let child = appendNode(name: subdirectory.name, parent: job.node)
            let childJob = Job(node: child, name: subdirectory.name, path: subdirectory.path, inUserArea: subdirectory.inUserArea)
            if keepLocal && stack.count >= sharedTarget {
                local.append(childJob)
            } else {
                stack.append(childJob)
                shared += 1
            }
        }
        if shared == 1 { condition.signal() } else if shared > 1 { condition.broadcast() }
        return local
    }

    @discardableResult
    private func appendNode(name: String, parent: Int32) -> Int32 {
        let index = Int32(names.count)
        names.append(name)
        parents.append(parent)
        ownBytes.append(0)
        fileCounts.append(0)
        newestFiles.append(0)
        markers.append([])
        return index
    }

    private func enumerate(_ job: Job, descriptor fd: Int32, reader: BulkDirectoryReader, findings: inout WalkerFindings) -> DirectoryContents {
        var contents = DirectoryContents()
        let base = job.path == "/" ? "" : job.path
        var files = 0
        var bytes: Int64 = 0
        reader.read(descriptor: fd) { entry in
            let marker = ProjectMarkers.forEntry(named: entry.name, isDirectory: entry.isDirectory)
            if !marker.isEmpty { contents.markers.insert(marker) }
            if entry.isDirectory {
                let childPath = base + "/" + entry.name
                if !configuration.skippedPaths.contains(childPath) {
                    let childInUserArea = job.inUserArea ? !isExcludedChild(named: entry.name, path: childPath, parent: job.path) : childPath == configuration.userAreaPrefix
                    contents.subdirectories.append(Subdirectory(name: entry.name, path: childPath, inUserArea: childInUserArea))
                }
                return
            }
            files += 1
            var size = entry.allocatedSize
            if entry.linkCount > 1, entry.objectType == ObjectType.regular, !claimHardLink(entry) {
                size = 0
            }
            contents.ownBytes += size
            bytes += size
            if entry.modificationTime > contents.newestFile { contents.newestFile = entry.modificationTime }
            guard job.inUserArea else { return }
            collectFinding(entry, size: size, base: base, into: &findings)
        }
        contents.fileCount = Int32(files)
        filesSeen.add(files, ordering: .relaxed)
        directoriesSeen.add(1, ordering: .relaxed)
        bytesSeen.add(bytes, ordering: .relaxed)
        return contents
    }

    private func collectFinding(_ entry: RawEntry, size: Int64, base: String, into findings: inout WalkerFindings) {
        if entry.name == ".DS_Store" {
            findings.dsStorePaths.append(base + "/" + entry.name)
            findings.dsStoreBytes += size
            return
        }
        let isBig = size >= configuration.bigFileThreshold
        let isInstaller = size >= 1_000_000 && hasInstallerExtension(entry.name)
        guard isBig || isInstaller else { return }
        let record = FileRecord(path: base + "/" + entry.name, size: size, modified: entry.modificationTime, accessed: entry.accessTime, fileID: entry.fileID, deviceID: entry.deviceID)
        if isBig { findings.bigFiles.append(record) }
        if isInstaller { findings.installers.append(record) }
    }

    private func hasInstallerExtension(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: ".") else { return false }
        return configuration.installerExtensions.contains(name[name.index(after: dot)...].lowercased())
    }

    private func claimHardLink(_ entry: RawEntry) -> Bool {
        let key = (UInt64(UInt32(bitPattern: entry.deviceID)) << 40) ^ entry.fileID
        return hardLinkKeys.withLock { $0.insert(key).inserted }
    }

    private func isUserArea(_ path: String) -> Bool {
        let prefix = configuration.userAreaPrefix
        guard path == prefix || path.hasPrefix(prefix + "/") else { return false }
        return !configuration.excludedUserAreaPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
            && !isInsideHiddenHomeFolder(path)
    }

    private func isInsideHiddenHomeFolder(_ path: String) -> Bool {
        let prefix = configuration.userAreaPrefix + "/"
        guard path.hasPrefix(prefix) else { return false }
        return path.dropFirst(prefix.count).hasPrefix(".")
    }

    private func isExcludedChild(named name: String, path: String, parent: String) -> Bool {
        if parent == configuration.userAreaPrefix, name.hasPrefix(".") { return true }
        return configuration.excludedUserAreaPaths.contains(path)
    }
}

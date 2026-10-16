import Foundation

struct ScanPipeline {
    let scope: ScanScope
    let cancel: CancelFlag
    let progress: @Sendable (ScanProgress) -> Void

    func run() async -> ScanReport {
        let started = Date()
        let home = Self.realHomeDirectory()
        let configuration = Self.configuration(for: scope, home: home)
        let walker = ParallelWalker(configuration: configuration, cancel: cancel)

        let dockerTask = Task.detached(priority: .utility) { () -> (DockerStatus, [CleanupItem]) in
            let service = DockerService()
            let status = await service.status()
            guard status.running else { return (status, []) }
            return (status, await service.findJunk())
        }

        let reporter = startReporter(walker: walker, started: started)
        let walk = await Self.runOnDedicatedThread { walker.run() }
        reporter.cancel()

        let walkProgress = ScanProgress(phase: .analyzing, filesScanned: walk.files, directoriesScanned: walk.directories, bytesScanned: walk.bytes, currentPath: "", elapsed: Date().timeIntervalSince(started))
        progress(walkProgress)

        let analyzer = JunkAnalyzer(walk: walk, home: home)
        var items = cancel.isCancelled ? [] : analyzer.analyze()

        if !cancel.isCancelled {
            var phase = walkProgress
            phase.phase = .duplicates
            phase.elapsed = Date().timeIntervalSince(started)
            progress(phase)
            var claimed = ClaimedPaths()
            claimed.claim(items.flatMap(Self.paths(of:)))
            let candidates = walk.findings.bigFiles.filter { !claimed.covers($0.path) }
            let duplicates = DuplicateFinder(candidates: candidates, home: home, cancel: cancel).findDuplicates()
            let largeOldIDs = Set(duplicates.map(\.id).map { "path:" + $0.dropFirst(4) })
            items.removeAll { $0.category == .largeOld && largeOldIDs.contains($0.id) }
            items += duplicates
        }

        var phase = walkProgress
        phase.phase = .docker
        phase.elapsed = Date().timeIntervalSince(started)
        progress(phase)
        let (dockerStatus, dockerItems) = cancel.isCancelled ? (DockerStatus(installed: false, running: false, message: nil), []) : await dockerTask.value
        dockerTask.cancel()
        items += dockerItems
        items.sort { $0.size > $1.size }

        let stats = ScanStats(files: walk.files, directories: walk.directories, bytes: walk.bytes, inaccessibleDirectories: walk.inaccessible, duration: Date().timeIntervalSince(started))
        var done = walkProgress
        done.phase = .done
        done.elapsed = stats.duration
        progress(done)
        return ScanReport(items: items, tree: walk.tree, stats: stats, volume: VolumeInfo.forPath(configuration.root), docker: dockerStatus)
    }

    private func startReporter(walker: ParallelWalker, started: Date) -> Task<Void, Never> {
        let progress = progress
        return Task.detached(priority: .utility) {
            while !Task.isCancelled {
                progress(ScanProgress(
                    phase: .walking,
                    filesScanned: walker.filesSeen.load(ordering: .relaxed),
                    directoriesScanned: walker.directoriesSeen.load(ordering: .relaxed),
                    bytesScanned: walker.bytesSeen.load(ordering: .relaxed),
                    currentPath: walker.currentPath,
                    elapsed: Date().timeIntervalSince(started)
                ))
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    private static func paths(of item: CleanupItem) -> [String] {
        switch item.action {
        case .removePaths(let paths), .emptyTrash(let paths): paths
        default: item.path.map { [$0] } ?? []
        }
    }

    static func runOnDedicatedThread<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let thread = Thread {
                continuation.resume(returning: work())
            }
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    static func realHomeDirectory() -> String {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return String(cString: directory)
        }
        return NSHomeDirectory()
    }

    static func configuration(for scope: ScanScope, home: String) -> WalkConfiguration {
        let root: String
        switch scope {
        case .entireDisk: root = "/"
        case .home: root = home
        case .folder(let path): root = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        }
        return WalkConfiguration(
            root: root,
            skippedPaths: skippedPaths(scanningFrom: root),
            userAreaPrefix: home,
            excludedUserAreaPaths: [home + "/Library", home + "/Applications"]
        )
    }

    static func skippedPaths(scanningFrom root: String) -> Set<String> {
        var skipped: Set<String> = ["/System/Volumes", "/Volumes", "/dev", "/net", "/home", "/cores", "/.vol", "/.nofollow", "/.resolve"]
        var mounts: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&mounts, MNT_NOWAIT)
        if count > 0, let mounts {
            for index in 0..<Int(count) {
                var entry = mounts[index]
                let mountPoint = withUnsafeBytes(of: &entry.f_mntonname) { raw in
                    String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
                }
                if mountPoint != "/" && mountPoint != "/System/Volumes/Data" {
                    skipped.insert(mountPoint)
                }
            }
        }
        skipped.remove(root)
        return skipped
    }
}

import XCTest
@testable import SweepCore

final class ScannerTests: XCTestCase {
    private var root: String!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("sweep-tests-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        root = URL(fileURLWithPath: base).resolvingSymlinksInPath().path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    private func write(_ relative: String, bytes: Int, fill: UInt8 = 0x41, modified: Date? = nil) throws {
        let path = root + "/" + relative
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(repeating: fill, count: bytes).write(to: URL(fileURLWithPath: path))
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: path)
        }
    }

    private func allocatedSize(_ relative: String) throws -> Int64 {
        let values = try URL(fileURLWithPath: root + "/" + relative).resourceValues(forKeys: [.totalFileAllocatedSizeKey])
        return Int64(values.totalFileAllocatedSize ?? 0)
    }

    private func walk(userArea: String? = nil) -> WalkResult {
        let configuration = WalkConfiguration(root: root, skippedPaths: [], userAreaPrefix: userArea ?? root, excludedUserAreaPaths: [root + "/Library"])
        return ParallelWalker(configuration: configuration, cancel: CancelFlag()).run(workerCount: 4)
    }

    func testBulkReaderMatchesFileManager() throws {
        try write("a.bin", bytes: 10_000)
        try write("b.bin", bytes: 200_000)
        try FileManager.default.createDirectory(atPath: root + "/sub", withIntermediateDirectories: true)
        var seen: [String: RawEntry] = [:]
        XCTAssertTrue(BulkDirectoryReader().read(directory: root) { seen[$0.name] = $0 })
        XCTAssertEqual(Set(seen.keys), ["a.bin", "b.bin", "sub"])
        XCTAssertEqual(seen["a.bin"]?.allocatedSize, try allocatedSize("a.bin"))
        XCTAssertEqual(seen["b.bin"]?.allocatedSize, try allocatedSize("b.bin"))
        XCTAssertTrue(seen["sub"]?.isDirectory ?? false)
        XCTAssertFalse(seen["a.bin"]?.isDirectory ?? true)
        XCTAssertGreaterThan(seen["a.bin"]?.modificationTime ?? 0, 1_600_000_000)
    }

    func testBulkReaderHandlesManyEntriesAcrossBufferRefills() throws {
        for index in 0..<3_000 {
            try write("many/file-with-a-fairly-long-name-\(index).txt", bytes: 1)
        }
        var count = 0
        XCTAssertTrue(BulkDirectoryReader(capacity: 16 * 1024).read(directory: root + "/many") { _ in count += 1 })
        XCTAssertEqual(count, 3_000)
    }

    func testWalkerTotalsMatchAllocatedSizes() throws {
        let files = ["x/1.bin": 5_000, "x/y/2.bin": 70_000, "x/y/z/3.bin": 300_000, "4.bin": 1_000]
        var expected: Int64 = 0
        for (name, size) in files {
            try write(name, bytes: size)
            expected += try allocatedSize(name)
        }
        let result = walk()
        XCTAssertEqual(result.files, files.count)
        XCTAssertEqual(result.tree.root.size, expected)
        XCTAssertEqual(result.bytes, expected)
        let y = try XCTUnwrap(result.tree.lookup(root + "/x/y"))
        XCTAssertEqual(result.tree.size(of: y), try allocatedSize("x/y/2.bin") + allocatedSize("x/y/z/3.bin"))
        XCTAssertEqual(result.tree.path(of: y), root + "/x/y")
        XCTAssertEqual(result.tree.children(of: 0).first?.name, "x")
    }

    func testWalkerCountsHardLinksOnce() throws {
        try write("original.bin", bytes: 100_000)
        try FileManager.default.linkItem(atPath: root + "/original.bin", toPath: root + "/link.bin")
        let result = walk()
        XCTAssertEqual(result.tree.root.size, try allocatedSize("original.bin"))
    }

    func testWalkerRecordsProjectMarkersAndFindings() throws {
        try write("projects/web/package.json", bytes: 10)
        try write("projects/web/node_modules/lib/index.js", bytes: 10)
        try write("Downloads/Tool.dmg", bytes: 2_000_000)
        try write("Downloads/.DS_Store", bytes: 10)
        try write("Library/Caches/big.bin", bytes: 12_000_000)
        let result = walk()
        let web = try XCTUnwrap(result.tree.lookup(root + "/projects/web"))
        XCTAssertTrue(result.markers[Int(web)].contains(.nodePackage))
        XCTAssertEqual(result.findings.installers.map(\.path), [root + "/Downloads/Tool.dmg"])
        XCTAssertEqual(result.findings.dsStorePaths, [root + "/Downloads/.DS_Store"])
        XCTAssertTrue(result.findings.bigFiles.isEmpty, "files under Library are not user files")
    }

    func testWalkerSkipsConfiguredPaths() throws {
        try write("keep/a.bin", bytes: 10)
        try write("skip/b.bin", bytes: 10)
        let configuration = WalkConfiguration(root: root, skippedPaths: [root + "/skip"], userAreaPrefix: root, excludedUserAreaPaths: [])
        let result = ParallelWalker(configuration: configuration, cancel: CancelFlag()).run(workerCount: 2)
        XCTAssertNil(result.tree.lookup(root + "/skip"))
        XCTAssertEqual(result.files, 1)
    }

    func testAnalyzerFindsJunkInFakeHome() throws {
        let old = Date().addingTimeInterval(-120 * 86_400)
        try write("projects/old-app/package.json", bytes: 10, modified: old)
        try write("projects/old-app/node_modules/react/index.js", bytes: 6_000_000, modified: old)
        try write("projects/fresh-app/package.json", bytes: 10)
        try write("projects/fresh-app/node_modules/react/index.js", bytes: 6_000_000)
        try write("projects/not-node/node_modules/x.js", bytes: 6_000_000)
        try write("projects/rusty/Cargo.toml", bytes: 10)
        try write("projects/rusty/target/debug/app", bytes: 6_000_000)
        try write("projects/py/__pycache__/a.pyc", bytes: 2_000_000)
        try write("Library/Caches/com.example.editor/blob", bytes: 2_000_000)
        try write("Library/Caches/Homebrew/downloads/x.tar.gz", bytes: 2_000_000)
        try write("Library/Logs/SomeApp/log.txt", bytes: 200_000)
        try write(".Trash/old.zip", bytes: 50_000)
        try write("Downloads/Setup.dmg", bytes: 3_000_000, modified: old)
        try write("Library/Application Support/Slack/Cache/data_1", bytes: 2_000_000)
        try write("Library/Application Support/Slack/Service Worker/CacheStorage/x", bytes: 2_000_000)
        try write(".npm/_cacache/content/x", bytes: 2_000_000)

        let items = JunkAnalyzer(walk: walk(), home: root).analyze()
        func item(at relative: String) -> CleanupItem? { items.first { $0.path == root + "/" + relative } }

        let oldModules = try XCTUnwrap(item(at: "projects/old-app/node_modules"))
        XCTAssertEqual(oldModules.category, .buildArtifacts)
        XCTAssertTrue(oldModules.recommended)
        let freshModules = try XCTUnwrap(item(at: "projects/fresh-app/node_modules"))
        XCTAssertFalse(freshModules.recommended)
        XCTAssertNil(item(at: "projects/not-node/node_modules"), "node_modules without package.json is ignored")
        XCTAssertEqual(item(at: "projects/rusty/target")?.category, .buildArtifacts)
        XCTAssertEqual(items.first { $0.id == "artifacts:tiny-caches" }?.itemCount, 1)
        XCTAssertEqual(item(at: "Library/Caches/com.example.editor")?.category, .appCaches)
        XCTAssertEqual(item(at: "Library/Caches/com.example.editor")?.bundleIdentifier, "com.example.editor")
        XCTAssertEqual(item(at: "Library/Caches/Homebrew")?.category, .devCaches)
        XCTAssertEqual(item(at: "Library/Logs/SomeApp")?.category, .logs)
        XCTAssertEqual(items.first { $0.category == .trash }?.action, .emptyTrash([root + "/.Trash/old.zip"]))
        XCTAssertEqual(item(at: "Downloads/Setup.dmg")?.category, .installers)
        XCTAssertTrue(item(at: "Downloads/Setup.dmg")?.recommended ?? false)
        XCTAssertEqual(item(at: ".npm/_cacache")?.category, .devCaches)
        let slack = try XCTUnwrap(items.first { $0.id == "appsupport-cache:Slack" })
        guard case .removePaths(let slackPaths) = slack.action else { return XCTFail("wrong action") }
        XCTAssertEqual(Set(slackPaths), [root + "/Library/Application Support/Slack/Cache", root + "/Library/Application Support/Slack/Service Worker/CacheStorage"])
    }

    func testAnalyzerNeverReturnsOverlappingPaths() throws {
        try write("projects/a/package.json", bytes: 10)
        try write("projects/a/node_modules/.cache/big.bin", bytes: 30_000_000)
        try write("projects/a/node_modules/pkg/__pycache__/x.pyc", bytes: 2_000_000)
        let items = JunkAnalyzer(walk: walk(), home: root).analyze()
        let paths = items.compactMap(\.path)
        for path in paths {
            XCTAssertFalse(paths.contains { $0 != path && path.hasPrefix($0 + "/") }, "\(path) is inside another item")
        }
        XCTAssertEqual(items.filter { $0.category == .buildArtifacts }.count, 1)
    }

    func testDuplicateFinderKeepsOneCopy() throws {
        try write("docs/report.pdf", bytes: 11_000_000, fill: 7, modified: Date().addingTimeInterval(-1000))
        try write("Downloads/report (1).pdf", bytes: 11_000_000, fill: 7)
        try write("docs/other.pdf", bytes: 11_000_000, fill: 9)
        let result = walk()
        let duplicates = DuplicateFinder(candidates: result.findings.bigFiles, home: root, cancel: CancelFlag()).findDuplicates()
        XCTAssertEqual(duplicates.map(\.path), [root + "/Downloads/report (1).pdf"])
        XCTAssertEqual(duplicates.first?.category, .duplicates)
    }

    func testCleanerRemovesPathsPermanentlyAndReportsMissingAsSuccess() async throws {
        try write("junk/a/b.bin", bytes: 1000)
        try write("junk/c.bin", bytes: 1000)
        let item = CleanupItem(id: "t", category: .appCaches, title: "t", detail: "", path: nil, size: 2000, safety: .safe, recommended: true, action: .removePaths([root + "/junk/a", root + "/junk/c.bin", root + "/junk/missing"]))
        let report = await Cleaner(mode: .deletePermanently).clean([item]) { _ in }
        XCTAssertEqual(report.cleanedItemIDs, ["t"])
        XCTAssertEqual(report.bytesFreed, 2000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root + "/junk/a"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root + "/junk/c.bin"))
    }

    func testCleanerRemovesReadOnlyTrees() async throws {
        try write("gomod/pkg/mod/x/file.go", bytes: 100)
        chmod(root + "/gomod/pkg/mod/x/file.go", 0o444)
        chmod(root + "/gomod/pkg/mod/x", 0o555)
        let item = CleanupItem(id: "go", category: .devCaches, title: "go", detail: "", path: root + "/gomod/pkg/mod", size: 100, safety: .review, recommended: false, action: .removePaths([root + "/gomod/pkg/mod"]))
        let report = await Cleaner(mode: .deletePermanently).clean([item]) { _ in }
        XCTAssertTrue(report.failures.isEmpty, "\(report.failures.map(\.reason))")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root + "/gomod/pkg/mod"))
    }

    func testCleanerDoesNotChangePermissionsThroughSymlinks() async throws {
        try write("outside/keep.txt", bytes: 10)
        chmod(root + "/outside", 0o555)
        defer { chmod(root + "/outside", 0o755) }
        try write("cache/locked/file.bin", bytes: 10)
        try FileManager.default.createSymbolicLink(atPath: root + "/cache/locked/link", withDestinationPath: root + "/outside")
        chmod(root + "/cache/locked", 0o555)
        let item = CleanupItem(id: "c", category: .appCaches, title: "c", detail: "", path: root + "/cache", size: 10, safety: .safe, recommended: true, action: .removePaths([root + "/cache"]))
        let report = await Cleaner(mode: .deletePermanently).clean([item]) { _ in }
        XCTAssertTrue(report.failures.isEmpty, "\(report.failures.map(\.reason))")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root + "/cache"))
        let outside = try FileManager.default.attributesOfItem(atPath: root + "/outside")
        XCTAssertEqual((outside[.posixPermissions] as? NSNumber)?.intValue, 0o555)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root + "/outside/keep.txt"))
    }

    func testPathGuardBlocksImportantFolders() {
        let home = ScanPipeline.realHomeDirectory()
        XCTAssertTrue(PathGuard.isProtected("/"))
        XCTAssertTrue(PathGuard.isProtected("/Users"))
        XCTAssertTrue(PathGuard.isProtected(home))
        XCTAssertTrue(PathGuard.isProtected(home + "/Documents"))
        XCTAssertTrue(PathGuard.isProtected(home + "/Library/Caches/../"))
        XCTAssertTrue(PathGuard.isProtected("/System/Library/Caches/x"))
        XCTAssertTrue(PathGuard.isProtected("/Applications/Safari.app"))
        XCTAssertFalse(PathGuard.isProtected(home + "/Library/Caches/com.example.app"))
        XCTAssertFalse(PathGuard.isProtected(home + "/projects/app/node_modules"))
    }

    func testCleanerRefusesProtectedPath() async {
        let item = CleanupItem(id: "bad", category: .appCaches, title: "bad", detail: "", path: "/Applications", size: 1, safety: .safe, recommended: true, action: .removePaths(["/Applications"]))
        let report = await Cleaner(mode: .deletePermanently).clean([item]) { _ in }
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: "/Applications"))
    }

    func testSkippedPathsIncludeOtherVolumesButNotRoot() {
        let skipped = ScanPipeline.skippedPaths(scanningFrom: "/")
        XCTAssertTrue(skipped.contains("/System/Volumes"))
        XCTAssertTrue(skipped.contains("/Volumes"))
        XCTAssertFalse(skipped.contains("/"))
        XCTAssertFalse(skipped.contains("/System/Volumes/Data"))
    }
}

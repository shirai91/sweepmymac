import XCTest
@testable import SweepCore

final class DeletionTests: XCTestCase {
    private var root: String!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("sweep-delete-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        root = URL(fileURLWithPath: base).resolvingSymlinksInPath().path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    private func makeTree(at relative: String, folders: Int, filesPerFolder: Int) throws {
        for folder in 0..<folders {
            let directory = root + "/\(relative)/pkg\(folder % 7)/sub\(folder)/deep"
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            for file in 0..<filesPerFolder {
                FileManager.default.createFile(atPath: directory + "/f\(file).js", contents: Data("x".utf8))
            }
        }
    }

    func testFastDeleterRemovesLargeTree() throws {
        try makeTree(at: "node_modules", folders: 200, filesPerFolder: 25)
        let result = FastDeleter(threadCount: 4).delete(root + "/node_modules")
        XCTAssertTrue(result.succeeded, result.firstError ?? "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root + "/node_modules"))
    }

    func testFastDeleterHandlesFilesMissingPathsAndSymlinks() throws {
        FileManager.default.createFile(atPath: root + "/single.bin", contents: Data(count: 10))
        XCTAssertTrue(FastDeleter().delete(root + "/single.bin").succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root + "/single.bin"))
        XCTAssertTrue(FastDeleter().delete(root + "/does-not-exist").succeeded)

        try FileManager.default.createDirectory(atPath: root + "/outside", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: root + "/outside/keep.txt", contents: Data("keep".utf8))
        try FileManager.default.createDirectory(atPath: root + "/cache", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: root + "/cache/link", withDestinationPath: root + "/outside")
        XCTAssertTrue(FastDeleter().delete(root + "/cache").succeeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root + "/outside/keep.txt"))
    }

    func testFastDeleterRemovesReadOnlyAndUnreadableFolders() throws {
        try makeTree(at: "mod", folders: 3, filesPerFolder: 2)
        let locked = root + "/mod/pkg0/sub0/deep"
        chmod(locked + "/f0.js", 0o444)
        chmod(locked, 0o555)
        chmod(root + "/mod/pkg1/sub1/deep", 0o000)
        let result = FastDeleter().delete(root + "/mod")
        XCTAssertTrue(result.succeeded, result.firstError ?? "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root + "/mod"))
    }

    func testFastDeleterRestoresPermissionsWhenItCannotFinish() throws {
        try makeTree(at: "stuck", folders: 1, filesPerFolder: 1)
        let directory = root + "/stuck/pkg0/sub0/deep"
        chflags(directory + "/f0.js", UInt32(UF_IMMUTABLE))
        defer { chflags(directory + "/f0.js", 0) }
        chmod(directory, 0o555)
        let result = FastDeleter().delete(root + "/stuck")
        XCTAssertFalse(result.succeeded)
        let mode = (try FileManager.default.attributesOfItem(atPath: directory)[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(mode, 0o555)
        chmod(directory, 0o755)
    }

    func testStagingMakesItemDisappearAtOnceAndDeletesInBackground() async throws {
        try makeTree(at: "big", folders: 50, filesPerFolder: 20)
        let deleter = BackgroundDeleter(stagingRoot: root + "/.staging")
        let started = Date()
        XCTAssertEqual(deleter.stage(root + "/big", bytes: 1_000), .staged)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root + "/big"))
        await deleter.waitUntilIdle()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root + "/.staging"), [])
        XCTAssertEqual(deleter.status, BackgroundDeletionStatus(pendingItems: 0, pendingBytes: 0, freedBytes: 1_000))
    }

    func testStatusUpdatesReachObservers() async throws {
        try makeTree(at: "watched", folders: 5, filesPerFolder: 5)
        let deleter = BackgroundDeleter(stagingRoot: root + "/.staging")
        let updates = deleter.statusUpdates()
        XCTAssertEqual(deleter.stage(root + "/watched", bytes: 500), .staged)
        var sawFreed = false
        for await status in updates where status.isIdle && status.freedBytes == 500 {
            sawFreed = true
            break
        }
        XCTAssertTrue(sawFreed)
    }

    func testResumeDeletesLeftoversFromAnEarlierRun() async throws {
        try makeTree(at: ".staging/old-run-item", folders: 3, filesPerFolder: 3)
        let deleter = BackgroundDeleter(stagingRoot: root + "/.staging")
        deleter.resumePendingDeletions()
        await deleter.waitUntilIdle()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root + "/.staging"), [])
    }

    func testStagingIsRefusedOnAnotherVolume() throws {
        let deleter = BackgroundDeleter(stagingRoot: root + "/.staging")
        XCTAssertEqual(deleter.stage("/dev/null", bytes: 0), .unavailable)
    }

    func testTrashLocation() {
        let home = ScanPipeline.realHomeDirectory()
        XCTAssertTrue(TrashLocation.contains(home + "/.Trash/old.zip"))
        XCTAssertTrue(TrashLocation.contains("/Volumes/USB/.Trashes/501/x"))
        XCTAssertFalse(TrashLocation.contains(home + "/.Trash"))
        XCTAssertFalse(TrashLocation.contains(home + "/.Trash/../Documents/x"))
        XCTAssertFalse(TrashLocation.contains(home + "/Documents/x"))
    }

    func testEmptyTrashRefusesPathsOutsideTrash() throws {
        FileManager.default.createFile(atPath: root + "/precious.txt", contents: Data("x".utf8))
        let result = Cleaner(mode: .deletePermanently).emptyTrash([root + "/precious.txt"])
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root + "/precious.txt"))
    }

    func testMoveToTrashReportsTrashedPathsAndEmptyTrashDeletesOnlyThose() async throws {
        let name = "sweep-test-\(UUID().uuidString).txt"
        FileManager.default.createFile(atPath: root + "/" + name, contents: Data("x".utf8))
        let item = CleanupItem(id: "t", category: .appCaches, title: "t", detail: "", path: root + "/" + name, size: 1, safety: .safe, recommended: true, action: .removePaths([root + "/" + name]))
        let report = await Cleaner(mode: .moveToTrash).clean([item]) { _ in }
        XCTAssertEqual(report.trashedPaths.count, 1)
        let trashed = try XCTUnwrap(report.trashedPaths.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashed))
        let staging = BackgroundDeleter(stagingRoot: root + "/.staging")
        var cleaner = Cleaner(mode: .deletePermanently)
        cleaner.backgroundDeleter = staging
        XCTAssertTrue(cleaner.emptyTrash(report.trashedPaths).succeeded)
        await staging.waitUntilIdle()
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashed))
    }
}

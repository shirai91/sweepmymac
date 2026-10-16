import Foundation
@testable import SweepCore
import XCTest

final class SizeParserDockerTests: XCTestCase {
    func testDecimalUnits() {
        XCTAssertEqual(DockerSizeParser.bytes(from: "4.24GB"), 4_240_000_000)
        XCTAssertEqual(DockerSizeParser.bytes(from: "737.9kB"), 737_900)
        XCTAssertEqual(DockerSizeParser.bytes(from: "737.9KB"), 737_900)
        XCTAssertEqual(DockerSizeParser.bytes(from: "68.84MB"), 68_840_000)
        XCTAssertEqual(DockerSizeParser.bytes(from: "1.5TB"), 1_500_000_000_000)
        XCTAssertEqual(DockerSizeParser.bytes(from: "34B"), 34)
        XCTAssertEqual(DockerSizeParser.bytes(from: "0B"), 0)
    }

    func testPercentSuffixIsIgnored() {
        XCTAssertEqual(DockerSizeParser.bytes(from: "33.98GB (78%)"), 33_980_000_000)
        XCTAssertEqual(DockerSizeParser.bytes(from: "2.13MB (96%)"), 2_130_000)
        XCTAssertEqual(DockerSizeParser.bytes(from: "4.1kB (virtual 437MB)"), 4_100)
    }

    func testUnparsableValuesAreZero() {
        XCTAssertEqual(DockerSizeParser.bytes(from: "N/A"), 0)
        XCTAssertEqual(DockerSizeParser.bytes(from: ""), 0)
        XCTAssertEqual(DockerSizeParser.bytes(from: "   "), 0)
        XCTAssertEqual(DockerSizeParser.bytes(from: "12XB"), 0)
    }

    func testWhitespaceAndBareNumbers() {
        XCTAssertEqual(DockerSizeParser.bytes(from: " 17.22GB \n"), 17_220_000_000)
        XCTAssertEqual(DockerSizeParser.bytes(from: "1.2 GB"), 1_200_000_000)
        XCTAssertEqual(DockerSizeParser.bytes(from: "512"), 512)
    }

    func testBinaryUnits() {
        XCTAssertEqual(DockerSizeParser.bytes(from: "1KiB"), 1_024)
        XCTAssertEqual(DockerSizeParser.bytes(from: "2GiB"), 2_147_483_648)
    }

    func testDisplayString() {
        XCTAssertEqual(DockerSizeParser.displayString("4.24GB"), "4.24 GB")
        XCTAssertEqual(DockerSizeParser.displayString("2.996GB"), "2.996 GB")
        XCTAssertEqual(DockerSizeParser.displayString("737.9kB"), "737.9 kB")
        XCTAssertEqual(DockerSizeParser.displayString("33.98GB (78%)"), "33.98 GB")
        XCTAssertEqual(DockerSizeParser.displayString("N/A"), "0 B")
    }
}

final class JunkParserDockerTests: XCTestCase {
    private let now = JunkParserDockerTests.date("2026-10-16 12:00:00 +0700")

    func testDanglingImageIsSafeAndRecommended() throws {
        let items = parse(images: [
            image(id: "sha256:ef32de1a9e0011223344556677889900aabbccddeeff00112233445566778899", repository: "<none>", tag: "<none>", containers: "0", size: "4.24GB", unique: "2.996GB"),
        ])
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(item.id, "docker:image:sha256:ef32de1a9e0011223344556677889900aabbccddeeff00112233445566778899")
        XCTAssertEqual(item.title, "Untagged image ef32de1a9e00")
        XCTAssertEqual(item.safety, .safe)
        XCTAssertTrue(item.recommended)
        XCTAssertEqual(item.size, 2_996_000_000)
        XCTAssertEqual(item.category, .docker)
        XCTAssertNil(item.path)
        XCTAssertEqual(item.itemCount, 1)
        XCTAssertEqual(item.action, .docker(.removeImage(id: "sha256:ef32de1a9e0011223344556677889900aabbccddeeff00112233445566778899")))
    }

    func testDanglingImageFallsBackToTotalSize() throws {
        let items = parse(images: [
            image(id: "sha256:aaaa", repository: "<none>", tag: "<none>", containers: "0", size: "1.5GB", unique: "N/A"),
        ])
        XCTAssertEqual(try XCTUnwrap(items.first).size, 1_500_000_000)
    }

    func testRecentTaggedImageIsReviewAndNotRecommended() throws {
        let items = parse(images: [
            image(id: "sha256:bbbb", repository: "pcw-shader-builder", tag: "1", containers: "0", size: "4.24GB", unique: "2.996GB", createdAt: "2026-10-06 14:25:19 +0700 +07", createdSince: "9 days ago"),
        ])
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.title, "pcw-shader-builder:1")
        XCTAssertEqual(item.detail, "Unused image · created 9 days ago · 4.24 GB total, 2.996 GB unique")
        XCTAssertEqual(item.safety, .review)
        XCTAssertFalse(item.recommended)
        XCTAssertEqual(item.size, 2_996_000_000)
        XCTAssertEqual(item.lastModified, Self.date("2026-10-06 14:25:19 +0700"))
    }

    func testOldTaggedImageIsRecommended() throws {
        let items = parse(images: [
            image(id: "sha256:cccc", repository: "postgres", tag: "16", containers: "0", size: "657MB", unique: "657.2MB", createdAt: "2026-06-24 08:36:31 +0700 +07", createdSince: "3 months ago"),
        ])
        let item = try XCTUnwrap(items.first)
        XCTAssertTrue(item.recommended)
        XCTAssertEqual(item.safety, .review)
    }

    func testImagesWithContainersAreSkipped() {
        let items = parse(images: [
            image(id: "sha256:dddd", repository: "mariadb", tag: "10.6", containers: "1", size: "413MB", unique: "413.4MB"),
            image(id: "sha256:eeee", repository: "<none>", tag: "<none>", containers: "2", size: "1GB", unique: "1GB"),
        ])
        XCTAssertTrue(items.isEmpty)
    }

    func testImageWithSeveralTagsBecomesOneItem() throws {
        let items = parse(images: [
            image(id: "sha256:ffff", repository: "node", tag: "22", containers: "0", size: "1.63GB", unique: "1.632GB"),
            image(id: "sha256:ffff", repository: "node", tag: "lts", containers: "0", size: "1.63GB", unique: "1.632GB"),
        ])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(try XCTUnwrap(items.first).title, "node:22, node:lts")
    }

    func testStoppedContainersAreListedAndRunningOnesAreNot() throws {
        let items = parse(containers: [
            container(id: "f876f31445a5", names: "eims-bank-mocks", image: "eims/bank-mocks:local", state: "exited", status: "Exited (0) 2 days ago", size: "4.1kB"),
            container(id: "a1", names: "web-1", image: "nginx", state: "running", status: "Up 9 days", size: "41kB"),
            container(id: "b2", names: "paused-1", image: "nginx", state: "paused", status: "Up 9 days (Paused)", size: "41kB"),
            container(id: "c3", names: "fresh", image: "alpine", state: "created", status: "Created", size: "0B"),
        ])
        XCTAssertEqual(items.map(\.title).sorted(), ["eims-bank-mocks", "fresh"])
        let stopped = try XCTUnwrap(items.first { $0.title == "eims-bank-mocks" })
        XCTAssertEqual(stopped.id, "docker:container:f876f31445a5")
        XCTAssertEqual(stopped.detail, "Stopped container · eims/bank-mocks:local · Exited (0) 2 days ago")
        XCTAssertEqual(stopped.size, 4_100)
        XCTAssertEqual(stopped.safety, .review)
        XCTAssertFalse(stopped.recommended)
        XCTAssertEqual(stopped.action, .docker(.removeContainer(id: "f876f31445a5")))
    }

    func testNamedUnusedVolumeIsCaution() throws {
        let items = parse(volumes: [
            volume(name: "documenso_postgres_data", links: "0", size: "68.84MB", labels: "com.docker.compose.project=documenso,com.docker.compose.volume=postgres_data"),
        ])
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.id, "docker:volume:documenso_postgres_data")
        XCTAssertEqual(item.title, "documenso_postgres_data")
        XCTAssertEqual(item.detail, "Not used by any container · may hold database data")
        XCTAssertEqual(item.safety, .caution)
        XCTAssertFalse(item.recommended)
        XCTAssertEqual(item.size, 68_840_000)
        XCTAssertEqual(item.action, .docker(.removeVolume(name: "documenso_postgres_data")))
    }

    func testAnonymousVolumesAreReview() {
        let hexName = "7803fce27014f3080e754474e52b1ff3ac31f2f07bc4267f2dedb711fef9b2e9"
        let items = parse(volumes: [
            volume(name: hexName, links: "0", size: "278.7MB", labels: ""),
            volume(name: "custom-name", links: "0", size: "1MB", labels: "com.docker.volume.anonymous="),
        ])
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.safety == .review && !$0.recommended })
        XCTAssertEqual(items.first?.title, "Anonymous volume 7803fce27014")
        XCTAssertEqual(items.last?.title, "Anonymous volume custom-name")
    }

    func testVolumesInUseAreSkipped() {
        let items = parse(volumes: [
            volume(name: "businesssales_db_data_mariadb106", links: "1", size: "11.55GB", labels: ""),
        ])
        XCTAssertTrue(items.isEmpty)
    }

    func testBuildCacheUsesSummaryReclaimable() throws {
        let entries = [
            buildCache(id: "5kd03s", inUse: "true", size: "20.2MB"),
            buildCache(id: "x1", inUse: "false", size: "1GB"),
            buildCache(id: "x2", inUse: "false", size: "2GB"),
        ]
        let items = parse(buildCache: entries, summary: summaryLines(buildCacheReclaimable: "17.22GB"))
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.id, "docker:buildcache")
        XCTAssertEqual(item.title, "Build cache")
        XCTAssertEqual(item.detail, "Layers BuildKit can rebuild · 2 entries not in use")
        XCTAssertEqual(item.size, 17_220_000_000)
        XCTAssertEqual(item.safety, .safe)
        XCTAssertTrue(item.recommended)
        XCTAssertEqual(item.action, .docker(.pruneBuildCache))
    }

    func testBuildCacheWithNothingReclaimableIsSkipped() {
        let items = parse(buildCache: [buildCache(id: "a", inUse: "true", size: "1GB")], summary: summaryLines(buildCacheReclaimable: "0B"))
        XCTAssertTrue(items.isEmpty)
    }

    func testItemsAreSortedBySizeDescending() {
        let items = parse(
            images: [image(id: "sha256:small", repository: "<none>", tag: "<none>", containers: "0", size: "10MB", unique: "10MB")],
            containers: [container(id: "c", names: "old", image: "x", state: "exited", status: "Exited (0) 1 day ago", size: "1kB")],
            volumes: [volume(name: "big_data", links: "0", size: "5GB", labels: "")],
            summary: summaryLines(buildCacheReclaimable: "33.98GB (78%)")
        )
        XCTAssertEqual(items.map(\.id), ["docker:buildcache", "docker:volume:big_data", "docker:image:sha256:small", "docker:container:c"])
    }

    func testNullValuesAndMissingSectionsAreTolerated() throws {
        let json = #"{"Images":null,"Containers":[{"ID":"abc","Names":"n","Image":"i","State":"exited","Status":"Exited (1) 3 days ago","Size":"0B","Platform":null}],"Volumes":null}"#
        let items = DockerService.parseJunk(verboseJSON: Data(json.utf8), summaryJSONLines: Data(), now: now)
        XCTAssertEqual(items.map(\.id), ["docker:container:abc"])
    }

    func testInvalidJSONGivesNoItems() {
        XCTAssertTrue(DockerService.parseJunk(verboseJSON: Data("not json".utf8), summaryJSONLines: Data(), now: now).isEmpty)
    }

    func testCreationDateParsing() {
        XCTAssertEqual(DockerService.creationDate("2026-10-06 14:25:19 +0700 +07"), Self.date("2026-10-06 14:25:19 +0700"))
        XCTAssertNil(DockerService.creationDate(""))
        XCTAssertNil(DockerService.creationDate("garbage"))
    }

    func testShortID() {
        XCTAssertEqual(DockerService.shortID("sha256:ef32de1a9e0011223344"), "ef32de1a9e00")
        XCTAssertEqual(DockerService.shortID("abc"), "abc")
    }

    private func parse(
        images: [[String: String]] = [],
        containers: [[String: String]] = [],
        volumes: [[String: String]] = [],
        buildCache: [[String: String]] = [],
        summary: String = ""
    ) -> [CleanupItem] {
        let root: [String: Any] = ["Images": images, "Containers": containers, "Volumes": volumes, "BuildCache": buildCache]
        let verbose = try! JSONSerialization.data(withJSONObject: root)
        return DockerService.parseJunk(verboseJSON: verbose, summaryJSONLines: Data(summary.utf8), now: now)
    }

    private func image(
        id: String, repository: String, tag: String, containers: String, size: String, unique: String,
        createdAt: String = "2026-10-06 13:51:58 +0700 +07", createdSince: String = "9 days ago"
    ) -> [String: String] {
        ["Containers": containers, "CreatedAt": createdAt, "CreatedSince": createdSince, "Digest": "", "ID": id,
         "Repository": repository, "SharedSize": "0B", "Size": size, "Tag": tag, "UniqueSize": unique]
    }

    private func container(id: String, names: String, image: String, state: String, status: String, size: String) -> [String: String] {
        ["ID": id, "Image": image, "Names": names, "State": state, "Status": status, "Size": size,
         "CreatedAt": "2026-10-06 22:47:57 +0700 +07", "RunningFor": "9 days ago", "LocalVolumes": "0", "Mounts": ""]
    }

    private func volume(name: String, links: String, size: String, labels: String) -> [String: String] {
        ["Driver": "local", "Labels": labels, "Links": links, "Mountpoint": "/var/lib/docker/volumes/\(name)/_data",
         "Name": name, "Scope": "local", "Size": size]
    }

    private func buildCache(id: String, inUse: String, size: String) -> [String: String] {
        ["CacheType": "regular", "ID": id, "InUse": inUse, "Shared": "true", "Size": size,
         "LastUsedSince": "", "CreatedSince": "2 weeks ago", "Description": "layer"]
    }

    private func summaryLines(buildCacheReclaimable: String) -> String {
        """
        {"Active":"10","Reclaimable":"33.98GB (78%)","Size":"43.02GB","TotalCount":"43","Type":"Images"}
        {"Active":"3","Reclaimable":"2.13MB (96%)","Size":"2.2MB","TotalCount":"11","Type":"Containers"}
        {"Active":"9","Reclaimable":"37.49GB (75%)","Size":"49.56GB","TotalCount":"34","Type":"Local Volumes"}
        {"Active":"147","Reclaimable":"\(buildCacheReclaimable)","Size":"45.46GB","TotalCount":"364","Type":"Build Cache"}
        """
    }

    private static func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: text)!
    }
}

final class ServiceDockerTests: XCTestCase {
    func testStatusWhenNotInstalled() async {
        let status = await DockerService(executable: nil).status()
        XCTAssertFalse(status.installed)
        XCTAssertFalse(status.running)
        XCTAssertNotNil(status.message)
    }

    func testStatusWhenDaemonIsDown() async {
        let recorder = CommandRecorder(results: [failure("Cannot connect to the Docker daemon")])
        let status = await DockerService(executable: "/fake/docker", runCommand: recorder.run).status()
        XCTAssertTrue(status.installed)
        XCTAssertFalse(status.running)
        XCTAssertEqual(status.message, "Docker Desktop is not running. Start it to review images.")
        XCTAssertEqual(recorder.calls.first?.arguments, ["info", "--format", "{{.ServerVersion}}"])
        XCTAssertEqual(recorder.calls.first?.timeout, 8)
    }

    func testStatusWhenRunning() async {
        let recorder = CommandRecorder(results: [success("28.1.1\n")])
        let status = await DockerService(executable: "/fake/docker", runCommand: recorder.run).status()
        XCTAssertTrue(status.running)
        XCTAssertNil(status.message)
    }

    func testFindJunkReturnsEmptyWhenACommandFails() async {
        let recorder = CommandRecorder(results: [failure("daemon down"), failure("daemon down")])
        let items = await DockerService(executable: "/fake/docker", runCommand: recorder.run).findJunk()
        XCTAssertTrue(items.isEmpty)
    }

    func testFindJunkRunsBothDiskUsageCommands() async {
        let verbose = #"{"Images":[],"Containers":[],"Volumes":[],"BuildCache":[]}"#
        let summary = #"{"Reclaimable":"1GB","Type":"Build Cache"}"#
        let recorder = CommandRecorder { arguments in
            arguments.contains("-v") ? Self.success(verbose) : Self.success(summary)
        }
        let items = await DockerService(executable: "/fake/docker", runCommand: recorder.run).findJunk()
        XCTAssertEqual(items.map(\.id), ["docker:buildcache"])
        XCTAssertEqual(Set(recorder.calls.map(\.arguments)), [["system", "df", "-v", "--format", "json"], ["system", "df", "--format", "json"]])
        XCTAssertTrue(recorder.calls.allSatisfy { $0.timeout == 60 })
    }

    func testRemoveImageRetriesWithForce() async throws {
        let recorder = CommandRecorder(results: [
            failure("Error response from daemon: conflict: unable to delete ffff (must be forced) - image is referenced in multiple repositories"),
            success(""),
        ])
        try await DockerService(executable: "/fake/docker", runCommand: recorder.run).perform(.removeImage(id: "sha256:ffff"))
        XCTAssertEqual(recorder.calls.map(\.arguments), [["image", "rm", "sha256:ffff"], ["image", "rm", "--force", "sha256:ffff"]])
        XCTAssertTrue(recorder.calls.allSatisfy { $0.timeout == 300 })
    }

    func testRemoveImageDoesNotForceOtherErrors() async {
        let recorder = CommandRecorder(results: [failure("Error: No such image: sha256:ffff")])
        do {
            try await DockerService(executable: "/fake/docker", runCommand: recorder.run).perform(.removeImage(id: "sha256:ffff"))
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Error: No such image: sha256:ffff")
        }
        XCTAssertEqual(recorder.calls.count, 1)
    }

    func testActionArguments() async throws {
        let recorder = CommandRecorder { _ in Self.success("") }
        let service = DockerService(executable: "/fake/docker", runCommand: recorder.run)
        try await service.perform(.removeContainer(id: "abc"))
        try await service.perform(.removeVolume(name: "data"))
        try await service.perform(.pruneBuildCache)
        XCTAssertEqual(recorder.calls.map(\.arguments), [["rm", "abc"], ["volume", "rm", "data"], ["builder", "prune", "--force"]])
    }

    func testFailedActionThrowsStderr() async {
        let recorder = CommandRecorder(results: [failure("Error response from daemon: remove data: volume is in use")])
        do {
            try await DockerService(executable: "/fake/docker", runCommand: recorder.run).perform(.removeVolume(name: "data"))
            XCTFail("Expected an error")
        } catch let error as DockerError {
            XCTAssertEqual(error, .commandFailed(command: "docker volume rm data", message: "Error response from daemon: remove data: volume is in use"))
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testPerformWithoutDockerThrows() async {
        do {
            try await DockerService(executable: nil).perform(.pruneBuildCache)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? DockerError, .notInstalled)
        }
    }

    func testLocateOrderPrefersWellKnownPaths() {
        let candidates = DockerService.candidatePaths(home: "/Users/me", environmentPath: "/custom/bin:/usr/bin")
        XCTAssertEqual(Array(candidates.prefix(7)), [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Users/me/.docker/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "/Users/me/.orbstack/bin/docker",
            "/Users/me/.rd/bin/docker",
            "/opt/local/bin/docker",
        ])
        XCTAssertEqual(Array(candidates.suffix(2)), ["/custom/bin/docker", "/usr/bin/docker"])
        XCTAssertEqual(
            DockerService.firstExecutable(in: candidates, isExecutable: { $0 == "/Users/me/.orbstack/bin/docker" || $0 == "/custom/bin/docker" }),
            "/Users/me/.orbstack/bin/docker"
        )
        XCTAssertNil(DockerService.firstExecutable(in: candidates, isExecutable: { _ in false }))
    }

    func testEnvironmentPathIncludesDockerFolderAndStandardFolders() {
        let environment = DockerCommandRunner.environment(forExecutable: "/Users/me/.orbstack/bin/docker", base: ["PATH": "/usr/bin:/bin", "HOME": "/Users/me"])
        let folders = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        XCTAssertEqual(folders.first, "/Users/me/.orbstack/bin")
        XCTAssertTrue(folders.contains("/usr/local/bin"))
        XCTAssertTrue(folders.contains("/opt/homebrew/bin"))
        XCTAssertEqual(folders.filter { $0 == "/usr/bin" }.count, 1)
        XCTAssertEqual(environment["HOME"], "/Users/me")
    }

    func testRunnerKillsProcessOnTimeout() async {
        let started = Date()
        let result = await DockerCommandRunner.run(executable: "/bin/sleep", arguments: ["30"], timeout: 0.5)
        XCTAssertTrue(result.timedOut)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testRunnerReadsLargeStdoutAndStderr() async {
        let script = "head -c 300000 /dev/zero | tr '\\0' 'a'; head -c 200000 /dev/zero | tr '\\0' 'b' 1>&2; exit 3"
        let result = await DockerCommandRunner.run(executable: "/bin/sh", arguments: ["-c", script], timeout: 20)
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertEqual(result.stdout.count, 300_000)
        XCTAssertEqual(result.stderr.count, 200_000)
    }

    func testLiveDockerDiskUsageWhenEnabled() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SWEEP_DOCKER_LIVE"] == "1", "Set SWEEP_DOCKER_LIVE=1 to read this machine's Docker disk usage")
        let service = DockerService()
        let status = await service.status()
        try XCTSkipUnless(status.running, status.message ?? "Docker is not running")
        let items = await service.findJunk()
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        print("Live Docker junk: \(items.count) items, \(total) bytes")
        for item in items {
            print("  \(item.size)\t\(item.safety)\t\(item.recommended)\t\(item.title)")
        }
        XCTAssertFalse(items.isEmpty)
    }

    private static func success(_ output: String) -> DockerCommandResult {
        DockerCommandResult(exitCode: 0, stdout: Data(output.utf8), stderr: Data())
    }

    private static func failure(_ message: String) -> DockerCommandResult {
        DockerCommandResult(exitCode: 1, stdout: Data(), stderr: Data(message.utf8))
    }

    private func success(_ output: String) -> DockerCommandResult { Self.success(output) }
    private func failure(_ message: String) -> DockerCommandResult { Self.failure(message) }
}

private final class CommandRecorder: @unchecked Sendable {
    struct Call {
        let arguments: [String]
        let timeout: TimeInterval
    }

    private let lock = NSLock()
    private var queuedResults: [DockerCommandResult]
    private var recordedCalls: [Call] = []
    private let respond: (@Sendable ([String]) -> DockerCommandResult)?

    init(results: [DockerCommandResult]) {
        queuedResults = results
        respond = nil
    }

    init(respond: @escaping @Sendable ([String]) -> DockerCommandResult) {
        queuedResults = []
        self.respond = respond
    }

    var calls: [Call] { lock.withLock { recordedCalls } }

    var run: DockerCommandRun {
        { [self] arguments, timeout in record(arguments, timeout) }
    }

    private func record(_ arguments: [String], _ timeout: TimeInterval) -> DockerCommandResult {
        lock.withLock {
            recordedCalls.append(Call(arguments: arguments, timeout: timeout))
            if let respond { return respond(arguments) }
            guard !queuedResults.isEmpty else { return DockerCommandResult(exitCode: 1, stdout: Data(), stderr: Data("unexpected call".utf8)) }
            return queuedResults.removeFirst()
        }
    }
}

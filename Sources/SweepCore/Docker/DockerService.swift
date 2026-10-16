import Foundation

public enum DockerError: LocalizedError, Sendable, Equatable {
    case notInstalled
    case commandFailed(command: String, message: String)
    case timedOut(command: String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Docker is not installed."
        case let .commandFailed(_, message):
            message
        case let .timedOut(command):
            "`\(command)` did not finish in time."
        }
    }
}

struct DockerCommandResult: Sendable, Equatable {
    var exitCode: Int32
    var stdout: Data
    var stderr: Data
    var timedOut: Bool = false

    var succeeded: Bool { exitCode == 0 && !timedOut }

    var failureMessage: String {
        let errorText = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if !errorText.isEmpty { return errorText }
        let outputText = String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if !outputText.isEmpty { return outputText }
        return "Docker exited with code \(exitCode)."
    }
}

typealias DockerCommandRun = @Sendable (_ arguments: [String], _ timeout: TimeInterval) async -> DockerCommandResult

public struct DockerService: Sendable {
    static let statusTimeout: TimeInterval = 8
    static let diskUsageTimeout: TimeInterval = 60
    static let actionTimeout: TimeInterval = 300
    static let notRunningMessage = "Docker Desktop is not running. Start it to review images."
    static let notInstalledMessage = "Docker is not installed."

    private let executable: String?
    private let runCommand: DockerCommandRun

    public init(executable: String? = DockerService.locateExecutable()) {
        self.executable = executable
        self.runCommand = { arguments, timeout in
            guard let executable else {
                return DockerCommandResult(exitCode: -1, stdout: Data(), stderr: Data(DockerService.notInstalledMessage.utf8))
            }
            return await DockerCommandRunner.run(executable: executable, arguments: arguments, timeout: timeout)
        }
    }

    init(executable: String?, runCommand: @escaping DockerCommandRun) {
        self.executable = executable
        self.runCommand = runCommand
    }

    public static func locateExecutable() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return firstExecutable(
            in: candidatePaths(home: home, environmentPath: environmentPath),
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }
        )
    }

    static func candidatePaths(home: String, environmentPath: String) -> [String] {
        let wellKnown = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "\(home)/.docker/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "\(home)/.orbstack/bin/docker",
            "\(home)/.rd/bin/docker",
            "/opt/local/bin/docker",
        ]
        let fromPath = environmentPath
            .split(separator: ":")
            .map { ($0 as NSString).appendingPathComponent("docker") }
        return wellKnown + fromPath
    }

    static func firstExecutable(in candidates: [String], isExecutable: (String) -> Bool) -> String? {
        candidates.first(where: isExecutable)
    }

    public func status() async -> DockerStatus {
        guard executable != nil else {
            return DockerStatus(installed: false, running: false, message: Self.notInstalledMessage)
        }
        let result = await runCommand(["info", "--format", "{{.ServerVersion}}"], Self.statusTimeout)
        if result.succeeded {
            return DockerStatus(installed: true, running: true, message: nil)
        }
        return DockerStatus(installed: true, running: false, message: Self.notRunningMessage)
    }

    public func findJunk() async -> [CleanupItem] {
        guard executable != nil else { return [] }
        async let verbose = runCommand(["system", "df", "-v", "--format", "json"], Self.diskUsageTimeout)
        async let summary = runCommand(["system", "df", "--format", "json"], Self.diskUsageTimeout)
        let (verboseResult, summaryResult) = await (verbose, summary)
        guard verboseResult.succeeded, summaryResult.succeeded else { return [] }
        return Self.parseJunk(verboseJSON: verboseResult.stdout, summaryJSONLines: summaryResult.stdout, now: Date())
    }

    public func perform(_ action: DockerAction) async throws {
        guard executable != nil else { throw DockerError.notInstalled }
        switch action {
        case let .removeImage(id):
            try await removeImage(id: id)
        case let .removeContainer(id):
            try await runChecked(["rm", id])
        case let .removeVolume(name):
            try await runChecked(["volume", "rm", name])
        case .pruneBuildCache:
            try await runChecked(["builder", "prune", "--force"])
        }
    }

    private func removeImage(id: String) async throws {
        let result = await runCommand(["image", "rm", id], Self.actionTimeout)
        if result.succeeded { return }
        if Self.needsForcedRemoval(result) {
            try await runChecked(["image", "rm", "--force", id])
            return
        }
        throw Self.error(for: ["image", "rm", id], result: result)
    }

    private func runChecked(_ arguments: [String]) async throws {
        let result = await runCommand(arguments, Self.actionTimeout)
        guard result.succeeded else { throw Self.error(for: arguments, result: result) }
    }

    static func needsForcedRemoval(_ result: DockerCommandResult) -> Bool {
        let message = result.failureMessage.lowercased()
        return message.contains("must be forced") || message.contains("referenced in multiple repositories")
    }

    static func error(for arguments: [String], result: DockerCommandResult) -> DockerError {
        let command = (["docker"] + arguments).joined(separator: " ")
        if result.timedOut { return .timedOut(command: command) }
        return .commandFailed(command: command, message: result.failureMessage)
    }
}

extension DockerService {
    static func parseJunk(verboseJSON: Data, summaryJSONLines: Data, now: Date) -> [CleanupItem] {
        guard let root = (try? JSONSerialization.jsonObject(with: verboseJSON)) as? [String: Any] else { return [] }
        let images = DockerRecords.from(root["Images"])
        let containers = DockerRecords.from(root["Containers"])
        let volumes = DockerRecords.from(root["Volumes"])
        let buildCache = DockerRecords.from(root["BuildCache"])
        let reclaimableBuildCache = buildCacheReclaimable(summaryJSONLines: summaryJSONLines)

        let items = imageItems(images, now: now)
            + containerItems(containers)
            + volumeItems(volumes)
            + buildCacheItems(buildCache, reclaimable: reclaimableBuildCache)
        return items.sorted { lhs, rhs in
            lhs.size != rhs.size ? lhs.size > rhs.size : lhs.title < rhs.title
        }
    }

    static func buildCacheReclaimable(summaryJSONLines: Data) -> Int64? {
        let lines = String(decoding: summaryJSONLines, as: UTF8.self).split(whereSeparator: \.isNewline)
        for line in lines {
            guard let row = DockerRecords.record(fromJSONLine: String(line)), row["Type"] == "Build Cache" else { continue }
            return DockerSizeParser.bytes(from: row["Reclaimable"] ?? "")
        }
        return nil
    }

    static func shortID(_ id: String) -> String {
        let hex = id.hasPrefix("sha256:") ? String(id.dropFirst("sha256:".count)) : id
        return String(hex.prefix(12))
    }

    static func creationDate(_ createdAt: String) -> Date? {
        let parts = createdAt.split(separator: " ").prefix(3)
        guard parts.count == 3 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: parts.joined(separator: " "))
    }

    static func isAnonymousVolume(name: String, labels: String) -> Bool {
        let labelKeys = labels.split(separator: ",").map { $0.split(separator: "=", maxSplits: 1).first.map(String.init) ?? "" }
        return labelKeys.contains("com.docker.volume.anonymous") || isSixtyFourHex(name)
    }

    private static let unusedImageAge: TimeInterval = 30 * 24 * 60 * 60
    private static let untaggedMarker = "<none>"

    private static func isSixtyFourHex(_ text: String) -> Bool {
        text.count == 64 && text.allSatisfy(\.isHexDigit)
    }

    private static func imageItems(_ images: [[String: String]], now: Date) -> [CleanupItem] {
        let unusedImages = images.filter { $0["Containers"] == "0" }
        let rowsByID = Dictionary(grouping: unusedImages, by: { $0["ID"] ?? "" })
        let orderedIDs = unusedImages.compactMap { $0["ID"] }.reduce(into: [String]()) { ids, id in
            if !id.isEmpty, !ids.contains(id) { ids.append(id) }
        }
        return orderedIDs.compactMap { id in
            guard let rows = rowsByID[id], let first = rows.first else { return nil }
            let references = rows.compactMap(reference(of:))
            return references.isEmpty
                ? untaggedImageItem(id: id, row: first)
                : taggedImageItem(id: id, row: first, references: references, now: now)
        }
    }

    private static func reference(of image: [String: String]) -> String? {
        let repository = image["Repository"] ?? ""
        let tag = image["Tag"] ?? ""
        guard !repository.isEmpty, repository != untaggedMarker else { return nil }
        guard !tag.isEmpty, tag != untaggedMarker else { return repository }
        return "\(repository):\(tag)"
    }

    private static func imageSize(_ image: [String: String]) -> (bytes: Int64, unique: String) {
        let unique = image["UniqueSize"] ?? ""
        let uniqueBytes = DockerSizeParser.bytes(from: unique)
        if uniqueBytes > 0 || unique.hasPrefix("0") { return (uniqueBytes, unique) }
        let total = image["Size"] ?? ""
        return (DockerSizeParser.bytes(from: total), total)
    }

    private static func imageDetail(prefix: String, image: [String: String], uniqueSize: String) -> String {
        let created = image["CreatedSince"].flatMap { $0.isEmpty ? nil : "created \($0)" }
        let total = DockerSizeParser.displayString(image["Size"] ?? "")
        let unique = DockerSizeParser.displayString(uniqueSize)
        return [prefix, created, "\(total) total, \(unique) unique"].compactMap { $0 }.joined(separator: " · ")
    }

    private static func untaggedImageItem(id: String, row: [String: String]) -> CleanupItem {
        let size = imageSize(row)
        return CleanupItem(
            id: "docker:image:\(id)",
            category: .docker,
            title: "Untagged image \(shortID(id))",
            detail: imageDetail(prefix: "Dangling layer left by a rebuild", image: row, uniqueSize: size.unique),
            path: nil,
            size: size.bytes,
            lastModified: creationDate(row["CreatedAt"] ?? ""),
            safety: .safe,
            recommended: true,
            action: .docker(.removeImage(id: id))
        )
    }

    private static func taggedImageItem(id: String, row: [String: String], references: [String], now: Date) -> CleanupItem {
        let size = imageSize(row)
        let created = creationDate(row["CreatedAt"] ?? "")
        let isOld = created.map { now.timeIntervalSince($0) > unusedImageAge } ?? false
        return CleanupItem(
            id: "docker:image:\(id)",
            category: .docker,
            title: references.joined(separator: ", "),
            detail: imageDetail(prefix: "Unused image", image: row, uniqueSize: size.unique),
            path: nil,
            size: size.bytes,
            lastModified: created,
            safety: .review,
            recommended: isOld,
            action: .docker(.removeImage(id: id))
        )
    }

    private static let activeContainerStates: Set<String> = ["running", "paused", "restarting"]

    private static func containerItems(_ containers: [[String: String]]) -> [CleanupItem] {
        containers.compactMap { container in
            guard let id = container["ID"], !id.isEmpty else { return nil }
            let state = (container["State"] ?? "").lowercased()
            guard !activeContainerStates.contains(state) else { return nil }
            let name = container["Names"].flatMap { $0.isEmpty ? nil : $0 } ?? shortID(id)
            let details = ["Stopped container", container["Image"], container["Status"]]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            return CleanupItem(
                id: "docker:container:\(id)",
                category: .docker,
                title: name,
                detail: details.joined(separator: " · "),
                path: nil,
                size: DockerSizeParser.bytes(from: container["Size"] ?? ""),
                lastModified: creationDate(container["CreatedAt"] ?? ""),
                safety: .review,
                recommended: false,
                action: .docker(.removeContainer(id: id))
            )
        }
    }

    private static func volumeItems(_ volumes: [[String: String]]) -> [CleanupItem] {
        volumes.compactMap { volume in
            guard let name = volume["Name"], !name.isEmpty, volume["Links"] == "0" else { return nil }
            let anonymous = isAnonymousVolume(name: name, labels: volume["Labels"] ?? "")
            return CleanupItem(
                id: "docker:volume:\(name)",
                category: .docker,
                title: anonymous ? "Anonymous volume \(String(name.prefix(12)))" : name,
                detail: "Not used by any container · may hold database data",
                path: nil,
                size: DockerSizeParser.bytes(from: volume["Size"] ?? ""),
                safety: anonymous ? .review : .caution,
                recommended: false,
                action: .docker(.removeVolume(name: name))
            )
        }
    }

    private static func buildCacheItems(_ entries: [[String: String]], reclaimable: Int64?) -> [CleanupItem] {
        let unusedEntries = entries.filter { ($0["InUse"] ?? "").lowercased() != "true" }
        let size = reclaimable ?? unusedEntries.reduce(Int64(0)) { $0 + DockerSizeParser.bytes(from: $1["Size"] ?? "") }
        guard size > 0 else { return [] }
        let entryWord = unusedEntries.count == 1 ? "entry" : "entries"
        return [
            CleanupItem(
                id: "docker:buildcache",
                category: .docker,
                title: "Build cache",
                detail: "Layers BuildKit can rebuild · \(unusedEntries.count) \(entryWord) not in use",
                path: nil,
                size: size,
                safety: .safe,
                recommended: true,
                action: .docker(.pruneBuildCache)
            ),
        ]
    }
}

enum DockerRecords {
    static func from(_ value: Any?) -> [[String: String]] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { ($0 as? [String: Any]).map(stringValues(of:)) }
    }

    static func record(fromJSONLine line: String) -> [String: String]? {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        return stringValues(of: object)
    }

    private static func stringValues(of object: [String: Any]) -> [String: String] {
        object.compactMapValues { value in
            switch value {
            case let text as String: text
            case let number as NSNumber: number.stringValue
            default: nil
            }
        }
    }
}

enum DockerCommandRunner {
    private static let standardFolders = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"]
    private static let gracefulStopWait: TimeInterval = 2
    private static let pipeDrainWait: TimeInterval = 5

    static func run(executable: String, arguments: [String], timeout: TimeInterval) async -> DockerCommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(executable: executable, arguments: arguments, timeout: timeout))
            }
        }
    }

    static func environment(forExecutable executable: String, base: [String: String]) -> [String: String] {
        let executableURL = URL(fileURLWithPath: executable)
        let executableFolders: [String] = [
            executableURL.deletingLastPathComponent().path,
            executableURL.resolvingSymlinksInPath().deletingLastPathComponent().path,
        ]
        let inheritedFolders: [String] = (base["PATH"] ?? "").split(separator: ":").map(String.init)
        let folders: [String] = executableFolders + standardFolders + inheritedFolders
        let uniqueFolders = folders.reduce(into: [String]()) { result, folder in
            if !folder.isEmpty, !result.contains(folder) { result.append(folder) }
        }
        var environment = base
        environment["PATH"] = uniqueFolders.joined(separator: ":")
        return environment
    }

    private static func runBlocking(executable: String, arguments: [String], timeout: TimeInterval) -> DockerCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment(forExecutable: executable, base: ProcessInfo.processInfo.environment)
        process.standardInput = FileHandle.nullDevice
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return DockerCommandResult(exitCode: -1, stdout: Data(), stderr: Data(error.localizedDescription.utf8))
        }

        let output = PipeDrain(outputPipe.fileHandleForReading)
        let errors = PipeDrain(errorPipe.fileHandleForReading)

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            stop(process, exited: exited)
        }
        output.wait(seconds: pipeDrainWait)
        errors.wait(seconds: pipeDrainWait)

        return DockerCommandResult(
            exitCode: timedOut ? -1 : process.terminationStatus,
            stdout: output.data,
            stderr: errors.data,
            timedOut: timedOut
        )
    }

    private static func stop(_ process: Process, exited: DispatchSemaphore) {
        process.terminate()
        if exited.wait(timeout: .now() + gracefulStopWait) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            _ = exited.wait(timeout: .now() + gracefulStopWait)
        }
    }
}

private final class PipeDrain: @unchecked Sendable {
    private let lock = NSLock()
    private let finished = DispatchGroup()
    private var collected = Data()

    init(_ handle: FileHandle) {
        finished.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let data = handle.readDataToEndOfFile()
            lock.withLock { collected = data }
            finished.leave()
        }
    }

    var data: Data { lock.withLock { collected } }

    func wait(seconds: TimeInterval) {
        _ = finished.wait(timeout: .now() + seconds)
    }
}

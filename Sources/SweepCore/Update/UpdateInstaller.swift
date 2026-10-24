import CryptoKit
import Foundation

public enum UpdateError: LocalizedError, Equatable {
    case feedUnavailable(Int)
    case downloadFailed(String)
    case missingDigest
    case digestMismatch
    case missingUpdateSignature
    case badUpdateSignature
    case noAppInArchive
    case wrongApp(String)
    case notNewer(String)
    case invalidSignature(String)
    case toolFailed(String, String)
    case cannotReplace(String)

    public var errorDescription: String? {
        switch self {
        case .feedUnavailable(let status): "GitHub did not answer the update check (status \(status))."
        case .downloadFailed(let reason): "The download failed: \(reason)"
        case .missingDigest: "The release does not give a SHA-256 checksum for the download."
        case .digestMismatch: "The downloaded file is damaged. Its checksum does not match the release."
        case .missingUpdateSignature: "The release has no update signature, so Sweep cannot trust it."
        case .badUpdateSignature: "The update signature is not valid. Sweep did not install this download."
        case .noAppInArchive: "The download does not contain an app."
        case .wrongApp(let identifier): "The download contains a different app (\(identifier))."
        case .notNewer(let version): "The download is version \(version), which is not newer."
        case .invalidSignature(let reason): "The downloaded app has an invalid code signature: \(reason)"
        case .toolFailed(let tool, let reason): "\(tool) failed: \(reason)"
        case .cannotReplace(let path): "Sweep cannot write to \(path)."
        }
    }
}

public struct PreparedUpdate: Sendable, Equatable {
    public let version: AppVersion
    public let stagedApp: URL
    public let workDirectory: URL
}

public struct UpdateInstaller: Sendable {
    public let installedApp: URL
    public let bundleIdentifier: String
    public let currentVersion: AppVersion
    public let publicKey: Curve25519.Signing.PublicKey

    public init(installedApp: URL, bundleIdentifier: String, currentVersion: AppVersion, publicKey: Curve25519.Signing.PublicKey) {
        self.installedApp = installedApp.standardizedFileURL
        self.bundleIdentifier = bundleIdentifier
        self.currentVersion = currentVersion
        self.publicKey = publicKey
    }

    public init?(bundle: Bundle) {
        guard bundle.bundleURL.pathExtension == "app",
              let identifier = bundle.bundleIdentifier,
              let versionText = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let version = AppVersion(versionText),
              let publicKeyText = bundle.object(forInfoDictionaryKey: UpdateSignature.publicKeyInfoKey) as? String,
              let publicKey = UpdateSignature.publicKey(base64: publicKeyText)
        else { return nil }
        self.init(installedApp: bundle.bundleURL, bundleIdentifier: identifier, currentVersion: version, publicKey: publicKey)
    }

    public var isTranslocated: Bool {
        installedApp.path.contains("/AppTranslocation/")
    }

    public var canReplaceInstalledApp: Bool {
        let fileManager = FileManager.default
        return !isTranslocated
            && fileManager.isWritableFile(atPath: installedApp.deletingLastPathComponent().path)
            && fileManager.isWritableFile(atPath: installedApp.path)
    }

    public func prepare(_ update: AvailableUpdate, progress: @escaping @Sendable (Double) -> Void) async throws -> PreparedUpdate {
        guard canReplaceInstalledApp else { throw UpdateError.cannotReplace(installedApp.deletingLastPathComponent().path) }
        let workDirectory = try makeWorkDirectory()
        do {
            let archive = workDirectory.appendingPathComponent(update.archive.name)
            try await Self.download(update.archive.browserDownloadUrl, to: archive, progress: progress)
            try Self.verify(archive, digest: update.archive.digest)
            try await verifySignature(of: archive, using: update.signature)
            let app = try Self.extractApp(from: archive, into: workDirectory.appendingPathComponent("extracted"))
            let version = try validate(app)
            try? FileManager.default.removeItem(at: archive)
            return PreparedUpdate(version: version, stagedApp: app, workDirectory: workDirectory)
        } catch {
            try? FileManager.default.removeItem(at: workDirectory)
            throw error
        }
    }

    func verifySignature(of archive: URL, using signatureAsset: ReleaseAsset?) async throws {
        guard let signatureAsset else { throw UpdateError.missingUpdateSignature }
        guard signatureAsset.size <= UpdateSignature.maximumSignatureFileSize else { throw UpdateError.badUpdateSignature }
        let (data, response) = try await URLSession.shared.data(from: signatureAsset.browserDownloadUrl)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.downloadFailed("HTTP status \(status)") }
        guard data.count <= UpdateSignature.maximumSignatureFileSize else { throw UpdateError.badUpdateSignature }
        try UpdateSignature.verify(archive, signatureFileContents: data, publicKey: publicKey)
    }

    public func validate(_ app: URL) throws -> AppVersion {
        guard let bundle = Bundle(url: app) else { throw UpdateError.noAppInArchive }
        guard bundle.bundleIdentifier == bundleIdentifier else {
            throw UpdateError.wrongApp(bundle.bundleIdentifier ?? app.lastPathComponent)
        }
        let versionText = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        guard let version = AppVersion(versionText), version > currentVersion else { throw UpdateError.notNewer(versionText) }
        guard let output = ProcessRunner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], timeout: 60) else {
            throw UpdateError.toolFailed("codesign", "did not finish")
        }
        guard output.status == 0 else { throw UpdateError.invalidSignature(output.errorText) }
        return version
    }

    public func installAndRelaunch(_ prepared: PreparedUpdate, afterExitOf processID: Int32) throws {
        try Self.launchSwap(
            processID: processID,
            target: installedApp,
            staged: prepared.stagedApp,
            workDirectory: prepared.workDirectory,
            relaunch: true
        )
    }

    public func discard(_ prepared: PreparedUpdate) {
        try? FileManager.default.removeItem(at: prepared.workDirectory)
    }

    private func makeWorkDirectory() throws -> URL {
        try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: installedApp, create: true)
    }

    static func download(_ source: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let observation = ProgressObservation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = URLSession.shared.downloadTask(with: source) { location, response, error in
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if let error {
                        continuation.resume(throwing: UpdateError.downloadFailed(error.localizedDescription))
                    } else if let location, status == 200 {
                        do {
                            try? FileManager.default.removeItem(at: destination)
                            try FileManager.default.moveItem(at: location, to: destination)
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: UpdateError.downloadFailed(error.localizedDescription))
                        }
                    } else {
                        continuation.resume(throwing: UpdateError.downloadFailed("HTTP status \(status)"))
                    }
                }
                observation.start(task, progress: progress)
                task.resume()
            }
        } onCancel: {
            observation.cancel()
        }
        observation.stop()
    }

    static func verify(_ file: URL, digest: String?) throws {
        let parts = digest?.split(separator: ":", maxSplits: 1) ?? []
        guard parts.count == 2, parts[0].lowercased() == "sha256" else { throw UpdateError.missingDigest }
        guard try sha256Hex(of: file) == parts[1].lowercased() else { throw UpdateError.digestMismatch }
    }

    static func sha256Hex(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func extractApp(from archive: URL, into directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let output = ProcessRunner.run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path], timeout: 120) else {
            throw UpdateError.toolFailed("ditto", "did not finish")
        }
        guard output.status == 0 else { throw UpdateError.toolFailed("ditto", output.errorText) }
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else { throw UpdateError.noAppInArchive }
        return app
    }

    static let swapScript = """
    pid="$1"; target="$2"; staged="$3"; workdir="$4"; relaunch="$5"
    waited=0
    while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 600 ]; do sleep 0.1; waited=$((waited + 1)); done
    if kill -0 "$pid" 2>/dev/null; then exit 1; fi
    backup="$workdir/previous.app"
    rm -rf "$backup"
    if mv "$target" "$backup"; then
        if mv "$staged" "$target"; then
            rm -rf "$workdir"
        else
            mv "$backup" "$target"
        fi
    fi
    if [ "$relaunch" = "1" ]; then open "$target"; fi
    """

    static func launchSwap(processID: Int32, target: URL, staged: URL, workDirectory: URL, relaunch: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", swapScript, "sweep-update",
            String(processID), target.path, staged.path, workDirectory.path, relaunch ? "1" : "0",
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw UpdateError.toolFailed("sh", error.localizedDescription)
        }
    }
}

private final class ProgressObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var observation: NSKeyValueObservation?

    func start(_ task: URLSessionTask, progress: @escaping @Sendable (Double) -> Void) {
        lock.withLock {
            self.task = task
            observation = task.progress.observe(\.fractionCompleted) { value, _ in
                progress(value.fractionCompleted)
            }
        }
    }

    func cancel() {
        lock.withLock { task?.cancel() }
    }

    func stop() {
        lock.withLock {
            observation?.invalidate()
            observation = nil
            task = nil
        }
    }
}

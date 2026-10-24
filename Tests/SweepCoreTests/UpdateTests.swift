import CryptoKit
import Foundation
@testable import SweepCore
import XCTest

final class AppVersionTests: XCTestCase {
    func testParsesTagsAndPlainVersions() {
        XCTAssertEqual(AppVersion("v0.0.3")?.components, [0, 0, 3])
        XCTAssertEqual(AppVersion("1.2")?.components, [1, 2])
        XCTAssertEqual(AppVersion(" 0.0.1-alpha ")?.components, [0, 0, 1])
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertNil(AppVersion(""))
    }

    func testOrdering() throws {
        let v002 = try XCTUnwrap(AppVersion("0.0.2"))
        let v003 = try XCTUnwrap(AppVersion("v0.0.3"))
        let v010 = try XCTUnwrap(AppVersion("0.1"))
        let v0010 = try XCTUnwrap(AppVersion("0.0.10"))
        XCTAssertLessThan(v002, v003)
        XCTAssertLessThan(v003, v0010)
        XCTAssertLessThan(v0010, v010)
        XCTAssertEqual(AppVersion("1.0"), AppVersion("1.0.0"))
        XCTAssertFalse(v003 < v003)
    }
}

final class ReleaseFeedTests: XCTestCase {
    private func release(tag: String = "v0.0.3", draft: Bool = false, prerelease: Bool = false, assets: [String] = ["Sweep-0.0.3.dmg", "Sweep-0.0.3.zip"]) throws -> Release {
        let assetJSON = assets.map { name in
            """
            {"name": "\(name)", "size": 100, "browser_download_url": "https://example.com/\(name)", "digest": "sha256:abc"}
            """
        }.joined(separator: ",")
        let json = """
        {"tag_name": "\(tag)", "name": "Sweep", "body": "**New**", "html_url": "https://github.com/shirai91/sweepmymac/releases/tag/\(tag)",
         "draft": \(draft), "prerelease": \(prerelease), "published_at": "2026-10-24T02:36:31Z", "assets": [\(assetJSON)]}
        """
        return try ReleaseFeed.decodeRelease(Data(json.utf8))
    }

    func testDecodesGitHubRelease() throws {
        let decoded = try release()
        XCTAssertEqual(decoded.version, AppVersion("0.0.3"))
        XCTAssertEqual(decoded.appArchive?.name, "Sweep-0.0.3.zip")
        XCTAssertEqual(decoded.appArchive?.digest, "sha256:abc")
        XCTAssertNotNil(decoded.publishedAt)
    }

    func testTurnsBlockMarkdownIntoInlineNotes() throws {
        let json = ###"{"tag_name": "v0.0.3", "body": "## What's new\n- **Fast** scan\n* Fix\n\nPlain", "html_url": "https://github.com", "draft": false, "prerelease": false, "assets": []}"###
        let decoded = try ReleaseFeed.decodeRelease(Data(json.utf8))
        XCTAssertEqual(decoded.inlineMarkdownNotes, "**What's new**\n•  **Fast** scan\n•  Fix\n\nPlain")
    }

    func testOffersOnlyNewerPublishedReleasesWithAnArchive() throws {
        let current = try XCTUnwrap(AppVersion("0.0.2"))
        XCTAssertEqual(ReleaseFeed.update(in: try release(), newerThan: current)?.version, AppVersion("0.0.3"))
        XCTAssertNil(ReleaseFeed.update(in: try release(tag: "v0.0.2"), newerThan: current))
        XCTAssertNil(ReleaseFeed.update(in: try release(tag: "v0.0.1"), newerThan: current))
        XCTAssertNil(ReleaseFeed.update(in: try release(draft: true), newerThan: current))
        XCTAssertNil(ReleaseFeed.update(in: try release(prerelease: true), newerThan: current))
        XCTAssertNil(ReleaseFeed.update(in: try release(assets: ["Sweep-0.0.3.dmg"]), newerThan: current))
    }
}

final class UpdateInstallerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sweep-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeApp(named name: String = "Sweep.app", in directory: URL, identifier: String = "com.tungpham.sweep", version: String, sign: Bool = true) throws -> URL {
        let app = directory.appendingPathComponent(name)
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: macOS.appendingPathComponent("Sweep").path)
        let plist: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleExecutable": "Sweep",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        if sign {
            let output = ProcessRunner.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path], timeout: 60)
            XCTAssertEqual(output?.status, 0, output?.errorText ?? "codesign did not run")
        }
        return app
    }

    private func installer(at app: URL, version: String = "0.0.2", publicKey: Curve25519.Signing.PublicKey = Curve25519.Signing.PrivateKey().publicKey) throws -> UpdateInstaller {
        UpdateInstaller(installedApp: app, bundleIdentifier: "com.tungpham.sweep", currentVersion: try XCTUnwrap(AppVersion(version)), publicKey: publicKey)
    }

    private func zipApp(_ app: URL, to archive: URL) {
        let zip = ProcessRunner.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, archive.path], timeout: 60)
        XCTAssertEqual(zip?.status, 0)
    }

    func testUpdateSignatureAcceptsOnlyTheSignedFileAndKey() throws {
        let key = Curve25519.Signing.PrivateKey()
        let file = root.appendingPathComponent("Sweep-0.0.3.zip")
        try Data("release".utf8).write(to: file)
        let signature = Data(try UpdateSignature.signatureFileContents(for: file, privateKey: key).utf8)

        XCTAssertNoThrow(try UpdateSignature.verify(file, signatureFileContents: signature, publicKey: key.publicKey))
        XCTAssertThrowsError(try UpdateSignature.verify(file, signatureFileContents: signature, publicKey: Curve25519.Signing.PrivateKey().publicKey)) {
            XCTAssertEqual($0 as? UpdateError, .badUpdateSignature)
        }
        XCTAssertThrowsError(try UpdateSignature.verify(file, signatureFileContents: Data("not base64".utf8), publicKey: key.publicKey)) {
            XCTAssertEqual($0 as? UpdateError, .badUpdateSignature)
        }
        try Data("release!".utf8).write(to: file)
        XCTAssertThrowsError(try UpdateSignature.verify(file, signatureFileContents: signature, publicKey: key.publicKey)) {
            XCTAssertEqual($0 as? UpdateError, .badUpdateSignature)
        }
    }

    func testPublicKeyParsing() {
        let key = Curve25519.Signing.PrivateKey().publicKey
        XCTAssertEqual(UpdateSignature.publicKey(base64: key.rawRepresentation.base64EncodedString() + "\n")?.rawRepresentation, key.rawRepresentation)
        XCTAssertNil(UpdateSignature.publicKey(base64: "abc"))
    }

    func testRepositoryInfoPlistHasAValidUpdatePublicKey() throws {
        let plistURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Info.plist").standardizedFileURL
        let plist = try XCTUnwrap(NSDictionary(contentsOf: plistURL))
        let text = try XCTUnwrap(plist[UpdateSignature.publicKeyInfoKey] as? String)
        XCTAssertNotNil(UpdateSignature.publicKey(base64: text))
    }

    func testPrepareDownloadsVerifiesAndStagesSignedRelease() async throws {
        let server = try LocalFileServer(root: root.appendingPathComponent("served"))
        defer { server.stop() }
        let key = Curve25519.Signing.PrivateKey()
        let newApp = try makeApp(in: root.appendingPathComponent("source"), version: "0.0.3")
        let archive = server.root.appendingPathComponent("Sweep-0.0.3.zip")
        zipApp(newApp, to: archive)
        try UpdateSignature.signatureFileContents(for: archive, privateKey: key)
            .write(to: server.root.appendingPathComponent("Sweep-0.0.3.zip.sig"), atomically: true, encoding: .utf8)
        let digest = "sha256:" + (try UpdateInstaller.sha256Hex(of: archive))
        let installed = try makeApp(in: root.appendingPathComponent("Applications"), version: "0.0.2")

        func update(withSignature: Bool) throws -> AvailableUpdate {
            var assets = [#"{"name": "Sweep-0.0.3.zip", "size": 1, "digest": "\#(digest)", "browser_download_url": "\#(server.url("Sweep-0.0.3.zip"))"}"#]
            if withSignature {
                assets.append(#"{"name": "Sweep-0.0.3.zip.sig", "size": 89, "browser_download_url": "\#(server.url("Sweep-0.0.3.zip.sig"))"}"#)
            }
            let json = #"{"tag_name": "v0.0.3", "html_url": "https://github.com", "draft": false, "prerelease": false, "assets": [\#(assets.joined(separator: ","))]}"#
            let release = try ReleaseFeed.decodeRelease(Data(json.utf8))
            return try XCTUnwrap(ReleaseFeed.update(in: release, newerThan: try XCTUnwrap(AppVersion("0.0.2"))))
        }

        let trusting = try installer(at: installed, publicKey: key.publicKey)
        let prepared = try await trusting.prepare(try update(withSignature: true)) { _ in }
        XCTAssertEqual(prepared.version, AppVersion("0.0.3"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.stagedApp.path))
        trusting.discard(prepared)

        do {
            _ = try await trusting.prepare(try update(withSignature: false)) { _ in }
            XCTFail("A release without a signature must not prepare.")
        } catch {
            XCTAssertEqual(error as? UpdateError, .missingUpdateSignature)
        }

        do {
            _ = try await installer(at: installed).prepare(try update(withSignature: true)) { _ in }
            XCTFail("A release signed with another key must not prepare.")
        } catch {
            XCTAssertEqual(error as? UpdateError, .badUpdateSignature)
        }
    }

    func testVerifyChecksSHA256Digest() throws {
        let file = root.appendingPathComponent("archive.zip")
        try Data("sweep".utf8).write(to: file)
        let digest = "sha256:" + (try UpdateInstaller.sha256Hex(of: file))
        XCTAssertNoThrow(try UpdateInstaller.verify(file, digest: digest))
        XCTAssertThrowsError(try UpdateInstaller.verify(file, digest: nil)) { XCTAssertEqual($0 as? UpdateError, .missingDigest) }
        XCTAssertThrowsError(try UpdateInstaller.verify(file, digest: "md5:abc")) { XCTAssertEqual($0 as? UpdateError, .missingDigest) }
        XCTAssertThrowsError(try UpdateInstaller.verify(file, digest: "sha256:" + String(repeating: "0", count: 64))) { error in
            XCTAssertEqual(error as? UpdateError, .digestMismatch)
        }
    }

    func testExtractsAndValidatesNewerSignedApp() throws {
        let source = root.appendingPathComponent("source")
        let app = try makeApp(in: source, version: "0.0.3")
        let archive = root.appendingPathComponent("Sweep-0.0.3.zip")
        zipApp(app, to: archive)

        let extracted = try UpdateInstaller.extractApp(from: archive, into: root.appendingPathComponent("extracted"))
        XCTAssertEqual(extracted.lastPathComponent, "Sweep.app")
        let installed = try makeApp(in: root.appendingPathComponent("Applications"), version: "0.0.2")
        XCTAssertEqual(try installer(at: installed).validate(extracted), AppVersion("0.0.3"))
    }

    func testRejectsOlderForeignOrUnsignedApps() throws {
        let installed = try makeApp(in: root.appendingPathComponent("Applications"), version: "0.0.2")
        let subject = try installer(at: installed)

        let older = try makeApp(in: root.appendingPathComponent("older"), version: "0.0.2")
        XCTAssertThrowsError(try subject.validate(older)) { XCTAssertEqual($0 as? UpdateError, .notNewer("0.0.2")) }

        let foreign = try makeApp(in: root.appendingPathComponent("foreign"), identifier: "com.example.other", version: "9.0")
        XCTAssertThrowsError(try subject.validate(foreign)) { XCTAssertEqual($0 as? UpdateError, .wrongApp("com.example.other")) }

        let tampered = try makeApp(in: root.appendingPathComponent("tampered"), version: "0.0.3")
        try Data("changed".utf8).write(to: tampered.appendingPathComponent("Contents/MacOS/Sweep"))
        XCTAssertThrowsError(try subject.validate(tampered)) { error in
            guard case .invalidSignature = error as? UpdateError else { return XCTFail("\(error)") }
        }
    }

    func testCannotReplaceTranslocatedApp() throws {
        let translocated = URL(fileURLWithPath: "/private/var/folders/xy/AppTranslocation/ABC/d/Sweep.app")
        let subject = try installer(at: translocated)
        XCTAssertTrue(subject.isTranslocated)
        XCTAssertFalse(subject.canReplaceInstalledApp)
    }

    func testSwapScriptReplacesAppAfterProcessExits() throws {
        let target = try makeApp(in: root.appendingPathComponent("Applications"), version: "0.0.2", sign: false)
        let workDirectory = root.appendingPathComponent("work")
        let staged = try makeApp(in: workDirectory.appendingPathComponent("extracted"), version: "0.0.3", sign: false)
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["1"]
        try sleeper.run()

        try UpdateInstaller.launchSwap(processID: sleeper.processIdentifier, target: target, staged: staged, workDirectory: workDirectory, relaunch: false)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(Bundle(url: target)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, "0.0.2")

        let deadline = Date().addingTimeInterval(10)
        while FileManager.default.fileExists(atPath: workDirectory.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        let plist = try XCTUnwrap(NSDictionary(contentsOf: target.appendingPathComponent("Contents/Info.plist")))
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "0.0.3")
        XCTAssertFalse(FileManager.default.fileExists(atPath: workDirectory.path))
    }

    func testPreparesRealLatestReleaseFromGitHub() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SWEEP_NETWORK_TESTS"] == "1", "Set SWEEP_NETWORK_TESTS=1 to run.")
        let plistURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Info.plist").standardizedFileURL
        let keyText = try XCTUnwrap(NSDictionary(contentsOf: plistURL)?[UpdateSignature.publicKeyInfoKey] as? String)
        let installed = try makeApp(in: root.appendingPathComponent("Applications"), version: "0.0.1")
        let subject = try installer(at: installed, version: "0.0.1", publicKey: try XCTUnwrap(UpdateSignature.publicKey(base64: keyText)))
        let update = try await ReleaseFeed.sweep.update(newerThan: subject.currentVersion, userAgent: "SweepTests")
        let available = try XCTUnwrap(update)
        guard available.signature != nil else {
            do {
                _ = try await subject.prepare(available) { _ in }
                XCTFail("An unsigned release must not prepare.")
            } catch {
                XCTAssertEqual(error as? UpdateError, .missingUpdateSignature)
            }
            return
        }
        let prepared = try await subject.prepare(available) { _ in }
        XCTAssertEqual(prepared.version, available.version)
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.stagedApp.path))
        subject.discard(prepared)
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.workDirectory.path))
    }
}

private final class LocalFileServer {
    let root: URL
    let port: Int
    private let process = Process()

    init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        port = Int.random(in: 20_000...40_000)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "http.server", String(port), "--bind", "127.0.0.1", "--directory", root.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        try waitUntilReady()
    }

    func url(_ name: String) -> String {
        "http://127.0.0.1:\(port)/\(name)"
    }

    func stop() {
        process.terminate()
        process.waitUntilExit()
    }

    private func waitUntilReady() throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if (try? Data(contentsOf: URL(string: url(""))!)) != nil { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        stop()
        throw XCTSkip("python3 http.server did not start")
    }
}

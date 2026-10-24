import Foundation

public struct ReleaseAsset: Decodable, Sendable, Equatable {
    public let name: String
    public let size: Int64
    public let browserDownloadUrl: URL
    public let digest: String?
}

public struct Release: Decodable, Sendable, Equatable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlUrl: URL
    public let draft: Bool
    public let prerelease: Bool
    public let publishedAt: Date?
    public let assets: [ReleaseAsset]

    public var version: AppVersion? { AppVersion(tagName) }

    public var inlineMarkdownNotes: String? {
        guard let body, !body.isEmpty else { return nil }
        return body.components(separatedBy: .newlines).map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let heading = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                return heading.isEmpty ? "" : "**\(heading)**"
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                return "•  " + trimmed.dropFirst(2)
            }
            return line
        }.joined(separator: "\n")
    }

    public var appArchive: ReleaseAsset? {
        let archives = assets.filter { $0.name.lowercased().hasSuffix(".zip") }
        return archives.first { $0.name.hasPrefix("Sweep") } ?? archives.first
    }

    public func signature(for archive: ReleaseAsset) -> ReleaseAsset? {
        assets.first { $0.name == "\(archive.name).\(UpdateSignature.fileExtension)" }
    }
}

public struct AvailableUpdate: Sendable, Equatable {
    public let release: Release
    public let version: AppVersion
    public let archive: ReleaseAsset
    public let signature: ReleaseAsset?
}

public struct ReleaseFeed: Sendable {
    public static let sweep = ReleaseFeed(repository: "shirai91/sweepmymac")

    public let repository: String

    public init(repository: String) {
        self.repository = repository
    }

    public var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    public func latestRelease(userAgent: String, session: URLSession = .shared) async throws -> Release {
        var request = URLRequest(url: latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.feedUnavailable(status) }
        return try Self.decodeRelease(data)
    }

    public func update(newerThan current: AppVersion, userAgent: String, session: URLSession = .shared) async throws -> AvailableUpdate? {
        Self.update(in: try await latestRelease(userAgent: userAgent, session: session), newerThan: current)
    }

    public static func update(in release: Release, newerThan current: AppVersion) -> AvailableUpdate? {
        guard !release.draft, !release.prerelease,
              let version = release.version, version > current,
              let archive = release.appArchive
        else { return nil }
        return AvailableUpdate(release: release, version: version, archive: archive, signature: release.signature(for: archive))
    }

    public static func decodeRelease(_ data: Data) throws -> Release {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Release.self, from: data)
    }
}

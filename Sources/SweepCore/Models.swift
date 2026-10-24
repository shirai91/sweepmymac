import Foundation

public enum Safety: Int, Comparable, Sendable, CaseIterable, Codable {
    case safe
    case review
    case caution

    public static func < (lhs: Safety, rhs: Safety) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .safe: "Safe to remove"
        case .review: "Review first"
        case .caution: "Caution"
        }
    }
}

public enum JunkCategory: String, CaseIterable, Sendable, Identifiable, Codable {
    case appCaches
    case devCaches
    case xcode
    case buildArtifacts
    case docker
    case logs
    case trash
    case installers
    case largeOld
    case duplicates
    case appLeftovers
    case mailAttachments
    case iosBackups
    case systemClutter

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appCaches: "App Caches"
        case .devCaches: "Developer Caches"
        case .xcode: "Xcode & Simulators"
        case .buildArtifacts: "Project Build Artifacts"
        case .docker: "Docker"
        case .logs: "Logs & Crash Reports"
        case .trash: "Trash"
        case .installers: "Old Installers"
        case .largeOld: "Large & Old Files"
        case .duplicates: "Duplicate Files"
        case .appLeftovers: "Leftovers of Removed Apps"
        case .mailAttachments: "Mail Attachments"
        case .iosBackups: "iOS Backups & Updates"
        case .systemClutter: "System Clutter"
        }
    }

    public var subtitle: String {
        switch self {
        case .appCaches: "Temporary data that apps rebuild on demand."
        case .devCaches: "Package manager and tool caches (npm, Homebrew, Gradle, pip…)."
        case .xcode: "DerivedData, device support files, simulator caches and archives."
        case .buildArtifacts: "node_modules, target, .next, __pycache__ and other rebuildable folders."
        case .docker: "Unused images, stopped containers, dangling volumes and build cache."
        case .logs: "Diagnostic logs and crash reports."
        case .trash: "Items already in your Trash."
        case .installers: "Disk images and installer packages you already used."
        case .largeOld: "Big files you have not opened in a long time."
        case .duplicates: "Identical copies of the same file."
        case .appLeftovers: "Data left behind by apps that are no longer installed."
        case .mailAttachments: "Attachments Mail downloaded for preview."
        case .iosBackups: "Old iPhone / iPad backups and firmware downloads."
        case .systemClutter: "Old temporary files and .DS_Store files."
        }
    }

    public var symbol: String {
        switch self {
        case .appCaches: "square.stack.3d.up.fill"
        case .devCaches: "shippingbox.fill"
        case .xcode: "hammer.fill"
        case .buildArtifacts: "cube.transparent.fill"
        case .docker: "server.rack"
        case .logs: "doc.text.fill"
        case .trash: "trash.fill"
        case .installers: "opticaldiscdrive.fill"
        case .largeOld: "archivebox.fill"
        case .duplicates: "doc.on.doc.fill"
        case .appLeftovers: "app.dashed"
        case .mailAttachments: "paperclip"
        case .iosBackups: "iphone.gen3"
        case .systemClutter: "sparkles"
        }
    }
}

public enum DockerAction: Hashable, Sendable, Codable {
    case removeImage(id: String)
    case removeContainer(id: String)
    case removeVolume(name: String)
    case pruneBuildCache
}

public enum CleanAction: Hashable, Sendable, Codable {
    case removePaths([String])
    case emptyTrash([String])
    case docker(DockerAction)
    case deleteUnavailableSimulators
}

public struct CleanupItem: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let category: JunkCategory
    public let title: String
    public let detail: String
    public let path: String?
    public let size: Int64
    public let itemCount: Int
    public let lastModified: Date?
    public let safety: Safety
    public let recommended: Bool
    public let action: CleanAction
    public let bundleIdentifier: String?

    public init(
        id: String,
        category: JunkCategory,
        title: String,
        detail: String,
        path: String?,
        size: Int64,
        itemCount: Int = 1,
        lastModified: Date? = nil,
        safety: Safety,
        recommended: Bool,
        action: CleanAction,
        bundleIdentifier: String? = nil
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.path = path
        self.size = size
        self.itemCount = itemCount
        self.lastModified = lastModified
        self.safety = safety
        self.recommended = recommended
        self.action = action
        self.bundleIdentifier = bundleIdentifier
    }
}

public enum ScanScope: Sendable, Hashable {
    case entireDisk
    case home
    case folder(String)
}

public struct ScanProgress: Sendable {
    public var phase: ScanPhase
    public var filesScanned: Int
    public var directoriesScanned: Int
    public var bytesScanned: Int64
    public var currentPath: String
    public var elapsed: TimeInterval

    public init(phase: ScanPhase, filesScanned: Int = 0, directoriesScanned: Int = 0, bytesScanned: Int64 = 0, currentPath: String = "", elapsed: TimeInterval = 0) {
        self.phase = phase
        self.filesScanned = filesScanned
        self.directoriesScanned = directoriesScanned
        self.bytesScanned = bytesScanned
        self.currentPath = currentPath
        self.elapsed = elapsed
    }
}

public enum ScanPhase: String, Sendable {
    case walking = "Scanning files"
    case analyzing = "Finding junk"
    case duplicates = "Comparing duplicates"
    case docker = "Checking Docker"
    case done = "Done"
}

public struct ScanStats: Sendable {
    public let files: Int
    public let directories: Int
    public let bytes: Int64
    public let inaccessibleDirectories: Int
    public let duration: TimeInterval
}

public struct VolumeInfo: Sendable {
    public let name: String
    public let totalBytes: Int64
    public let availableBytes: Int64
    public var usedBytes: Int64 { totalBytes - availableBytes }

    public static func forPath(_ path: String) -> VolumeInfo {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let important = values?.volumeAvailableCapacityForImportantUsage ?? 0
        let available = important > 0 ? important : Int64(values?.volumeAvailableCapacity ?? 0)
        return VolumeInfo(name: values?.volumeName ?? "Disk", totalBytes: total, availableBytes: available)
    }
}

public struct DockerStatus: Sendable {
    public let installed: Bool
    public let running: Bool
    public let message: String?

    public init(installed: Bool, running: Bool, message: String?) {
        self.installed = installed
        self.running = running
        self.message = message
    }
}

public struct ScanReport: Sendable {
    public let items: [CleanupItem]
    public let tree: SpaceTree
    public let stats: ScanStats
    public let volume: VolumeInfo
    public let docker: DockerStatus
}

public enum DeleteMode: String, Sendable, CaseIterable {
    case moveToTrash
    case deletePermanently
}

public struct CleanProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let bytesFreed: Int64
    public let bytesProcessed: Int64
    public let currentTitle: String
}

public struct CleanFailure: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let reason: String
}

public struct CleanReport: Sendable {
    public let bytesFreed: Int64
    public let cleanedItemIDs: Set<String>
    public let failures: [CleanFailure]
    public let movedToTrash: Bool
    public let trashedPaths: [String]
}

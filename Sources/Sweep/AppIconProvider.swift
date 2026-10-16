import AppKit
import SweepCore

@MainActor
final class AppIconProvider {
    static let shared = AppIconProvider()

    private let icons = NSCache<NSString, NSImage>()
    private var appNames: [String: String] = [:]
    private var missingBundles: Set<String> = []
    private var missingPaths: Set<String> = []

    private init() {
        icons.countLimit = 2000
    }

    func displayName(for item: CleanupItem) -> String {
        guard let bundleID = item.bundleIdentifier else { return item.title }
        return appName(forBundleIdentifier: bundleID) ?? item.title
    }

    func appName(forBundleIdentifier bundleID: String) -> String? {
        if let cached = appNames[bundleID] { return cached }
        guard !missingBundles.contains(bundleID), let url = applicationURL(for: bundleID) else {
            missingBundles.insert(bundleID)
            return nil
        }
        let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        appNames[bundleID] = name
        return name
    }

    func icon(for item: CleanupItem) -> NSImage? {
        if let bundleID = item.bundleIdentifier, let icon = appIcon(forBundleIdentifier: bundleID) {
            return icon
        }
        if let path = item.path {
            return fileIcon(forPath: path)
        }
        return nil
    }

    func appIcon(forBundleIdentifier bundleID: String) -> NSImage? {
        let key = "bundle:" + bundleID as NSString
        if let cached = icons.object(forKey: key) { return cached }
        guard !missingBundles.contains(bundleID), let url = applicationURL(for: bundleID) else {
            missingBundles.insert(bundleID)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(icon, forKey: key)
        return icon
    }

    func fileIcon(forPath path: String) -> NSImage? {
        let key = "path:" + path as NSString
        if let cached = icons.object(forKey: key) { return cached }
        guard !missingPaths.contains(path) else { return nil }
        guard FileManager.default.fileExists(atPath: path) else {
            missingPaths.insert(path)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons.setObject(icon, forKey: key)
        return icon
    }

    private func applicationURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}

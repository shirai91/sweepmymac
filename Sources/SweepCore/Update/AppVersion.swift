import Foundation

public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ text: String) {
        var core = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if core.first == "v" || core.first == "V" { core = core.dropFirst() }
        if let suffixStart = core.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            core = core[..<suffixStart]
        }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        components = parts.map { $0! }
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.padded(to: rhs) == rhs.padded(to: lhs)
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.padded(to: rhs).lexicographicallyPrecedes(rhs.padded(to: lhs))
    }

    private func padded(to other: AppVersion) -> [Int] {
        components + Array(repeating: 0, count: max(0, other.components.count - components.count))
    }
}

import Foundation

enum DockerSizeParser {
    private static let decimalMultipliers: [String: Double] = [
        "B": 1,
        "KB": 1_000,
        "MB": 1_000_000,
        "GB": 1_000_000_000,
        "TB": 1_000_000_000_000,
        "PB": 1_000_000_000_000_000,
    ]

    private static let binaryMultipliers: [String: Double] = [
        "KIB": 1_024,
        "MIB": 1_048_576,
        "GIB": 1_073_741_824,
        "TIB": 1_099_511_627_776,
    ]

    static func bytes(from raw: String) -> Int64 {
        guard let (number, unit) = splitNumberAndUnit(raw), let value = Double(number) else { return 0 }
        guard let multiplier = multiplier(forUnit: unit) else { return 0 }
        let bytes = (value * multiplier).rounded()
        guard bytes.isFinite, bytes >= 0, bytes < Double(Int64.max) else { return 0 }
        return Int64(bytes)
    }

    static func displayString(_ raw: String) -> String {
        guard let (number, unit) = splitNumberAndUnit(raw) else { return "0 B" }
        return "\(number) \(unit.isEmpty ? "B" : displayUnit(unit))"
    }

    private static func multiplier(forUnit unit: String) -> Double? {
        let normalized = unit.uppercased()
        if normalized.isEmpty { return 1 }
        return decimalMultipliers[normalized] ?? binaryMultipliers[normalized]
    }

    private static func displayUnit(_ unit: String) -> String {
        let normalized = unit.uppercased()
        if normalized == "KB" { return "kB" }
        if let binary = binaryMultipliers.keys.first(where: { $0 == normalized }) {
            return binary.prefix(1) + "i" + binary.suffix(1)
        }
        return normalized
    }

    private static func splitNumberAndUnit(_ raw: String) -> (number: String, unit: String)? {
        let withoutPercent = raw.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let trimmed = withoutPercent.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = String(trimmed.prefix(while: { $0.isNumber || $0 == "." }))
        guard !number.isEmpty else { return nil }
        let unit = trimmed.dropFirst(number.count).trimmingCharacters(in: .whitespaces)
        return (number, unit)
    }
}

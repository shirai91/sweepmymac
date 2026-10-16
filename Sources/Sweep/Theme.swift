import SwiftUI
import SweepCore

extension JunkCategory {
    var tint: Color {
        switch self {
        case .appCaches: Color(red: 0.20, green: 0.52, blue: 1.00)
        case .devCaches: Color(red: 0.40, green: 0.36, blue: 0.98)
        case .xcode: Color(red: 0.10, green: 0.70, blue: 0.95)
        case .buildArtifacts: Color(red: 1.00, green: 0.55, blue: 0.10)
        case .docker: Color(red: 0.11, green: 0.45, blue: 0.93)
        case .logs: Color(red: 0.50, green: 0.56, blue: 0.66)
        case .trash: Color(red: 0.98, green: 0.32, blue: 0.38)
        case .installers: Color(red: 0.69, green: 0.38, blue: 0.96)
        case .largeOld: Color(red: 0.83, green: 0.60, blue: 0.20)
        case .duplicates: Color(red: 0.12, green: 0.78, blue: 0.62)
        case .appLeftovers: Color(red: 0.96, green: 0.36, blue: 0.68)
        case .mailAttachments: Color(red: 0.98, green: 0.74, blue: 0.10)
        case .iosBackups: Color(red: 0.25, green: 0.78, blue: 0.35)
        case .systemClutter: Color(red: 0.55, green: 0.45, blue: 0.85)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [tint.mix(with: .white, by: 0.22), tint], startPoint: .top, endPoint: .bottom)
    }
}

extension Safety {
    var tint: Color {
        switch self {
        case .safe: .green
        case .review: .orange
        case .caution: .red
        }
    }

    var shortLabel: String {
        switch self {
        case .safe: "Safe"
        case .review: "Review"
        case .caution: "Caution"
        }
    }

    var symbol: String {
        switch self {
        case .safe: "checkmark.shield.fill"
        case .review: "eye.fill"
        case .caution: "exclamationmark.triangle.fill"
        }
    }
}

enum Theme {
    static let accentStart = Color(red: 0.30, green: 0.45, blue: 1.00)
    static let accentEnd = Color(red: 0.66, green: 0.34, blue: 0.98)
    static let accentGradient = LinearGradient(colors: [accentStart, accentEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let celebrationGradient = LinearGradient(colors: [Color(red: 0.16, green: 0.80, blue: 0.55), Color(red: 0.10, green: 0.62, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let warningGradient = LinearGradient(colors: [Color(red: 1.0, green: 0.70, blue: 0.20), Color(red: 1.0, green: 0.45, blue: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let dangerGradient = LinearGradient(colors: [Color(red: 1.0, green: 0.42, blue: 0.40), Color(red: 0.90, green: 0.18, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let usedColor = Color(red: 0.55, green: 0.58, blue: 0.66)
    static let freeColor = Color.primary.opacity(0.08)
    static let junkColor = Color(red: 1.0, green: 0.50, blue: 0.25)
    static let cardRadius: CGFloat = 16
}

struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }
    }
}

extension View {
    func card(radius: CGFloat = Theme.cardRadius, padding: CGFloat = 20) -> some View {
        modifier(CardBackground(radius: radius, padding: padding))
    }
}

struct CategoryIcon: View {
    let category: JunkCategory
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(category.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: category.symbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
            }
            .shadow(color: category.tint.opacity(0.35), radius: size * 0.12, y: size * 0.05)
    }
}

struct DetailBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [Theme.accentStart.opacity(0.10), .clear],
                center: .topLeading, startRadius: 0, endRadius: 700
            )
            RadialGradient(
                colors: [Theme.accentEnd.opacity(0.07), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 600
            )
        }
        .ignoresSafeArea()
    }
}

enum ByteFormat {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    static func string(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: max(bytes, 0))
    }

    static func parts(_ bytes: Int64) -> (number: String, unit: String) {
        guard bytes > 0 else { return ("0", "KB") }
        let numberFormatter = ByteCountFormatter()
        numberFormatter.countStyle = .file
        numberFormatter.includesUnit = false
        let unitFormatter = ByteCountFormatter()
        unitFormatter.countStyle = .file
        unitFormatter.includesCount = false
        return (numberFormatter.string(fromByteCount: bytes), unitFormatter.string(fromByteCount: bytes))
    }
}

enum CountFormat {
    static func string(_ value: Int) -> String {
        value.formatted(.number)
    }

    static func items(_ value: Int) -> String {
        value == 1 ? "1 item" : "\(string(value)) items"
    }
}

enum DurationFormat {
    static func clock(_ interval: TimeInterval) -> String {
        let total = Int(max(interval, 0))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

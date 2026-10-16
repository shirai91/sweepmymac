import SweepCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: selectionBinding) {
            Section {
                SidebarLink(title: model.hasResults ? "Overview" : "Scan", symbol: model.hasResults ? "square.grid.2x2.fill" : "magnifyingglass", tint: Theme.accentStart, trailing: overviewTrailing)
                    .tag(SidebarDestination.overview)
                SidebarLink(title: "Space Explorer", symbol: "square.split.bottomrightquarter.fill", tint: Color(red: 0.95, green: 0.45, blue: 0.25), trailing: nil)
                    .tag(SidebarDestination.explorer)
                    .disabled(!model.hasResults)
            }
            if model.hasResults && !model.summaries.isEmpty {
                Section("Junk") {
                    ForEach(model.summaries) { summary in
                        CategorySidebarRow(summary: summary, selectedCount: model.selectedCountByCategory[summary.category] ?? 0)
                            .tag(SidebarDestination.category(summary.category))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarDiskMeter()
        }
        .animation(.smooth, value: model.summaries.map(\.category))
    }

    private var overviewTrailing: String? {
        guard model.hasResults else { return nil }
        return ByteFormat.string(model.totalJunkBytes)
    }

    private var selectionBinding: Binding<SidebarDestination?> {
        Binding(
            get: { model.phase == .results || model.phase == .done ? model.destination : .overview },
            set: { newValue in
                guard let newValue, model.phase != .scanning, model.phase != .cleaning else { return }
                if model.hasResults {
                    if model.phase == .home { model.phase = .results }
                    model.navigate(to: newValue)
                } else {
                    model.goHome()
                }
            }
        )
    }
}

struct SidebarLink: View {
    let title: String
    let symbol: String
    let tint: Color
    let trailing: String?

    var body: some View {
        HStack(spacing: 9) {
            SidebarGlyph(symbol: symbol, fill: AnyShapeStyle(LinearGradient(colors: [tint.mix(with: .white, by: 0.2), tint], startPoint: .top, endPoint: .bottom)))
            Text(title)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SidebarGlyph: View {
    let symbol: String
    let fill: AnyShapeStyle

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(fill)
            .frame(width: 22, height: 22)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

struct CategorySidebarRow: View {
    let summary: CategorySummary
    let selectedCount: Int

    var body: some View {
        HStack(spacing: 9) {
            SidebarGlyph(symbol: summary.category.symbol, fill: AnyShapeStyle(summary.category.gradient))
            Text(summary.category.title)
                .lineLimit(1)
            Spacer(minLength: 4)
            if selectedCount > 0 {
                Text(CountFormat.string(selectedCount))
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(summary.category.tint))
                    .contentTransition(.numericText())
            }
            Text(ByteFormat.string(summary.totalSize))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .animation(.snappy, value: selectedCount)
    }
}

struct SidebarDiskMeter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let volume = model.volume
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive.fill")
                    .foregroundStyle(.secondary)
                Text(volume.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
            }
            DiskBar(
                total: volume.totalBytes,
                used: volume.usedBytes,
                junk: model.hasResults ? model.totalJunkBytes : 0,
                height: 6
            )
            Text("\(ByteFormat.string(volume.availableBytes)) free of \(ByteFormat.string(volume.totalBytes))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }
}

struct DiskBar: View {
    let total: Int64
    let used: Int64
    let junk: Int64
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let safeTotal = Double(max(total, 1))
            let junkClamped = min(max(junk, 0), max(used, 0))
            let usedWidth = width * Double(max(used - junkClamped, 0)) / safeTotal
            let junkWidth = width * Double(junkClamped) / safeTotal
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.freeColor)
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.usedColor.gradient).frame(width: usedWidth)
                    Rectangle().fill(Theme.junkColor.gradient).frame(width: junkWidth)
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.6), value: junk)
        .animation(.smooth(duration: 0.6), value: used)
    }
}

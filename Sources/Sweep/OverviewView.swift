import AppKit
import SweepCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !model.hasFullDiskAccess {
                    FullDiskAccessBanner()
                }
                if model.summaries.isEmpty {
                    SpotlessCard()
                } else {
                    HeroCard()
                    DiskImpactCard()
                }
                if let docker = model.docker, docker.installed, !docker.running {
                    DockerNotRunningCard(message: docker.message)
                }
                if !model.summaries.isEmpty {
                    CategoryGrid()
                }
                if let results = model.results {
                    ScanFootnote(results: results)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
    }
}

struct HeroCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let parts = ByteFormat.parts(model.totalJunkBytes)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sweep found")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(parts.number)
                            .font(.system(size: 64, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(model.totalJunkBytes)))
                        Text(parts.unit)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("can be freed")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)
                    }
                    .foregroundStyle(Theme.accentGradient)
                    .animation(.snappy, value: model.totalJunkBytes)
                }
                Spacer(minLength: 16)
                SelectionSummary()
            }
            CategoryStackBar(summaries: model.summaries, total: model.totalJunkBytes)
                .frame(height: 14)
            CategoryLegend(summaries: Array(model.summaries.prefix(6)))
        }
        .card(padding: 24)
    }
}

struct SelectionSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Button(action: model.smartSelect) {
                Label("Smart Select", systemImage: "wand.and.stars")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.accentStart)
            .help("Select everything Sweep recommends removing")
            Text("\(CountFormat.items(model.selectedCount)) selected · \(ByteFormat.string(model.selectedBytes))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(model.selectedBytes)))
                .animation(.snappy, value: model.selectedBytes)
        }
    }
}

struct CategoryStackBar: View {
    let summaries: [CategorySummary]
    let total: Int64

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 2
            let available = proxy.size.width - spacing * CGFloat(max(summaries.count - 1, 0))
            HStack(spacing: spacing) {
                ForEach(summaries) { summary in
                    Rectangle()
                        .fill(summary.category.gradient)
                        .frame(width: max(2, available * CGFloat(summary.totalSize) / CGFloat(max(total, 1))))
                        .help("\(summary.category.title): \(ByteFormat.string(summary.totalSize))")
                }
            }
            .clipShape(Capsule())
        }
        .animation(.smooth(duration: 0.5), value: total)
    }
}

struct CategoryLegend: View {
    let summaries: [CategorySummary]

    var body: some View {
        FlowLayout(spacing: 18, lineSpacing: 8, alignment: .leading) {
            ForEach(summaries) { summary in
                HStack(spacing: 6) {
                    Circle().fill(summary.category.tint).frame(width: 8, height: 8)
                    Text(summary.category.title)
                        .foregroundStyle(.secondary)
                    Text(ByteFormat.string(summary.totalSize))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                .font(.callout)
                .fixedSize()
            }
        }
    }
}

struct DiskImpactCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let volume = model.volume
        let freeAfter = volume.availableBytes + model.selectedBytes
        HStack(spacing: 22) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(0.06)))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(volume.name)
                        .font(.headline)
                    Text(ByteFormat.string(volume.totalBytes))
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("After cleaning you'll have")
                            .foregroundStyle(.secondary)
                        Text(ByteFormat.string(freeAfter))
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.celebrationGradient)
                            .contentTransition(.numericText(value: Double(freeAfter)))
                        Text("free")
                            .foregroundStyle(.secondary)
                    }
                    .animation(.snappy, value: freeAfter)
                }
                DiskBar(total: volume.totalBytes, used: volume.usedBytes, junk: model.selectedBytes, height: 12)
                HStack(spacing: 18) {
                    LegendDot(color: Theme.usedColor, title: "Used", value: ByteFormat.string(max(volume.usedBytes - model.selectedBytes, 0)))
                    LegendDot(color: Theme.junkColor, title: "Selected junk", value: ByteFormat.string(model.selectedBytes))
                    LegendDot(color: Color.primary.opacity(0.18), title: "Free", value: ByteFormat.string(volume.availableBytes))
                    Spacer()
                }
            }
        }
        .card()
    }
}

struct LegendDot: View {
    let color: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}

struct CategoryGrid: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 210, maximum: 400), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Categories")
                .font(.title3.weight(.semibold))
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(model.summaries) { summary in
                    CategoryCard(
                        summary: summary,
                        selectedCount: model.selectedCountByCategory[summary.category] ?? 0,
                        selectedBytes: model.selectedBytesByCategory[summary.category] ?? 0
                    ) {
                        model.navigate(to: .category(summary.category))
                    }
                }
            }
        }
    }
}

struct CategoryCard: View {
    let summary: CategorySummary
    let selectedCount: Int
    let selectedBytes: Int64
    let open: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    CategoryIcon(category: summary.category, size: 38)
                    Spacer()
                    if selectedCount > 0 {
                        Label(CountFormat.string(selectedCount), systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(summary.category.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(summary.category.tint.opacity(0.12)))
                            .contentTransition(.numericText())
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                        .opacity(isHovering ? 1 : 0.4)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.category.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(ByteFormat.string(summary.totalSize))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text(selectionCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                SafetyMixBar(safetyBytes: summary.safetyBytes, total: summary.totalSize)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.06 : 0.035))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .strokeBorder(isHovering ? summary.category.tint.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .shadow(color: summary.category.tint.opacity(isHovering ? 0.18 : 0), radius: 14, y: 6)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .offset(y: isHovering ? -2 : 0)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering in withAnimation(.snappy(duration: 0.2)) { isHovering = hovering } }
        .help(summary.category.subtitle)
        .animation(.snappy, value: selectedCount)
    }

    private var selectionCaption: String {
        let total = CountFormat.items(summary.items.count)
        guard selectedCount > 0 else { return total }
        return "\(total) · \(ByteFormat.string(selectedBytes)) selected"
    }
}

struct SafetyMixBar: View {
    let safetyBytes: [Safety: Int64]
    let total: Int64

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(Safety.allCases, id: \.self) { safety in
                    let bytes = safetyBytes[safety] ?? 0
                    if bytes > 0 {
                        Rectangle()
                            .fill(safety.tint.opacity(0.85))
                            .frame(width: max(3, (proxy.size.width - 4) * CGFloat(bytes) / CGFloat(max(total, 1))))
                    }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 4)
        .help(safetyHelp)
    }

    private var safetyHelp: String {
        Safety.allCases.compactMap { safety in
            guard let bytes = safetyBytes[safety], bytes > 0 else { return nil }
            return "\(safety.label): \(ByteFormat.string(bytes))"
        }
        .joined(separator: "\n")
    }
}

struct SpotlessCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.celebrationGradient)
                .symbolEffect(.bounce, options: .nonRepeating)
            Text("Your Mac is spotless")
                .font(.title.weight(.bold))
            Text("Sweep found nothing worth removing. Check back after a few busy weeks.")
                .foregroundStyle(.secondary)
            Button("Scan Again", action: model.startScan)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .card()
    }
}

struct DockerNotRunningCard: View {
    @Environment(AppModel.self) private var model
    let message: String?

    var body: some View {
        HStack(spacing: 16) {
            CategoryIcon(category: .docker, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text("Docker isn't running")
                    .font(.headline)
                Text(message ?? "Start Docker Desktop to review unused images, stopped containers and build cache.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Open Docker", action: openDocker)
                .controlSize(.large)
            Button {
                Task { await DockerRefresher.refresh(model) }
            } label: {
                HStack(spacing: 6) {
                    if model.isRefreshingDocker {
                        ProgressView().controlSize(.small)
                    }
                    Text("Rescan Docker")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(JunkCategory.docker.tint)
            .controlSize(.large)
            .disabled(model.isRefreshingDocker)
        }
        .card(padding: 16)
    }

    private func openDocker() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Docker.app"), configuration: NSWorkspace.OpenConfiguration())
    }
}

struct ScanFootnote: View {
    let results: ScanResults

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
            Text("Scanned \(CountFormat.string(results.filesScanned)) files in \(CountFormat.string(results.directoriesScanned)) folders (\(ByteFormat.string(results.bytesScanned))) in \(String(format: "%.1f", results.duration)) s")
            if results.inaccessibleDirectories > 0 {
                Text("· \(CountFormat.string(results.inaccessibleDirectories)) folders were not readable")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

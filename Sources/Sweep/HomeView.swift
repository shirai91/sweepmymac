import AppKit
import SweepCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                if !model.hasFullDiskAccess {
                    FullDiskAccessBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 56) {
                    DiskRing(volume: model.volume)
                        .frame(width: 260, height: 260)
                    VStack(alignment: .leading, spacing: 22) {
                        HomeHeadline()
                        ScopePicker()
                        ScanButton()
                        if model.hasResults {
                            Button("Back to last results") { model.navigate(to: .overview); model.phase = .results }
                                .buttonStyle(.link)
                        }
                    }
                    .frame(maxWidth: 420, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                CategoryChips()
                    .frame(maxWidth: 760)
            }
            .padding(.horizontal, 40)
            .padding(.top, 36)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, minHeight: 600)
            .animation(.smooth, value: model.hasFullDiskAccess)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

struct HomeHeadline: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Make room for what matters.")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Sweep scans your whole disk in seconds and finds caches, build leftovers, old installers and other junk that is safe to remove.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ScanButton: View {
    @Environment(AppModel.self) private var model
    @State private var isHovering = false

    var body: some View {
        Button(action: model.startScan) {
            HStack(spacing: 12) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
                Text("Scan")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("⌘R")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.2)))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 34)
            .frame(height: 58)
            .background {
                Capsule()
                    .fill(Theme.accentGradient)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: Theme.accentStart.opacity(isHovering ? 0.55 : 0.35), radius: isHovering ? 18 : 12, y: 6)
            }
            .scaleEffect(isHovering ? 1.03 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering in withAnimation(.snappy(duration: 0.2)) { isHovering = hovering } }
        .disabled(!model.canStartScan)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

enum ScopeOption: Hashable {
    case entireDisk
    case home
    case folder
}

struct ScopePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Scope", selection: optionBinding) {
                Label("Entire Disk", systemImage: "internaldrive").tag(ScopeOption.entireDisk)
                Label("Home Folder", systemImage: "house").tag(ScopeOption.home)
                Label(folderLabel, systemImage: "folder").tag(ScopeOption.folder)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 380)
            if case .folder(let path) = model.scope {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundStyle(.secondary)
                    Text(path)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Change…", action: chooseFolder)
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }
        }
    }

    private var folderLabel: String {
        if case .folder = model.scope { return model.scope.title }
        return "Choose Folder…"
    }

    private var optionBinding: Binding<ScopeOption> {
        Binding(
            get: {
                switch model.scope {
                case .entireDisk: .entireDisk
                case .home: .home
                case .folder: .folder
                }
            },
            set: { option in
                switch option {
                case .entireDisk: model.scope = .entireDisk
                case .home: model.scope = .home
                case .folder: chooseFolder()
                }
            }
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder for Sweep to scan."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.scope = .folder(url.path)
    }
}

struct CategoryChips: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("WHAT SWEEP CHECKS")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(JunkCategory.allCases) { category in
                    HStack(spacing: 6) {
                        Image(systemName: category.symbol)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(category.tint)
                        Text(category.title)
                            .font(.callout)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(category.tint.opacity(0.10)))
                    .overlay(Capsule().strokeBorder(category.tint.opacity(0.18), lineWidth: 1))
                    .help(category.subtitle)
                }
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    var alignment: HorizontalAlignment = .center

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = alignment == .leading ? bounds.minX : bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if proposedWidth > width && !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

struct DiskRing: View {
    let volume: VolumeInfo
    @State private var appeared = false

    private var usedFraction: Double {
        guard volume.totalBytes > 0 else { return 0 }
        return Double(volume.usedBytes) / Double(volume.totalBytes)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.freeColor, lineWidth: 26)
            Circle()
                .trim(from: 0, to: appeared ? usedFraction : 0)
                .stroke(
                    AngularGradient(colors: [Theme.accentStart, Theme.accentEnd, Color(red: 0.98, green: 0.40, blue: 0.60), Theme.accentStart], center: .center),
                    style: StrokeStyle(lineWidth: 26, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.accentEnd.opacity(0.35), radius: 14)
            VStack(spacing: 4) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                Text(ByteFormat.string(volume.usedBytes))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("used of \(ByteFormat.string(volume.totalBytes))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(volume.name)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .padding(.top, 4)
                Text("\(ByteFormat.string(volume.availableBytes)) available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .onAppear {
            withAnimation(.spring(duration: 1.2, bounce: 0.15).delay(0.1)) { appeared = true }
        }
    }
}

struct FullDiskAccessBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.warningGradient)
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text("Give Sweep Full Disk Access")
                    .font(.headline)
                Text("macOS hides Mail, Safari, and some app data until you allow it. Without access, Sweep can't see all of your junk.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Check Again", action: model.refreshFullDiskAccess)
                .controlSize(.large)
            Button("Grant Access", action: model.openFullDiskAccessSettings)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.orange.opacity(0.25), lineWidth: 1))
        }
    }
}

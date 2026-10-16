import SweepCore
import SwiftUI

struct CleanBar: View {
    @Environment(AppModel.self) private var model
    @AppStorage(DeleteMode.storageKey) private var deleteMode: DeleteMode = .moveToTrash

    var body: some View {
        HStack(spacing: 16) {
            SelectedCategoryDots()
            VStack(alignment: .leading, spacing: 1) {
                Text(ByteFormat.string(model.selectedBytes))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(model.selectedBytes)))
                Text(model.selection.isEmpty ? "Nothing selected" : "\(CountFormat.items(model.selectedCount)) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(model.selectedCount)))
            }
            .animation(.snappy, value: model.selectedBytes)
            Spacer(minLength: 12)
            Picker("Delete mode", selection: $deleteMode) {
                ForEach(DeleteMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help("Choose whether Sweep moves items to the Trash or deletes them right away")
            CleanButton(enabled: model.canClean, permanent: deleteMode == .deletePermanently, action: model.requestClean)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background {
            Rectangle()
                .fill(.bar)
                .overlay(alignment: .top) { Divider() }
                .ignoresSafeArea()
        }
    }
}

struct SelectedCategoryDots: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let selectedCategories = model.summaries.map(\.category).filter { (model.selectedCountByCategory[$0] ?? 0) > 0 }
        ZStack {
            if selectedCategories.isEmpty {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 38, height: 38)
                    .overlay(Image(systemName: "tray").foregroundStyle(.tertiary))
            } else {
                ForEach(Array(selectedCategories.prefix(3).enumerated()), id: \.element) { index, category in
                    CategoryIcon(category: category, size: 30)
                        .offset(x: CGFloat(index) * 12)
                        .zIndex(Double(-index))
                }
            }
        }
        .frame(width: 60, alignment: .leading)
        .animation(.snappy, value: selectedCategories)
    }
}

struct CleanButton: View {
    let enabled: Bool
    let permanent: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: permanent ? "xmark.bin.fill" : "trash.fill")
                Text("Clean")
                Text("⌘⌫")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .opacity(0.75)
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 38)
            .background {
                Capsule()
                    .fill(permanent ? Theme.dangerGradient : Theme.accentGradient)
                    .shadow(color: (permanent ? Color.red : Theme.accentStart).opacity(enabled ? (isHovering ? 0.5 : 0.3) : 0), radius: 10, y: 4)
            }
            .saturation(enabled ? 1 : 0)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!enabled)
        .onHover { hovering in withAnimation(.snappy(duration: 0.2)) { isHovering = hovering } }
    }
}

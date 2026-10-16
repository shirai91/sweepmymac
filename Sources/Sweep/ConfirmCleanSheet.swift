import SweepCore
import SwiftUI

struct ConfirmCleanSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DeleteMode.storageKey) private var deleteMode: DeleteMode = .moveToTrash

    var body: some View {
        let items = model.selectedItems
        let reviewCount = items.filter { $0.safety == .review }.count
        let cautionCount = items.filter { $0.safety == .caution }.count
        VStack(alignment: .leading, spacing: 18) {
            ConfirmHeader(bytes: model.selectedBytes, permanent: isPermanent)
            ConfirmCategoryList(rows: categoryRows)
            if reviewCount + cautionCount > 0 {
                RiskWarning(reviewCount: reviewCount, cautionCount: cautionCount)
            }
            Picker("Mode", selection: $deleteMode) {
                ForEach(DeleteMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ConsequenceLine(count: items.count, permanent: isPermanent)
            if !isPermanent && directRemovalCount(items) > 0 {
                Label("\(CountFormat.items(directRemovalCount(items))) (Docker data, simulators or Trash contents) can't go to the Trash and will be removed directly.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                confirmButton
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private var isPermanent: Bool { deleteMode == .deletePermanently }

    private func directRemovalCount(_ items: [CleanupItem]) -> Int {
        items.filter { item in
            if case .removePaths = item.action { return false }
            return true
        }.count
    }

    @ViewBuilder
    private var confirmButton: some View {
        let button = Button(role: .destructive, action: model.clean) {
            Text(isPermanent ? "Delete \(ByteFormat.string(model.selectedBytes))" : "Move to Trash")
                .frame(minWidth: 120)
        }
        .buttonStyle(.borderedProminent)
        .tint(isPermanent ? .red : Theme.accentStart)
        .controlSize(.large)
        if isPermanent {
            button
        } else {
            button.keyboardShortcut(.defaultAction)
        }
    }

    private var categoryRows: [ConfirmCategoryRow.Model] {
        model.summaries.compactMap { summary in
            let count = model.selectedCountByCategory[summary.category] ?? 0
            guard count > 0 else { return nil }
            return ConfirmCategoryRow.Model(category: summary.category, count: count, bytes: model.selectedBytesByCategory[summary.category] ?? 0)
        }
    }
}

struct ConfirmHeader: View {
    let bytes: Int64
    let permanent: Bool

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(permanent ? Theme.dangerGradient : Theme.accentGradient)
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: permanent ? "xmark.bin.fill" : "trash.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("Clean \(ByteFormat.string(bytes))?")
                    .font(.title2.weight(.bold))
                Text("Review what Sweep is about to remove.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ConfirmCategoryList: View {
    let rows: [ConfirmCategoryRow.Model]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    ConfirmCategoryRow(model: row)
                    if row.id != rows.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
        .frame(maxHeight: 260)
        .fixedSize(horizontal: false, vertical: true)
        .card(radius: 12, padding: 6)
    }
}

struct ConfirmCategoryRow: View {
    struct Model: Identifiable {
        let category: JunkCategory
        let count: Int
        let bytes: Int64
        var id: JunkCategory { category }
    }

    let model: Model

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: model.category, size: 26)
            Text(model.category.title)
            Spacer()
            Text(CountFormat.items(model.count))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(ByteFormat.string(model.bytes))
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }
}

struct RiskWarning: View {
    let reviewCount: Int
    let cautionCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: cautionCount > 0 ? "exclamationmark.triangle.fill" : "eye.fill")
                .foregroundStyle(cautionCount > 0 ? .red : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .fontWeight(.semibold)
                Text("These may hold data you still want, like backups, archives or downloads. Make sure you checked them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill((cautionCount > 0 ? Color.red : Color.orange).opacity(0.10))
        }
    }

    private var headline: String {
        var parts: [String] = []
        if cautionCount > 0 { parts.append("\(cautionCount) marked Caution") }
        if reviewCount > 0 { parts.append("\(reviewCount) marked Review") }
        return "Selection includes " + parts.joined(separator: " and ")
    }
}

struct ConsequenceLine: View {
    let count: Int
    let permanent: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: permanent ? "exclamationmark.octagon.fill" : "arrow.uturn.backward.circle.fill")
                .foregroundStyle(permanent ? .red : .green)
            Text(permanent
                 ? "This permanently deletes \(CountFormat.items(count)). This cannot be undone."
                 : "This moves \(CountFormat.items(count)) to the Trash. You can put them back until you empty it.")
                .font(.callout)
                .foregroundStyle(permanent ? .primary : .secondary)
        }
    }
}

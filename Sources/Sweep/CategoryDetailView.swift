import AppKit
import SweepCore
import SwiftUI

struct DetailRow: Identifiable {
    let item: CleanupItem
    let name: String
    let sortDate: Date

    var id: String { item.id }
    var size: Int64 { item.size }
    var safetyRank: Int { item.safety.rawValue }
}

enum DetailSort: String, CaseIterable, Identifiable {
    case size
    case name
    case date

    var id: String { rawValue }

    var title: String {
        switch self {
        case .size: "Size"
        case .name: "Name"
        case .date: "Last Modified"
        }
    }

    var comparator: KeyPathComparator<DetailRow> {
        switch self {
        case .size: KeyPathComparator(\DetailRow.size, order: .reverse)
        case .name: KeyPathComparator(\DetailRow.name, comparator: .localizedStandard)
        case .date: KeyPathComparator(\DetailRow.sortDate, order: .forward)
        }
    }
}

struct RowsKey: Hashable {
    let query: String
    let sortOrder: [KeyPathComparator<DetailRow>]
    let itemCount: Int
    let totalSize: Int64
}

struct CategoryDetailView: View {
    let category: JunkCategory
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var sortOrder = [DetailSort.size.comparator]
    @State private var rows: [DetailRow] = []
    @State private var highlighted: Set<String> = []

    var body: some View {
        if let summary = model.summary(for: category) {
            VStack(spacing: 0) {
                CategoryHeader(
                    summary: summary,
                    selectedCount: model.selectedCountByCategory[category] ?? 0,
                    selectedBytes: model.selectedBytesByCategory[category] ?? 0
                )
                DetailControls(
                    query: $query,
                    sort: sortBinding,
                    selectRecommended: { selectRecommended(in: summary) },
                    selectAll: { model.setChecked(rows.map(\.id), true) },
                    selectNone: { model.setChecked(rows.map(\.id), false) }
                )
                Divider()
                ItemTable(
                    rows: rows,
                    largestSize: summary.largestItemSize,
                    tint: category.tint,
                    highlighted: $highlighted,
                    sortOrder: $sortOrder
                )
                .overlay {
                    if rows.isEmpty && !query.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .task(id: RowsKey(query: query, sortOrder: sortOrder, itemCount: summary.items.count, totalSize: summary.totalSize)) {
                rows = buildRows(from: summary)
            }
        } else {
            ContentUnavailableView("Nothing left here", systemImage: "checkmark.circle", description: Text("Everything in this category was cleaned or ignored."))
        }
    }

    private var sortBinding: Binding<DetailSort> {
        Binding(
            get: {
                guard let first = sortOrder.first else { return .size }
                if first.keyPath == \DetailRow.name { return .name }
                if first.keyPath == \DetailRow.sortDate { return .date }
                return .size
            },
            set: { sortOrder = [$0.comparator] }
        )
    }

    private func buildRows(from summary: CategorySummary) -> [DetailRow] {
        let icons = AppIconProvider.shared
        let needle = query.trimmingCharacters(in: .whitespaces)
        let all = summary.items.map { item in
            DetailRow(item: item, name: icons.displayName(for: item), sortDate: item.lastModified ?? .distantPast)
        }
        let filtered = needle.isEmpty ? all : all.filter { row in
            row.name.localizedCaseInsensitiveContains(needle)
                || row.item.detail.localizedCaseInsensitiveContains(needle)
                || (row.item.path?.localizedCaseInsensitiveContains(needle) ?? false)
        }
        return filtered.sorted(using: sortOrder)
    }

    private func selectRecommended(in summary: CategorySummary) {
        let visibleIDs = Set(rows.map(\.id))
        let scoped = summary.items.filter { visibleIDs.contains($0.id) }
        model.setChecked(scoped.filter { !$0.recommended }.map(\.id), false)
        model.setChecked(scoped.filter(\.recommended).map(\.id), true)
    }
}

struct CategoryHeader: View {
    let summary: CategorySummary
    let selectedCount: Int
    let selectedBytes: Int64

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            CategoryIcon(category: summary.category, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.category.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(summary.category.subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 4) {
                Text(ByteFormat.string(summary.totalSize))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(summary.category.gradient)
                Text("\(CountFormat.string(selectedCount)) of \(CountFormat.items(summary.items.count)) selected · \(ByteFormat.string(selectedBytes))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: Double(selectedBytes)))
                    .animation(.snappy, value: selectedBytes)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }
}

struct DetailControls: View {
    @Binding var query: String
    @Binding var sort: DetailSort
    let selectRecommended: () -> Void
    let selectAll: () -> Void
    let selectNone: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SearchField(text: $query, prompt: "Filter items")
                .frame(maxWidth: 280)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Text("Select")
                    .foregroundStyle(.secondary)
                Button(action: selectRecommended) {
                    Label("Recommended", systemImage: "wand.and.stars")
                }
                .help("Select only the items Sweep recommends")
                Button("All", action: selectAll)
                Button("None", action: selectNone)
            }
            .fixedSize()
            Divider().frame(height: 18)
            HStack(spacing: 6) {
                Text("Sort by")
                    .foregroundStyle(.secondary)
                Picker("Sort by", selection: $sort) {
                    ForEach(DetailSort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .fixedSize()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}

struct SearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(focused ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: focused ? 2 : 1)
                )
        }
    }
}

struct ItemTable: View {
    let rows: [DetailRow]
    let largestSize: Int64
    let tint: Color
    @Binding var highlighted: Set<String>
    @Binding var sortOrder: [KeyPathComparator<DetailRow>]
    @Environment(AppModel.self) private var model

    var body: some View {
        Table(rows, selection: $highlighted, sortOrder: $sortOrder) {
            TableColumn("") { row in
                Toggle("", isOn: checkBinding(for: row.id))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            .width(22)
            TableColumn("Name", value: \.name) { row in
                NameCell(row: row)
            }
            .width(min: 240, ideal: 420)
            TableColumn("Size", value: \.size) { row in
                SizeCell(size: row.size, fraction: Double(row.size) / Double(max(largestSize, 1)), tint: tint)
            }
            .width(min: 120, ideal: 150, max: 220)
            TableColumn("Modified", value: \.sortDate) { row in
                Text(row.item.lastModified.map(RelativeDate.string) ?? "—")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110, max: 150)
            TableColumn("Safety", value: \.safetyRank) { row in
                SafetyBadge(safety: row.item.safety)
            }
            .width(min: 84, ideal: 92, max: 120)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: String.self) { ids in
            ItemContextMenu(ids: ids, rows: rows)
        } primaryAction: { ids in
            QuickLookPreview.shared.toggle(paths: paths(for: ids))
        }
        .onKeyPress(.space) {
            QuickLookPreview.shared.toggle(paths: paths(for: highlighted))
            return .handled
        }
    }

    private func paths(for ids: Set<String>) -> [String] {
        rows.filter { ids.contains($0.id) }.flatMap(\.item.previewPaths)
    }

    private func checkBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { model.isSelected(id) },
            set: { checked in
                let targets = highlighted.contains(id) && highlighted.count > 1 ? highlighted : [id]
                model.setChecked(targets, checked)
            }
        )
    }
}

struct ItemContextMenu: View {
    let ids: Set<String>
    let rows: [DetailRow]
    @Environment(AppModel.self) private var model

    var body: some View {
        let selectedItems = rows.filter { ids.contains($0.id) }.map(\.item)
        let paths = selectedItems.flatMap(\.previewPaths)
        let allPaths = selectedItems.flatMap(\.allPaths)
        let allChecked = ids.allSatisfy(model.isSelected)
        if !ids.isEmpty {
            Button("Reveal in Finder") { FinderActions.reveal(paths) }
                .disabled(paths.isEmpty)
            Button("Quick Look") { QuickLookPreview.shared.toggle(paths: paths) }
                .disabled(paths.isEmpty)
            Button(allPaths.count > 1 ? "Copy \(allPaths.count) Paths" : "Copy Path") { FinderActions.copy(allPaths) }
                .disabled(allPaths.isEmpty)
            Divider()
            Button(allChecked ? "Don't Clean" : "Mark for Cleaning") { model.setChecked(ids, !allChecked) }
            Divider()
            Button(ids.count > 1 ? "Always Ignore \(ids.count) Items" : "Always Ignore") { model.ignore(Array(ids)) }
        }
    }
}

struct NameCell: View {
    let row: DetailRow

    var body: some View {
        HStack(spacing: 10) {
            ItemIcon(item: row.item, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if row.item.itemCount > 1 {
                        Text(CountFormat.items(row.item.itemCount))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                }
                SecondaryLine(item: row.item)
            }
        }
        .padding(.vertical, 3)
    }
}

struct SecondaryLine: View {
    let item: CleanupItem

    var body: some View {
        HStack(spacing: 0) {
            if let path = item.path {
                Text(PathDisplay.abbreviated(path))
                    .truncationMode(.middle)
                    .layoutPriority(1)
                if !item.detail.isEmpty {
                    Text("  ·  " + item.detail)
                        .foregroundStyle(.tertiary)
                        .truncationMode(.tail)
                }
            } else {
                Text(item.detail)
                    .truncationMode(.tail)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .help([item.detail, item.path ?? ""].filter { !$0.isEmpty }.joined(separator: "\n"))
    }
}

extension CleanupItem {
    var allPaths: [String] {
        switch action {
        case .removePaths(let paths) where !paths.isEmpty: paths
        case .emptyTrash(let paths) where !paths.isEmpty: paths
        default: path.map { [$0] } ?? []
        }
    }

    var previewPaths: [String] {
        Array(allPaths.prefix(20))
    }
}

enum PathDisplay {
    static let home = NSHomeDirectory()

    static func abbreviated(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

enum RelativeDate {
    static func string(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}

struct ItemIcon: View {
    let item: CleanupItem
    var size: CGFloat = 28
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(item.category.tint.opacity(0.16))
                    .overlay {
                        Image(systemName: ItemSymbol.name(for: item))
                            .font(.system(size: size * 0.46, weight: .semibold))
                            .foregroundStyle(item.category.tint)
                    }
                    .padding(1)
            }
        }
        .frame(width: size, height: size)
        .task(id: item.id) {
            image = AppIconProvider.shared.icon(for: item)
        }
    }
}

enum ItemSymbol {
    static func name(for item: CleanupItem) -> String {
        switch item.action {
        case .docker(.removeImage): "shippingbox.fill"
        case .docker(.removeContainer): "cube.fill"
        case .docker(.removeVolume): "externaldrive.fill"
        case .docker(.pruneBuildCache): "hammer.fill"
        case .deleteUnavailableSimulators: "iphone.slash"
        case .emptyTrash: "trash.fill"
        case .removePaths: item.category.symbol
        }
    }
}

struct SizeCell: View {
    let size: Int64
    let fraction: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(3, proxy.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(width: 44, height: 4)
            Text(ByteFormat.string(size))
                .monospacedDigit()
                .frame(minWidth: 64, alignment: .trailing)
        }
    }
}

struct SafetyBadge: View {
    let safety: Safety

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: safety.symbol)
                .font(.system(size: 9, weight: .bold))
            Text(safety.shortLabel)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(safety.tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(safety.tint.opacity(0.13)))
        .help(safety.label)
    }
}

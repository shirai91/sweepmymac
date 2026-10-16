import SweepCore
import SwiftUI

struct ExplorerListing: Sendable {
    let node: SpaceNode
    let ancestors: [SpaceNode]
    let topChildren: [SpaceNode]
    let remainingCount: Int
    let remainingBytes: Int64

    static let visibleLimit = 50

    static func load(tree: SpaceTree, nodeID: Int32) -> ExplorerListing {
        let node = tree.node(nodeID)
        let children = tree.children(of: nodeID)
        let top = Array(children.prefix(visibleLimit))
        let rest = children.dropFirst(visibleLimit)
        return ExplorerListing(
            node: node,
            ancestors: tree.ancestors(of: nodeID),
            topChildren: top,
            remainingCount: rest.count,
            remainingBytes: rest.reduce(0) { $0 + $1.size }
        )
    }
}

struct LayoutRequest: Hashable {
    let nodeID: Int32
    let width: Int
    let height: Int
}

struct SpaceExplorerView: View {
    @Environment(AppModel.self) private var model
    @State private var listing: ExplorerListing?
    @State private var layout: TreemapLayoutResult?
    @State private var canvasSize: CGSize = .zero
    @State private var hoveredNodeID: Int32?

    var body: some View {
        if let tree = model.tree, tree.nodeCount > 1 {
            content(tree: tree)
        } else {
            ContentUnavailableView {
                Label("No folder sizes yet", systemImage: "square.split.bottomrightquarter")
            } description: {
                Text("Run a scan to see what takes up space on your disk.")
            } actions: {
                Button("Scan", action: model.startScan)
            }
        }
    }

    private func content(tree: SpaceTree) -> some View {
        VStack(spacing: 0) {
            ExplorerHeader(listing: listing, canGoUp: model.explorerNodeID != 0, goUp: goUp, open: open)
            HStack(spacing: 16) {
                treemapPane(tree: tree)
                ExplorerSideList(listing: listing, hoveredNodeID: $hoveredNodeID, open: open)
                    .frame(width: 300)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .task(id: model.explorerNodeID) {
            let nodeID = model.explorerNodeID
            listing = await Task.detached(priority: .userInitiated) { ExplorerListing.load(tree: tree, nodeID: nodeID) }.value
        }
    }

    private func treemapPane(tree: SpaceTree) -> some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                if let layout {
                    TreemapView(layout: layout, highlightedNodeID: hoveredNodeID, onOpen: open)
                        .padding(4)
                        .id(layout.nodeID)
                        .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity))
                } else {
                    ProgressView()
                }
            }
            .animation(.smooth(duration: 0.35), value: layout?.nodeID)
            .task(id: LayoutRequest(nodeID: model.explorerNodeID, width: Int(proxy.size.width), height: Int(proxy.size.height))) {
                await relayout(tree: tree, size: CGSize(width: proxy.size.width - 8, height: proxy.size.height - 8))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func relayout(tree: SpaceTree, size: CGSize) async {
        guard size.width > 20, size.height > 20 else { return }
        let nodeID = model.explorerNodeID
        if layout != nil, layout?.nodeID == nodeID {
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
        }
        let result = await Task.detached(priority: .userInitiated) {
            TreemapBuilder.build(tree: tree, nodeID: nodeID, size: size)
        }.value
        guard !Task.isCancelled else { return }
        layout = result
    }

    private func open(_ nodeID: Int32) {
        hoveredNodeID = nil
        model.explorerNodeID = nodeID
    }

    private func goUp() {
        guard let parent = model.tree?.parent(of: model.explorerNodeID) else { return }
        open(parent)
    }
}

struct ExplorerHeader: View {
    let listing: ExplorerListing?
    let canGoUp: Bool
    let goUp: () -> Void
    let open: (Int32) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: goUp) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 22)
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!canGoUp)
            .help("Go to the enclosing folder (⌘[)")
            Breadcrumbs(ancestors: listing?.ancestors ?? [], open: open)
            Spacer(minLength: 12)
            if let node = listing?.node {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(ByteFormat.string(node.size))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("\(CountFormat.string(node.fileCount)) files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Button {
                    FinderActions.reveal([node.path])
                } label: {
                    Image(systemName: "folder")
                }
                .help("Reveal in Finder")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
}

struct Breadcrumbs: View {
    let ancestors: [SpaceNode]
    let open: (Int32) -> Void

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(ancestors.enumerated()), id: \.element.id) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.compact.right")
                                .foregroundStyle(.tertiary)
                        }
                        BreadcrumbButton(title: title(for: node, index: index), isCurrent: index == ancestors.count - 1, isRoot: index == 0) {
                            open(node.id)
                        }
                        .id(node.id)
                    }
                }
            }
            .onChange(of: ancestors.last?.id) { _, last in
                if let last { withAnimation { reader.scrollTo(last, anchor: .trailing) } }
            }
        }
    }

    private func title(for node: SpaceNode, index: Int) -> String {
        guard index == 0 else { return node.name }
        if node.path == "/" { return VolumeInfo.forPath("/").name }
        return PathDisplay.abbreviated(node.path)
    }
}

struct BreadcrumbButton: View {
    let title: String
    let isCurrent: Bool
    let isRoot: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isRoot {
                    Image(systemName: "internaldrive")
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(isCurrent ? .title3.weight(.semibold) : .title3)
            .foregroundStyle(isCurrent ? .primary : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(isHovering && !isCurrent ? 0.07 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct ExplorerSideList: View {
    let listing: ExplorerListing?
    @Binding var hoveredNodeID: Int32?
    let open: (Int32) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let listing {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(listing.topChildren.enumerated()), id: \.element.id) { index, child in
                            ExplorerRow(
                                name: child.name,
                                size: child.size,
                                fraction: fraction(child.size, of: listing),
                                color: TreemapPalette.colors[index % TreemapPalette.colors.count],
                                symbol: "folder.fill",
                                isNavigable: child.hasChildren
                            ) {
                                if child.hasChildren { open(child.id) }
                            }
                            .onHover { hovering in hoveredNodeID = hovering ? child.id : (hoveredNodeID == child.id ? nil : hoveredNodeID) }
                            .contextMenu {
                                Button("Reveal in Finder") { FinderActions.reveal([child.path]) }
                                Button("Copy Path") { FinderActions.copy([child.path]) }
                            }
                        }
                        if listing.node.directFileBytes > 0 {
                            ExplorerRow(name: "Files in this folder", size: listing.node.directFileBytes, fraction: fraction(listing.node.directFileBytes, of: listing), color: TreemapPalette.looseFiles, symbol: "doc.fill", isNavigable: false) {
                                FinderActions.reveal([listing.node.path])
                            }
                        }
                        if listing.remainingCount > 0 {
                            ExplorerRow(name: "\(CountFormat.string(listing.remainingCount)) smaller items", size: listing.remainingBytes, fraction: fraction(listing.remainingBytes, of: listing), color: TreemapPalette.aggregate, symbol: "ellipsis.circle.fill", isNavigable: false) {}
                        }
                    }
                    .padding(6)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }

    private func fraction(_ size: Int64, of listing: ExplorerListing) -> Double {
        Double(size) / Double(max(listing.node.size, 1))
    }
}

struct ExplorerRow: View {
    let name: String
    let size: Int64
    let fraction: Double
    let color: Color
    let symbol: String
    let isNavigable: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .foregroundStyle(color)
                        .frame(width: 16)
                    Text(name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(ByteFormat.string(size))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .opacity(isNavigable ? 1 : 0)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.06))
                        Capsule().fill(color.gradient).frame(width: max(2, proxy.size.width * min(fraction, 1)))
                    }
                }
                .frame(height: 3)
                .padding(.leading, 24)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(isHovering ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

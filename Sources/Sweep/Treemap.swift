import SweepCore
import SwiftUI

struct TreemapTile: Identifiable, Sendable {
    let id: Int
    let nodeID: Int32?
    let name: String
    let path: String
    let size: Int64
    let rect: CGRect
    let depth: Int
    let colorIndex: Int
    let shade: Double
    let parentIndex: Int?
    let hasChildren: Bool
    let kind: Kind
    var hasNestedTiles = false

    enum Kind: Sendable {
        case folder
        case looseFiles
        case aggregate
    }
}

struct TreemapLayoutResult: Sendable {
    let nodeID: Int32
    let canvasSize: CGSize
    let tiles: [TreemapTile]
    let totalSize: Int64
}

enum TreemapPalette {
    static let colors: [Color] = [
        Color(red: 0.25, green: 0.52, blue: 1.00),
        Color(red: 0.62, green: 0.38, blue: 0.98),
        Color(red: 0.98, green: 0.42, blue: 0.55),
        Color(red: 1.00, green: 0.60, blue: 0.20),
        Color(red: 0.16, green: 0.76, blue: 0.62),
        Color(red: 0.10, green: 0.68, blue: 0.92),
        Color(red: 0.92, green: 0.36, blue: 0.85),
        Color(red: 0.98, green: 0.78, blue: 0.20),
        Color(red: 0.40, green: 0.78, blue: 0.32),
        Color(red: 0.95, green: 0.48, blue: 0.32),
        Color(red: 0.42, green: 0.45, blue: 0.95),
        Color(red: 0.20, green: 0.80, blue: 0.82),
    ]

    static let looseFiles = Color(red: 0.56, green: 0.58, blue: 0.64)
    static let aggregate = Color(red: 0.44, green: 0.46, blue: 0.52)

    static func color(for tile: TreemapTile) -> Color {
        let base: Color = switch tile.kind {
        case .folder: colors[tile.colorIndex % colors.count]
        case .looseFiles: looseFiles
        case .aggregate: aggregate
        }
        guard tile.shade != 0 else { return base }
        return tile.shade > 0 ? base.mix(with: .white, by: tile.shade) : base.mix(with: .black, by: -tile.shade)
    }
}

enum SquarifiedLayout {
    static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: values.count)
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 1, rect.height > 1 else { return result }
        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { $0 * scale }
        var remaining = rect
        var start = 0
        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            guard side > 0 else { break }
            var end = start
            var rowSum = 0.0
            var best = Double.infinity
            while end < areas.count {
                let candidateSum = rowSum + areas[end]
                let ratio = worstRatio(areas[start...end], sum: candidateSum, side: side)
                if ratio > best { break }
                best = ratio
                rowSum = candidateSum
                end += 1
            }
            remaining = place(areas: areas, range: start..<end, rowSum: rowSum, in: remaining, into: &result)
            start = end
        }
        return result
    }

    private static func worstRatio(_ row: ArraySlice<Double>, sum: Double, side: Double) -> Double {
        guard let largest = row.max(), let smallest = row.min(), smallest > 0, sum > 0 else { return .infinity }
        let sideSquared = side * side
        let sumSquared = sum * sum
        return max(sideSquared * largest / sumSquared, sumSquared / (sideSquared * smallest))
    }

    private static func place(areas: [Double], range: Range<Int>, rowSum: Double, in remaining: CGRect, into result: inout [CGRect]) -> CGRect {
        let isWide = remaining.width >= remaining.height
        let side = Double(isWide ? remaining.height : remaining.width)
        let thickness = CGFloat(rowSum / side)
        var offset: CGFloat = 0
        for index in range {
            let length = CGFloat(areas[index] / Double(thickness))
            result[index] = isWide
                ? CGRect(x: remaining.minX, y: remaining.minY + offset, width: thickness, height: length)
                : CGRect(x: remaining.minX + offset, y: remaining.minY, width: length, height: thickness)
            offset += length
        }
        return isWide
            ? CGRect(x: remaining.minX + thickness, y: remaining.minY, width: max(remaining.width - thickness, 0), height: remaining.height)
            : CGRect(x: remaining.minX, y: remaining.minY + thickness, width: remaining.width, height: max(remaining.height - thickness, 0))
    }
}

struct TreemapEntry {
    let nodeID: Int32?
    let name: String
    let path: String
    let size: Int64
    let hasChildren: Bool
    let kind: TreemapTile.Kind
}

enum TreemapBuilder {
    static let gap: CGFloat = 2
    static let headerHeight: CGFloat = 20
    static let minimumTileArea: Double = 90
    static let maximumTopLevelTiles = 220
    static let maximumNestedTiles = 70

    static func build(tree: SpaceTree, nodeID: Int32, size: CGSize) -> TreemapLayoutResult {
        let bounds = CGRect(origin: .zero, size: size)
        let node = tree.node(nodeID)
        var tiles: [TreemapTile] = []
        let topEntries = entries(tree: tree, node: node, area: Double(size.width * size.height), limit: maximumTopLevelTiles)
        let topRects = SquarifiedLayout.layout(topEntries.map { Double($0.size) }, in: bounds)
        for (index, entry) in topEntries.enumerated() {
            let rect = topRects[index].insetBy(dx: gap / 2, dy: gap / 2)
            guard rect.width > 1, rect.height > 1 else { continue }
            let parentIndex = tiles.count
            tiles.append(tile(id: parentIndex, entry: entry, rect: rect, depth: 0, colorIndex: index, shade: 0, parentIndex: nil))
            guard entry.kind == .folder, let childID = entry.nodeID, entry.hasChildren, rect.width > 90, rect.height > 64 else { continue }
            let inner = CGRect(x: rect.minX + 3, y: rect.minY + headerHeight, width: rect.width - 6, height: rect.height - headerHeight - 3)
            let nested = nestedTiles(tree: tree, nodeID: childID, in: inner, colorIndex: index, parentIndex: parentIndex, firstID: tiles.count)
            if !nested.isEmpty {
                tiles[parentIndex].hasNestedTiles = true
                tiles.append(contentsOf: nested)
            }
        }
        return TreemapLayoutResult(nodeID: nodeID, canvasSize: size, tiles: tiles, totalSize: node.size)
    }

    private static func nestedTiles(tree: SpaceTree, nodeID: Int32, in rect: CGRect, colorIndex: Int, parentIndex: Int, firstID: Int) -> [TreemapTile] {
        let node = tree.node(nodeID)
        let nestedEntries = entries(tree: tree, node: node, area: Double(rect.width * rect.height), limit: maximumNestedTiles)
        let rects = SquarifiedLayout.layout(nestedEntries.map { Double($0.size) }, in: rect)
        var result: [TreemapTile] = []
        for (index, entry) in nestedEntries.enumerated() {
            let inset = rects[index].insetBy(dx: 0.75, dy: 0.75)
            guard inset.width > 1, inset.height > 1 else { continue }
            let shade = (index % 2 == 0 ? 0.08 : 0.24) + Double(index % 5) * 0.03
            result.append(tile(id: firstID + result.count, entry: entry, rect: inset, depth: 1, colorIndex: colorIndex, shade: shade, parentIndex: parentIndex))
        }
        return result
    }

    private static func tile(id: Int, entry: TreemapEntry, rect: CGRect, depth: Int, colorIndex: Int, shade: Double, parentIndex: Int?) -> TreemapTile {
        TreemapTile(
            id: id,
            nodeID: entry.nodeID,
            name: entry.name,
            path: entry.path,
            size: entry.size,
            rect: rect,
            depth: depth,
            colorIndex: colorIndex,
            shade: shade,
            parentIndex: parentIndex,
            hasChildren: entry.hasChildren,
            kind: entry.kind
        )
    }

    static func entries(tree: SpaceTree, node: SpaceNode, area: Double, limit: Int) -> [TreemapEntry] {
        guard node.size > 0 else { return [] }
        var all = tree.children(of: node.id).filter { $0.size > 0 }.map {
            TreemapEntry(nodeID: $0.id, name: $0.name, path: $0.path, size: $0.size, hasChildren: $0.hasChildren, kind: .folder)
        }
        if node.directFileBytes > 0 {
            all.append(TreemapEntry(nodeID: nil, name: "Files in this folder", path: node.path, size: node.directFileBytes, hasChildren: false, kind: .looseFiles))
            all.sort { $0.size > $1.size }
        }
        let bytesPerPoint = Double(node.size) / max(area, 1)
        let threshold = Int64(bytesPerPoint * minimumTileArea)
        var kept: [TreemapEntry] = []
        var droppedBytes: Int64 = 0
        var droppedCount = 0
        for entry in all {
            if kept.count < limit && entry.size >= threshold {
                kept.append(entry)
            } else {
                droppedBytes += entry.size
                droppedCount += 1
            }
        }
        if droppedCount > 0 && Double(droppedBytes) >= Double(threshold) {
            kept.append(TreemapEntry(nodeID: nil, name: "\(droppedCount) smaller items", path: node.path, size: droppedBytes, hasChildren: false, kind: .aggregate))
        }
        return kept
    }
}

struct TreemapView: View {
    let layout: TreemapLayoutResult
    let highlightedNodeID: Int32?
    let onOpen: (Int32) -> Void
    @State private var hoveredIndex: Int?
    @State private var hoverLocation: CGPoint = .zero

    var body: some View {
        GeometryReader { proxy in
            let scale = CGSize(
                width: proxy.size.width / max(layout.canvasSize.width, 1),
                height: proxy.size.height / max(layout.canvasSize.height, 1)
            )
            Canvas { context, _ in
                context.scaleBy(x: scale.width, y: scale.height)
                draw(in: &context)
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    hoverLocation = location
                    hoveredIndex = tileIndex(at: CGPoint(x: location.x / scale.width, y: location.y / scale.height))
                case .ended:
                    hoveredIndex = nil
                }
            }
            .onTapGesture { location in
                guard let index = tileIndex(at: CGPoint(x: location.x / scale.width, y: location.y / scale.height)), let target = drillTarget(for: index) else { return }
                onOpen(target)
            }
            .contextMenu { contextMenu }
            .overlay(alignment: .topLeading) {
                if let hoveredIndex, layout.tiles.indices.contains(hoveredIndex) {
                    TreemapTooltip(tile: layout.tiles[hoveredIndex], total: layout.totalSize)
                        .fixedSize()
                        .alignmentGuide(.leading) { dimensions in
                            -min(hoverLocation.x + 14, proxy.size.width - dimensions.width - 4)
                        }
                        .alignmentGuide(.top) { dimensions in
                            let below = hoverLocation.y + 18
                            return -(below + dimensions.height > proxy.size.height ? hoverLocation.y - dimensions.height - 10 : below)
                        }
                        .allowsHitTesting(false)
                }
            }
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if let hoveredIndex, layout.tiles.indices.contains(hoveredIndex) {
            let tile = layout.tiles[hoveredIndex]
            if let target = drillTarget(for: hoveredIndex) {
                Button("Open") { onOpen(target) }
            }
            Button("Reveal in Finder") { FinderActions.reveal([tile.path]) }
            Button("Copy Path") { FinderActions.copy([tile.path]) }
        }
    }

    private func drillTarget(for index: Int) -> Int32? {
        let tile = layout.tiles[index]
        if tile.depth == 0 {
            return tile.hasChildren ? tile.nodeID : nil
        }
        guard let parentIndex = tile.parentIndex else { return nil }
        return layout.tiles[parentIndex].nodeID
    }

    private func tileIndex(at point: CGPoint) -> Int? {
        layout.tiles.lastIndex { $0.rect.contains(point) }
    }

    private func draw(in context: inout GraphicsContext) {
        let hoveredParent = hoveredIndex.flatMap { layout.tiles[$0].parentIndex } ?? hoveredIndex
        for tile in layout.tiles {
            drawTile(tile, emphasized: tile.id == hoveredParent, in: &context)
        }
        if let hoveredIndex, layout.tiles.indices.contains(hoveredIndex) {
            let tile = layout.tiles[hoveredIndex]
            context.stroke(roundedPath(for: tile), with: .color(.white), lineWidth: 2)
        }
        if let highlightedNodeID, let tile = layout.tiles.first(where: { $0.depth == 0 && $0.nodeID == highlightedNodeID }) {
            context.stroke(roundedPath(for: tile), with: .color(.white), lineWidth: 3)
        }
    }

    private func roundedPath(for tile: TreemapTile) -> Path {
        let radius = min(tile.depth == 0 ? 7 : 4, min(tile.rect.width, tile.rect.height) / 3)
        return Path(roundedRect: tile.rect, cornerRadius: radius, style: .continuous)
    }

    private func drawTile(_ tile: TreemapTile, emphasized: Bool, in context: inout GraphicsContext) {
        let color = TreemapPalette.color(for: tile)
        let path = roundedPath(for: tile)
        if tile.depth == 0 {
            let top = tile.hasNestedTiles ? color.mix(with: .black, by: 0.18) : color.mix(with: .white, by: 0.12)
            let bottom = tile.hasNestedTiles ? color.mix(with: .black, by: 0.32) : color.mix(with: .black, by: 0.08)
            context.fill(path, with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: CGPoint(x: tile.rect.midX, y: tile.rect.minY), endPoint: CGPoint(x: tile.rect.midX, y: tile.rect.maxY)))
            if emphasized {
                context.fill(path, with: .color(.white.opacity(0.10)))
            }
            drawTopLevelLabel(for: tile, in: &context)
        } else {
            context.fill(path, with: .color(emphasized ? color.mix(with: .white, by: 0.12) : color))
            drawNestedLabel(for: tile, in: &context)
        }
    }

    private func drawTopLevelLabel(for tile: TreemapTile, in context: inout GraphicsContext) {
        guard tile.rect.width > 54, tile.rect.height > 20 else { return }
        let width = tile.rect.width - 12
        let name = context.resolve(Text(tile.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white))
        let size = context.resolve(Text(ByteFormat.string(tile.size)).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.8)))
        if tile.hasNestedTiles {
            let sizeWidth = size.measure(in: CGSize(width: width, height: 14)).width
            let showsSize = sizeWidth + 40 < width
            context.draw(name, in: CGRect(x: tile.rect.minX + 6, y: tile.rect.minY + 3, width: showsSize ? width - sizeWidth - 6 : width, height: 14))
            if showsSize {
                context.draw(size, in: CGRect(x: tile.rect.maxX - 6 - sizeWidth, y: tile.rect.minY + 4, width: sizeWidth, height: 14))
            }
        } else {
            context.draw(name, in: CGRect(x: tile.rect.minX + 6, y: tile.rect.minY + 5, width: width, height: 14))
            if tile.rect.height > 36 {
                context.draw(size, in: CGRect(x: tile.rect.minX + 6, y: tile.rect.minY + 20, width: width, height: 14))
            }
        }
    }

    private func drawNestedLabel(for tile: TreemapTile, in context: inout GraphicsContext) {
        guard tile.rect.width > 56, tile.rect.height > 26 else { return }
        let width = tile.rect.width - 8
        let name = context.resolve(Text(tile.name).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.95)))
        context.draw(name, in: CGRect(x: tile.rect.minX + 4, y: tile.rect.minY + 3, width: width, height: 13))
        if tile.rect.height > 40 {
            let size = context.resolve(Text(ByteFormat.string(tile.size)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.75)))
            context.draw(size, in: CGRect(x: tile.rect.minX + 4, y: tile.rect.minY + 16, width: width, height: 12))
        }
    }
}

struct TreemapTooltip: View {
    let tile: TreemapTile
    let total: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(TreemapPalette.color(for: tile)).frame(width: 8, height: 8)
                Text(tile.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(ByteFormat.string(tile.size))
                    .monospacedDigit()
                Text("·")
                Text(percentText)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if tile.kind == .folder {
                Text(PathDisplay.abbreviated(tile.path))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 280, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.97), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }

    private var percentText: String {
        let fraction = Double(tile.size) / Double(max(total, 1))
        return fraction.formatted(.percent.precision(.fractionLength(fraction < 0.01 ? 2 : 1)))
    }
}

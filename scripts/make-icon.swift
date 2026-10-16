#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
let tileSide: CGFloat = 824
let tileCornerRadius: CGFloat = tileSide * 0.2237
let tileRect = CGRect(
    x: (canvas - tileSide) / 2,
    y: (canvas - tileSide) / 2,
    width: tileSide,
    height: tileSide
)
let iconCenter = CGPoint(x: canvas / 2, y: canvas / 2)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    let red = CGFloat((hex >> 16) & 0xFF) / 255
    let green = CGFloat((hex >> 8) & 0xFF) / 255
    let blue = CGFloat(hex & 0xFF) / 255
    return CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func white(_ alpha: CGFloat) -> CGColor {
    CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha)
}

func black(_ alpha: CGFloat) -> CGColor {
    CGColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha)
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
}

func degrees(_ value: CGFloat) -> CGFloat {
    value * .pi / 180
}

func pointOnCircle(radius: CGFloat, angle: CGFloat) -> CGPoint {
    CGPoint(
        x: iconCenter.x + radius * cos(degrees(angle)),
        y: iconCenter.y + radius * sin(degrees(angle))
    )
}

struct GlyphMetrics {
    let ringRadius: CGFloat
    let ringWidth: CGFloat
    let trackAlpha: CGFloat
    let centerSparkleRadius: CGFloat
    let centerSparklePinch: CGFloat
    let showsSatelliteSparkles: Bool
    let showsGlyphShadow: Bool

    static func forPixelSize(_ pixels: Int) -> GlyphMetrics {
        switch pixels {
        case ...16:
            return GlyphMetrics(ringRadius: 256, ringWidth: 124, trackAlpha: 0.3, centerSparkleRadius: 132, centerSparklePinch: 0.36, showsSatelliteSparkles: false, showsGlyphShadow: false)
        case ...32:
            return GlyphMetrics(ringRadius: 246, ringWidth: 104, trackAlpha: 0.26, centerSparkleRadius: 166, centerSparklePinch: 0.24, showsSatelliteSparkles: false, showsGlyphShadow: false)
        case ...64:
            return GlyphMetrics(ringRadius: 252, ringWidth: 80, trackAlpha: 0.2, centerSparkleRadius: 162, centerSparklePinch: 0.18, showsSatelliteSparkles: true, showsGlyphShadow: true)
        default:
            return GlyphMetrics(ringRadius: 256, ringWidth: 68, trackAlpha: 0.16, centerSparkleRadius: 162, centerSparklePinch: 0.16, showsSatelliteSparkles: true, showsGlyphShadow: true)
        }
    }
}

func tilePath() -> CGPath {
    CGPath(roundedRect: tileRect, cornerWidth: tileCornerRadius, cornerHeight: tileCornerRadius, transform: nil)
}

func drawTileShadow(in context: CGContext) {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: black(0.32))
    context.addPath(tilePath())
    context.setFillColor(color(0x4F46E5))
    context.fillPath()
    context.restoreGState()
}

func drawTileBackground(in context: CGContext) {
    context.saveGState()
    context.addPath(tilePath())
    context.clip()

    let baseGradient = gradient([color(0x4F46E5), color(0x6D3FEA), color(0x7C3AED)], [0, 0.55, 1])
    context.drawLinearGradient(
        baseGradient,
        start: CGPoint(x: tileRect.minX, y: tileRect.maxY),
        end: CGPoint(x: tileRect.maxX, y: tileRect.minY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    let pinkGlow = gradient([color(0xDB2777, alpha: 0.85), color(0xDB2777, alpha: 0.35), color(0xDB2777, alpha: 0)], [0, 0.45, 1])
    let pinkCenter = CGPoint(x: tileRect.maxX - 40, y: tileRect.minY + 40)
    context.drawRadialGradient(pinkGlow, startCenter: pinkCenter, startRadius: 0, endCenter: pinkCenter, endRadius: tileSide * 0.78, options: [])

    let indigoDepth = gradient([color(0x312E81, alpha: 0.45), color(0x312E81, alpha: 0)], [0, 1])
    let indigoCenter = CGPoint(x: tileRect.minX + 60, y: tileRect.minY + 80)
    context.drawRadialGradient(indigoDepth, startCenter: indigoCenter, startRadius: 0, endCenter: indigoCenter, endRadius: tileSide * 0.55, options: [])

    let topSheen = gradient([white(0.22), white(0.06), white(0)], [0, 0.35, 0.6])
    context.drawLinearGradient(
        topSheen,
        start: CGPoint(x: iconCenter.x, y: tileRect.maxY),
        end: CGPoint(x: iconCenter.x, y: tileRect.minY),
        options: []
    )
    context.restoreGState()
}

func drawTileEdgeHighlight(in context: CGContext) {
    context.saveGState()
    context.addPath(tilePath())
    context.clip()
    context.addPath(tilePath())
    context.setLineWidth(6)
    context.replacePathWithStrokedPath()
    context.clip()
    let edgeLight = gradient([white(0.5), white(0.08), white(0), black(0.18)], [0, 0.3, 0.7, 1])
    context.drawLinearGradient(
        edgeLight,
        start: CGPoint(x: iconCenter.x, y: tileRect.maxY),
        end: CGPoint(x: iconCenter.x, y: tileRect.minY),
        options: []
    )
    context.restoreGState()
}

func sparklePath(center: CGPoint, radius: CGFloat, pinch: CGFloat = 0.16) -> CGPath {
    let path = CGMutablePath()
    let waist = radius * pinch
    let tips = [
        CGPoint(x: center.x, y: center.y + radius),
        CGPoint(x: center.x + radius, y: center.y),
        CGPoint(x: center.x, y: center.y - radius),
        CGPoint(x: center.x - radius, y: center.y),
    ]
    let waists = [
        CGPoint(x: center.x + waist, y: center.y + waist),
        CGPoint(x: center.x + waist, y: center.y - waist),
        CGPoint(x: center.x - waist, y: center.y - waist),
        CGPoint(x: center.x - waist, y: center.y + waist),
    ]
    path.move(to: tips[0])
    for index in 0..<4 {
        path.addQuadCurve(to: tips[(index + 1) % 4], control: waists[index])
    }
    path.closeSubpath()
    return path
}

let sweepHeadAngle: CGFloat = 62
let sweepLength: CGFloat = 290

func ringArcPath(metrics: GlyphMetrics, from startAngle: CGFloat, to endAngle: CGFloat) -> CGPath {
    let arc = CGMutablePath()
    arc.addArc(
        center: iconCenter,
        radius: metrics.ringRadius,
        startAngle: degrees(startAngle),
        endAngle: degrees(endAngle),
        clockwise: true
    )
    return arc.copy(strokingWithWidth: metrics.ringWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

func drawRingTrack(in context: CGContext, metrics: GlyphMetrics) {
    let track = CGMutablePath()
    track.addEllipse(in: CGRect(
        x: iconCenter.x - metrics.ringRadius,
        y: iconCenter.y - metrics.ringRadius,
        width: metrics.ringRadius * 2,
        height: metrics.ringRadius * 2
    ))
    context.addPath(track.copy(strokingWithWidth: metrics.ringWidth, lineCap: .butt, lineJoin: .round, miterLimit: 10))
    context.setFillColor(white(metrics.trackAlpha))
    context.fillPath()
}

func cometOpacity(clockwiseDegreesFromHead distance: CGFloat) -> CGFloat {
    let progress = distance / sweepLength
    let isNearHeadInGap = distance > (sweepLength + 360) / 2
    if progress <= 0.05 || isNearHeadInGap { return 1 }
    if progress >= 1 { return 0 }
    let fade = min(1, (progress - 0.05) / 0.85)
    return max(0, 1 - pow(fade, 1.15))
}

func cometFadeMask(pixels: Int) -> CGImage {
    let scale = CGFloat(pixels) / canvas
    var bytes = [UInt8](repeating: 0, count: pixels * pixels)
    for row in 0..<pixels {
        let userY = (CGFloat(pixels - row) - 0.5) / scale
        for column in 0..<pixels {
            let userX = (CGFloat(column) + 0.5) / scale
            let angle = atan2(userY - iconCenter.y, userX - iconCenter.x) * 180 / .pi
            var distance = (sweepHeadAngle - angle).truncatingRemainder(dividingBy: 360)
            if distance < 0 { distance += 360 }
            bytes[row * pixels + column] = UInt8((cometOpacity(clockwiseDegreesFromHead: distance) * 255).rounded())
        }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        bytesPerRow: pixels,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
    )!
}

func drawSweepArc(in context: CGContext, metrics: GlyphMetrics) {
    let tailAngle = sweepHeadAngle - sweepLength
    context.saveGState()
    context.clip(to: CGRect(x: 0, y: 0, width: canvas, height: canvas), mask: cometFadeMask(pixels: context.width))
    context.addPath(ringArcPath(metrics: metrics, from: sweepHeadAngle, to: tailAngle))
    context.setFillColor(white(1))
    context.fillPath()
    context.restoreGState()

    let headCap = CGRect(
        x: pointOnCircle(radius: metrics.ringRadius, angle: sweepHeadAngle).x - metrics.ringWidth / 2,
        y: pointOnCircle(radius: metrics.ringRadius, angle: sweepHeadAngle).y - metrics.ringWidth / 2,
        width: metrics.ringWidth,
        height: metrics.ringWidth
    )
    context.setFillColor(white(1))
    context.fillEllipse(in: headCap)
}

func drawSparkles(in context: CGContext, metrics: GlyphMetrics) {
    context.setFillColor(white(1))
    context.addPath(sparklePath(center: iconCenter, radius: metrics.centerSparkleRadius, pinch: metrics.centerSparklePinch))
    context.fillPath()

    guard metrics.showsSatelliteSparkles else { return }
    context.addPath(sparklePath(center: pointOnCircle(radius: 368, angle: 44), radius: 54, pinch: 0.2))
    context.fillPath()
    context.setFillColor(white(0.85))
    context.addPath(sparklePath(center: pointOnCircle(radius: 378, angle: 19), radius: 28, pinch: 0.22))
    context.fillPath()
}

func drawGlyph(in context: CGContext, metrics: GlyphMetrics) {
    context.saveGState()
    if metrics.showsGlyphShadow {
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x1E1B4B, alpha: 0.38))
    }
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    drawRingTrack(in: context, metrics: metrics)
    drawSweepArc(in: context, metrics: metrics)
    drawSparkles(in: context, metrics: metrics)
    context.endTransparencyLayer()
    context.restoreGState()
}

func renderIcon(pixels: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    let scale = CGFloat(pixels) / canvas
    context.scaleBy(x: scale, y: scale)

    drawTileShadow(in: context)
    drawTileBackground(in: context)
    drawTileEdgeHighlight(in: context)
    drawGlyph(in: context, metrics: .forPixelSize(pixels))
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write(Data("Failed to write \(url.path)\n".utf8))
        exit(1)
    }
}

struct IconsetEntry {
    let points: Int
    let scale: Int

    var pixels: Int { points * scale }
    var fileName: String {
        scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@\(scale)x.png"
    }
}

let iconsetEntries = [16, 32, 128, 256, 512].flatMap { points in
    [IconsetEntry(points: points, scale: 1), IconsetEntry(points: points, scale: 2)]
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift make-icon.swift <output.iconset>\n".utf8))
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

var renderedBySize: [Int: CGImage] = [:]
for entry in iconsetEntries {
    let image = renderedBySize[entry.pixels] ?? renderIcon(pixels: entry.pixels)
    renderedBySize[entry.pixels] = image
    writePNG(image, to: outputDirectory.appendingPathComponent(entry.fileName))
}
print("Wrote \(iconsetEntries.count) images to \(outputDirectory.path)")

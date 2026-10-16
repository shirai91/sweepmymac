import SweepCore
import SwiftUI

struct ScanningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 0)
            RadarView()
                .frame(width: 250, height: 250)
            ScanHeadline(progress: model.progress, scope: model.scope)
            ScanCounters(progress: model.progress, startedAt: model.scanStartedAt)
                .frame(maxWidth: 640)
            CurrentPathPill(path: model.progress.currentPath)
                .frame(maxWidth: 560)
            Button(action: model.cancelScan) {
                Text("Cancel")
                    .frame(minWidth: 90)
            }
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)
            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScanHeadline: View {
    let progress: ScanProgress
    let scope: ScopeChoice

    var body: some View {
        VStack(spacing: 6) {
            Text(progress.phase.rawValue + "…")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.smooth, value: progress.phase.rawValue)
            Text(ByteFormat.string(progress.bytesScanned))
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(progress.bytesScanned)))
                .animation(.linear(duration: 0.08), value: progress.bytesScanned)
            Text("scanned on \(scope.title)")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }
}

struct ScanCounters: View {
    let progress: ScanProgress
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 0.5)) { context in
            let elapsed = max(progress.elapsed, context.date.timeIntervalSince(startedAt))
            HStack(spacing: 12) {
                CounterTile(title: "Files", value: CountFormat.string(progress.filesScanned), numeric: Double(progress.filesScanned), symbol: "doc.fill")
                CounterTile(title: "Folders", value: CountFormat.string(progress.directoriesScanned), numeric: Double(progress.directoriesScanned), symbol: "folder.fill")
                CounterTile(title: "Files / sec", value: CountFormat.string(filesPerSecond(elapsed: elapsed)), numeric: Double(filesPerSecond(elapsed: elapsed)), symbol: "speedometer")
                CounterTile(title: "Elapsed", value: DurationFormat.clock(elapsed), numeric: elapsed.rounded(.down), symbol: "clock.fill")
            }
        }
    }

    private func filesPerSecond(elapsed: TimeInterval) -> Int {
        guard elapsed > 0.2 else { return 0 }
        return Int(Double(progress.filesScanned) / elapsed)
    }
}

struct CounterTile: View {
    let title: String
    let value: String
    let numeric: Double
    let symbol: String

    var body: some View {
        VStack(spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: numeric))
                .animation(.linear(duration: 0.08), value: numeric)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .card(radius: 14, padding: 14)
    }
}

struct CurrentPathPill: View {
    let path: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
                .symbolEffect(.rotate, options: .repeating)
            Text(path.isEmpty ? "Preparing…" : path)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
    }
}

struct RadarView: View {
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let sweepAngle = Angle.degrees((time * 120).truncatingRemainder(dividingBy: 360))
            let ringAngle = Angle.degrees((time * -45).truncatingRemainder(dividingBy: 360))
            let pulse = (sin(time * 2.4) + 1) / 2
            ZStack {
                RadarGrid()
                RadarSweep()
                    .rotationEffect(sweepAngle)
                Circle()
                    .strokeBorder(
                        AngularGradient(colors: [Theme.accentStart, Theme.accentEnd, Color(red: 0.98, green: 0.40, blue: 0.60), Theme.accentStart.opacity(0.1), Theme.accentStart], center: .center),
                        lineWidth: 6
                    )
                    .rotationEffect(ringAngle)
                    .shadow(color: Theme.accentEnd.opacity(0.4), radius: 10)
                RadarBlips(time: time)
                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: 64, height: 64)
                    .scaleEffect(1 + pulse * 0.06)
                    .shadow(color: Theme.accentStart.opacity(0.5), radius: 12 + pulse * 8)
                    .overlay {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
    }
}

struct RadarGrid: View {
    var body: some View {
        ZStack {
            ForEach([0.36, 0.62, 0.86], id: \.self) { scale in
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    .scaleEffect(scale)
            }
            Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1)
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
        }
        .padding(6)
    }
}

struct RadarSweep: View {
    var body: some View {
        Circle()
            .fill(
                AngularGradient(
                    stops: [
                        .init(color: Theme.accentStart.opacity(0.0), location: 0.0),
                        .init(color: Theme.accentStart.opacity(0.0), location: 0.70),
                        .init(color: Theme.accentEnd.opacity(0.22), location: 0.94),
                        .init(color: Theme.accentEnd.opacity(0.55), location: 1.0),
                    ],
                    center: .center
                )
            )
            .padding(6)
    }
}

struct RadarBlips: View {
    let time: TimeInterval

    private static let blips: [(angle: Double, radius: Double, phase: Double)] = [
        (0.4, 0.55, 0.0), (1.9, 0.78, 0.7), (2.8, 0.38, 1.3), (3.9, 0.68, 2.1), (5.1, 0.48, 2.9), (5.8, 0.82, 0.4),
    ]

    var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2 - 10
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ForEach(Self.blips.indices, id: \.self) { index in
                let blip = Self.blips[index]
                let glow = max(0, sin(time * 1.6 + blip.phase))
                Circle()
                    .fill(JunkCategory.allCases[index % JunkCategory.allCases.count].tint)
                    .frame(width: 7, height: 7)
                    .opacity(glow)
                    .scaleEffect(0.6 + glow * 0.6)
                    .shadow(color: JunkCategory.allCases[index].tint, radius: 4)
                    .position(x: center.x + cos(blip.angle) * radius * blip.radius, y: center.y + sin(blip.angle) * radius * blip.radius)
            }
        }
    }
}

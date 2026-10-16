import AppKit
import SweepCore
import SwiftUI

struct DoneView: View {
    @Environment(AppModel.self) private var model
    @State private var trashState: TrashState = .idle
    @State private var isConfirmingEmptyTrash = false

    var body: some View {
        if let outcome = model.outcome {
            ScrollView {
                VStack(spacing: 22) {
                    ZStack {
                        ParticleBurst()
                            .frame(width: 420, height: 320)
                        AnimatedCheckmark()
                            .frame(width: 130, height: 130)
                    }
                    .frame(height: 260)
                    VStack(spacing: 6) {
                        Text("You freed \(ByteFormat.string(outcome.bytesFreed))")
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.celebrationGradient)
                        Text(subtitle(for: outcome))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    if outcome.movedToTrash && !outcome.trashedPaths.isEmpty {
                        TrashHint(state: trashState) { isConfirmingEmptyTrash = true }
                            .frame(maxWidth: 560)
                    }
                    if !outcome.failures.isEmpty {
                        FailureList(failures: outcome.failures)
                            .frame(maxWidth: 560)
                    }
                    HStack(spacing: 12) {
                        Button("Back to Results", action: model.backToResults)
                            .controlSize(.large)
                            .keyboardShortcut(.cancelAction)
                        Button(action: model.startScan) {
                            Label("Scan Again", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accentStart)
                        .controlSize(.large)
                    }
                    .padding(.top, 4)
                }
                .padding(40)
                .frame(maxWidth: .infinity)
            }
            .confirmationDialog("Delete these items from the Trash?", isPresented: $isConfirmingEmptyTrash) {
                Button("Delete from Trash", role: .destructive) { emptyTrash(outcome.trashedPaths) }
            } message: {
                Text("Sweep deletes only the \(CountFormat.items(outcome.trashedPaths.count)) it moved to the Trash. Other items in your Trash stay. This cannot be undone.")
            }
        } else {
            ContentUnavailableView("Nothing was cleaned", systemImage: "tray")
        }
    }

    private func subtitle(for outcome: CleanOutcome) -> String {
        let cleaned = CountFormat.items(outcome.cleanedItemIDs.count)
        guard !outcome.failures.isEmpty else { return "\(cleaned) cleaned. Your Mac thanks you." }
        return "\(cleaned) cleaned, \(outcome.failures.count) could not be removed."
    }

    private func emptyTrash(_ paths: [String]) {
        trashState = .emptying
        Task {
            let result = await model.deleteTrashedItems(paths)
            trashState = result.succeeded ? .emptied : .failed(result.firstError ?? "Some items could not be deleted.")
        }
    }
}

enum TrashState: Equatable {
    case idle
    case emptying
    case emptied
    case failed(String)
}

struct TrashHint: View {
    let state: TrashState
    let emptyTrash: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state == .emptied ? "checkmark.circle.fill" : "trash.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(state == .emptied ? AnyShapeStyle(.green) : AnyShapeStyle(Theme.accentGradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if state != .emptied {
                Button(action: emptyTrash) {
                    HStack(spacing: 6) {
                        if state == .emptying { ProgressView().controlSize(.small) }
                        Text("Delete from Trash")
                    }
                }
                .controlSize(.large)
                .disabled(state == .emptying)
            }
        }
        .card(padding: 16)
    }

    private var title: String {
        switch state {
        case .emptied: "Deleted from the Trash"
        case .failed: "Some items are still in the Trash"
        default: "Items are in the Trash"
        }
    }

    private var message: String {
        switch state {
        case .emptied: "Sweep frees the space in the background. Your other Trash items are untouched."
        case .failed(let reason): reason
        default: "Delete them to free the space. Until then you can put anything back."
        }
    }
}

struct FailureList: View {
    let failures: [CleanFailureEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(failures.count) couldn't be removed", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(failures) { failure in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(failure.title).fontWeight(.medium)
                            Text(failure.reason)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 180)
            .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 16)
    }
}

struct AnimatedCheckmark: View {
    @State private var drawn = false
    @State private var popped = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.celebrationGradient)
                .shadow(color: Color.green.opacity(0.45), radius: 24, y: 8)
                .scaleEffect(popped ? 1 : 0.4)
                .opacity(popped ? 1 : 0)
            CheckmarkShape()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                .padding(36)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.45)) { popped = true }
            withAnimation(.easeOut(duration: 0.45).delay(0.3)) { drawn = true }
        }
    }
}

struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.04))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY - rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.14))
        return path
    }
}

struct ParticleBurst: View {
    @State private var start = Date()
    @State private var finished = false

    private struct Particle {
        let angle: Double
        let speed: Double
        let size: Double
        let spin: Double
        let color: Color
        let isRect: Bool
    }

    private static let particles: [Particle] = {
        var generator = SeededGenerator(seed: 7)
        let palette = JunkCategory.allCases.map(\.tint)
        return (0..<90).map { index in
            Particle(
                angle: Double.random(in: 0..<(2 * .pi), using: &generator),
                speed: Double.random(in: 120...300, using: &generator),
                size: Double.random(in: 4...9, using: &generator),
                spin: Double.random(in: -6...6, using: &generator),
                color: palette[index % palette.count],
                isRect: index % 3 == 0
            )
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: finished)) { context in
            let t = context.date.timeIntervalSince(start)
            Canvas { graphics, size in
                guard t < 2.6 else { return }
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for particle in Self.particles {
                    let eased = 1 - pow(1 - min(t / 1.4, 1), 3)
                    let distance = particle.speed * eased
                    let gravity = 60 * t * t
                    let x = center.x + cos(particle.angle) * distance
                    let y = center.y + sin(particle.angle) * distance * 0.8 + gravity
                    let alpha = max(0, 1 - t / 2.6)
                    var local = graphics
                    local.opacity = alpha
                    local.translateBy(x: x, y: y)
                    local.rotate(by: .radians(particle.spin * t))
                    let rect = CGRect(x: -particle.size / 2, y: -particle.size / 2, width: particle.size, height: particle.isRect ? particle.size * 0.5 : particle.size)
                    let shape = particle.isRect ? Path(roundedRect: rect, cornerRadius: 1) : Path(ellipseIn: rect)
                    local.fill(shape, with: .color(particle.color))
                }
            }
        }
        .allowsHitTesting(false)
        .task {
            start = Date()
            try? await Task.sleep(for: .seconds(2.7))
            finished = true
        }
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

import SweepCore
import SwiftUI

struct CleaningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let progress = model.cleanProgress
        VStack(spacing: 26) {
            Spacer(minLength: 0)
            CleaningRing(fraction: progress.fraction)
                .frame(width: 220, height: 220)
            VStack(spacing: 6) {
                Text("Cleaning…")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(ByteFormat.string(progress.bytesFreed))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(progress.bytesFreed)))
                    .animation(.snappy(duration: 0.3), value: progress.bytesFreed)
                Text("freed of \(ByteFormat.string(progress.targetBytes))")
                    .foregroundStyle(.tertiary)
            }
            VStack(spacing: 10) {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                    .tint(Theme.accentStart)
                    .frame(width: 360)
                    .animation(.smooth, value: progress.fraction)
                HStack(spacing: 6) {
                    Text("\(CountFormat.string(min(progress.completed + 1, progress.total))) of \(CountFormat.string(progress.total))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(progress.currentTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.callout)
                .frame(maxWidth: 460)
            }
            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CleaningRing: View {
    let fraction: Double

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .stroke(Theme.freeColor, lineWidth: 18)
                Circle()
                    .trim(from: 0, to: 0.18)
                    .stroke(Theme.accentStart.opacity(0.25), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees((time * 160).truncatingRemainder(dividingBy: 360)))
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        AngularGradient(colors: [Theme.accentStart, Theme.accentEnd, Color(red: 0.98, green: 0.40, blue: 0.60), Theme.accentStart], center: .center),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Theme.accentEnd.opacity(0.4), radius: 10)
                    .opacity(fraction > 0 ? 1 : 0)
                    .animation(.smooth(duration: 0.4), value: fraction)
                Image(systemName: "wind")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(Theme.accentGradient)
                    .offset(x: sin(time * 3) * 4)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }
            .padding(9)
        }
    }
}

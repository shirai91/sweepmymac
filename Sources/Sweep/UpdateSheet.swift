import AppKit
import SweepCore
import SwiftUI

struct UpdateSheet: View {
    @Environment(UpdateController.self) private var updater
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let update = updater.available {
                UpdateHeader(
                    title: "Sweep \(update.version) is available",
                    subtitle: "You have version \(updater.currentVersion)."
                )
                ReleaseNotesBox(notes: updater.releaseNotes)
                UpdateStatusLine(status: updater.status, canInstallInPlace: updater.canInstallInPlace)
                availableButtons
            } else {
                UpdateHeader(title: noUpdateTitle, subtitle: noUpdateSubtitle)
                HStack {
                    Spacer()
                    Button("OK", action: updater.remindLater)
                        .keyboardShortcut(.defaultAction)
                        .controlSize(.large)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private var noUpdateTitle: String {
        if case .failed = updater.status { return "Sweep could not check for updates" }
        return "Sweep is up to date"
    }

    private var noUpdateSubtitle: String {
        if case .failed(let reason) = updater.status { return reason }
        return "Version \(updater.currentVersion) is the newest version."
    }

    private var availableButtons: some View {
        HStack {
            Button("Skip This Version", action: updater.skipThisVersion)
                .controlSize(.large)
            Spacer()
            Button("Later", action: updater.remindLater)
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
            primaryButton
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch updater.status {
        case .ready, .installing:
            Button("Install and Relaunch", action: updater.installAndRelaunch)
                .disabled(model.phase == .cleaning || updater.status == .installing)
                .help(model.phase == .cleaning ? "Wait until cleaning is done." : "")
        case .downloading:
            Button("Downloading…") {}
                .disabled(true)
        case .failed where updater.canInstallInPlace:
            Button("Try Again") { updater.downloadUpdate() }
        default:
            if updater.canInstallInPlace {
                Button("Download and Install") { updater.downloadUpdate() }
            } else {
                Button("Open Download Page", action: updater.openReleasePage)
            }
        }
    }
}

private struct UpdateHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ReleaseNotesBox: View {
    let notes: AttributedString?

    var body: some View {
        ScrollView {
            Text(notes ?? AttributedString("No release notes."))
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(height: 200)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct UpdateStatusLine: View {
    let status: UpdateController.Status
    let canInstallInPlace: Bool

    var body: some View {
        switch status {
        case .downloading(let fraction):
            ProgressView(value: fraction) {
                BusyLabel(text: "Downloading… \(fraction.formatted(.percent.precision(.fractionLength(0))))")
            }
            .animation(.smooth(duration: 0.3), value: fraction)
        case .ready:
            Label("Downloaded and ready to install.", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .installing:
            BusyLabel(text: "Installing. Sweep will open again in a moment.")
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        default:
            if !canInstallInPlace {
                Label("Sweep cannot replace itself in this folder. Get the new version from GitHub.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct BusyLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.callout)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}

struct UpdateSettings: View {
    @Environment(UpdateController.self) private var updater
    @AppStorage(UpdateController.checksAutomaticallyKey) private var checksAutomatically = true
    @AppStorage(UpdateController.downloadsAutomaticallyKey) private var downloadsAutomatically = true

    var body: some View {
        Section("Updates") {
            Toggle("Check for updates at startup", isOn: $checksAutomatically)
            Toggle("Download updates automatically", isOn: $downloadsAutomatically)
                .disabled(!checksAutomatically)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version \(updater.currentVersion)")
                    Text(statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if updater.isBusy {
                    ProgressView().controlSize(.small)
                }
                Button("Check Now", action: updater.checkNow)
                    .disabled(!updater.isEnabled || updater.isBusy)
            }
        }
    }

    private var statusText: String {
        guard updater.isEnabled else { return "Updates work only in the built app." }
        if case .downloading(let fraction) = updater.status {
            return "Downloading \(updater.available?.version.description ?? "update")… \(fraction.formatted(.percent.precision(.fractionLength(0))))"
        }
        if updater.status == .ready, let version = updater.available?.version {
            return "Version \(version) is ready to install."
        }
        guard let date = updater.lastChecked else { return "Not checked yet." }
        return "Last checked \(date.formatted(.relative(presentation: .named)))."
    }
}

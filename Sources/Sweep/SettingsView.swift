import SweepCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            IgnoredSettings()
                .tabItem { Label("Ignored Items", systemImage: "eye.slash") }
        }
        .frame(width: 540, height: 380)
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(DeleteMode.storageKey) private var deleteMode: DeleteMode = .moveToTrash

    var body: some View {
        Form {
            Section("Cleaning") {
                Picker("When cleaning", selection: $deleteMode) {
                    ForEach(DeleteMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(deleteMode == .moveToTrash ? "Items go to the Trash, so you can put them back." : "Items are deleted right away. This cannot be undone.")
                    .font(.callout)
                    .foregroundStyle(deleteMode == .moveToTrash ? Color.secondary : Color.red)
            }
            Section("Privacy") {
                HStack(spacing: 12) {
                    Image(systemName: model.hasFullDiskAccess ? "checkmark.shield.fill" : "lock.shield.fill")
                        .font(.title2)
                        .foregroundStyle(model.hasFullDiskAccess ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.hasFullDiskAccess ? "Full Disk Access is on" : "Full Disk Access is off")
                            .fontWeight(.medium)
                        Text(model.hasFullDiskAccess ? "Sweep can see every folder on your disk." : "Some folders stay hidden from Sweep, so results are incomplete.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check Again", action: model.refreshFullDiskAccess)
                    if !model.hasFullDiskAccess {
                        Button("Open Settings", action: model.openFullDiskAccessSettings)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct IgnoredSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.ignoredKeys.isEmpty {
                ContentUnavailableView("No ignored items", systemImage: "eye", description: Text("Right-click an item and choose Always Ignore to hide it from future scans."))
            } else {
                List {
                    ForEach(model.ignoredKeys, id: \.self) { key in
                        HStack(spacing: 10) {
                            Image(systemName: key.hasPrefix("/") ? "folder" : "tag")
                                .foregroundStyle(.secondary)
                            Text(PathDisplay.abbreviated(key))
                                .font(.callout.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(key)
                            Spacer()
                            Button {
                                model.unignore(key)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Stop ignoring")
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                HStack {
                    Text("\(CountFormat.items(model.ignoredKeys.count)) hidden from results")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore All", action: model.unignoreAll)
                }
                .padding(12)
            }
        }
    }
}

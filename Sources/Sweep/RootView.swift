import AppKit
import SweepCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(UpdateController.self) private var updater
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 310, max: 380)
        } detail: {
            DetailContainer()
                .sheet(isPresented: updatePromptBinding) {
                    UpdateSheet()
                        .environment(model)
                        .environment(updater)
                }
        }
        .sheet(isPresented: $model.isConfirmingClean) {
            ConfirmCleanSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshFullDiskAccess()
        }
        .task { await runDemoAutopilotIfNeeded() }
        .task { updater.start() }
    }

    private var updatePromptBinding: Binding<Bool> {
        Binding(
            get: { updater.isPromptRequested && model.phase != .scanning && model.phase != .cleaning && !model.isConfirmingClean },
            set: { isPresented in if !isPresented { updater.remindLater() } }
        )
    }

    private func runDemoAutopilotIfNeeded() async {
        #if DEBUG
        await DemoAutopilot.run(model, openSettings: { openSettings() })
        #endif
    }
}

struct DetailContainer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            DetailBackground()
            phaseContent
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
        }
        .animation(.smooth(duration: 0.45), value: model.phase)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .home: HomeView()
        case .scanning: ScanningView()
        case .results: ResultsContainer()
        case .cleaning: CleaningView()
        case .done: DoneView()
        }
    }
}

struct ResultsContainer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        destinationContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsCleanBar { CleanBar() }
            }
    }

    private var showsCleanBar: Bool {
        if case .explorer = model.destination { return false }
        return true
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch model.destination {
        case .overview: OverviewView()
        case .explorer: SpaceExplorerView()
        case .category(let category): CategoryDetailView(category: category).id(category)
        }
    }
}

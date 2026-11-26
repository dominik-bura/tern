import SwiftUI

/// Standard macOS menu rows; editing belongs in the application window.
struct MenuBarMenu: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: RoutingCoordinator

    var body: some View {
        if let pending = router.current, pending.error != nil {
            Button("Review Pending Link…") { router.onNeedsAttention?() }
            Divider()
        }
        Button("New Rule…") { model.startNewRule() }.keyboardShortcut("n")
        Button("Open Link from Clipboard") {
            model.openClipboard()
            if model.error != nil { model.showDashboard?() }
        }
        if !model.isDefaultBrowser {
            Divider()
            Button("Make \(TernAssets.appName) Default Browser…") { run { await model.makeDefault() } }
        }
        Divider()
        Button("Open \(TernAssets.appName)…") { model.showDashboard?() }.keyboardShortcut(",")
        Divider()
        UpdateMenuItems(updater: model.updater)
        Divider()
        Button("Quit \(TernAssets.appName)") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }

    /// Runs a menu action and brings up the window only if it needs the user's attention.
    private func run(_ action: @escaping () async -> Void) {
        Task {
            await action()
            if model.error != nil { model.showDashboard?() }
        }
    }
}

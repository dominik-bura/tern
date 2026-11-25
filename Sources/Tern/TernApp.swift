import SwiftUI

@main struct TernApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    init() { TernAssets.registerNamedImages() }
    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu().environmentObject(model).environmentObject(model.router)
        } label: {
            Image(nsImage: TernAssets.menuBarIcon).accessibilityLabel("Tern")
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Rule…") { model.startNewRule() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open Tern…") { model.showDashboard?() }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Close Window") { NSApplication.shared.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    model.configurationSection = .settings
                    model.showDashboard?()
                }.keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

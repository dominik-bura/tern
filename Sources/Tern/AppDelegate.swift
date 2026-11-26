import AppKit
import SwiftUI
import Combine
import TernUpdateCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var dashboard: NSWindow?
    private var mainController: MainWindowController?
    private var picker: NSWindow?
    private var receivedURL = false
    private var pickerObservation: AnyCancellable?
    private var clickMonitor: Any?
    private var updatePromptObservation: AnyCancellable?
    private var updatePromptWindow: UpdatePromptWindow?
    private var updateActivityTokens: [NSObjectProtocol] = []
    private var trackingMenus: Set<ObjectIdentifier> = []
    private let model = AppModel.shared
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.applicationIconImage = TernAssets.applicationIcon
        NSApplication.shared.setActivationPolicy(.accessory)
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            Self.endEditingIfClickedOutside(event)
            return event
        }
        model.showDashboard = { [weak self] in self?.showDashboard() }
        model.updatePickerIsVisible = { [weak self] in self?.picker?.isVisible == true }
        observeUpdateActivity()
        updatePromptObservation = model.updater.$presentedRelease.sink { [weak self] _ in
            DispatchQueue.main.async { self?.synchronizeUpdatePrompt() }
        }
        model.router.onNeedsAttention = { [weak self] in self?.showPicker() }
        pickerObservation = model.router.$current.sink { [weak self] pending in
            guard pending == nil else { return }
            DispatchQueue.main.async {
                guard self?.model.router.current == nil else { return }
                self?.picker?.orderOut(nil)
            }
        }
        if model.router.current != nil { showPicker() }
        if !UpdateRelaunch.isRequested(arguments: ProcessInfo.processInfo.arguments) {
            if !receivedURL { showDashboard() }
            if model.needsOnboarding {
                showDashboard()
                model.showsOnboarding = true
            }
        }
    }
    /// Like clicking empty space in System Settings: a click outside the focused text field ends editing.
    private static func endEditingIfClickedOutside(_ event: NSEvent) {
        guard let window = event.window, let editor = window.firstResponder as? NSText,
              let field = editor.delegate as? NSView,
              let contentView = window.contentView else { return }
        let hit = contentView.hitTest(contentView.convert(event.locationInWindow, from: nil))
        if let hit, hit === field || hit.isDescendant(of: field) || hit === editor || hit is NSTextField { return }
        window.makeFirstResponder(nil)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receivedURL = true
        model.receive(urls, sourceApp: Self.sendingApp())
    }
    /// The app the link came from: the sender of the "open URL" Apple event, or else the frontmost app.
    private static func sendingApp() -> String? {
        let own = Bundle.main.bundleIdentifier
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value, pid > 0,
           let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
           id != own, !Self.isSystemRelay(id) {
            return id
        }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return front == own ? nil : front
    }
    /// Services that forward links on behalf of the app the person actually used.
    private static func isSystemRelay(_ id: String) -> Bool {
        ["com.apple.launchservicesd", "com.apple.coreservices.uiagent", "com.apple.CoreServicesUIAgent"].contains(id)
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        // Picks up profile changes and newly granted Full Disk Access.
        model.loadBrowserProfiles()
        model.updater.activityDidChange()
    }
    func applicationDidResignActive(_ notification: Notification) { model.updater.activityDidChange() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard(); return true
    }
    func showDashboard() {
        NSApplication.shared.setActivationPolicy(.regular)
        let isNewWindow = dashboard == nil
        if dashboard == nil {
            let controller = MainWindowController(model: model)
            controller.window?.delegate = self
            mainController = controller
            dashboard = controller.window
        }
        model.refreshDefaultStatus()
        model.loadBrowserProfiles()
        NSApplication.shared.setActivationPolicy(.regular)
        dashboard?.makeKeyAndOrderFront(nil)
        // Don't start with the sidebar search focused.
        if isNewWindow { dashboard?.makeFirstResponder(nil) }
        NSApplication.shared.activate(ignoringOtherApps: true)
        model.updater.activityDidChange()
    }
    private func showPicker() {
        if picker == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 480), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Open Link In"
            window.contentView = NSHostingView(rootView: DestinationPickerView().environmentObject(model).environmentObject(model.router))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.level = .floating
            window.center()
            picker = window
        }
        picker?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === dashboard else { return }
        NSApplication.shared.setActivationPolicy(.accessory)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === picker {
            guard !model.router.isDelivering else { return false }
            model.router.cancel()
            return model.router.current == nil
        }
        return true
    }

    private func synchronizeUpdatePrompt() {
        guard let release = model.updater.presentedRelease else {
            let previous = updatePromptWindow
            updatePromptWindow = nil
            previous?.closeQuietly()
            return
        }
        guard updatePromptWindow == nil else { return }
        let controller = UpdatePromptWindow(updater: model.updater, release: release) { [weak self] userInitiated in
            guard let self else { return }
            self.updatePromptWindow = nil
            if userInitiated, self.model.updater.presentedRelease == release {
                self.model.updater.promptClosedByUser(release)
            }
        }
        updatePromptWindow = controller
        controller.present()
    }

    private func observeUpdateActivity() {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            updateActivityTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.updater.activityDidChange() }
            })
        }
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            updateActivityTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let menu = note.object as? NSMenu else { return }
                    if name == NSMenu.didBeginTrackingNotification { self.trackingMenus.insert(ObjectIdentifier(menu)) }
                    else { self.trackingMenus.remove(ObjectIdentifier(menu)) }
                    self.model.updater.setMenuTracking(!self.trackingMenus.isEmpty)
                }
            })
        }
    }
}

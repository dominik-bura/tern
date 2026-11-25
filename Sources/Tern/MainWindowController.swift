import AppKit
import Combine
import SwiftUI

/// The configuration window: a native sidebar split view with back/forward navigation in the toolbar.
@MainActor final class MainWindowController: NSWindowController, NSToolbarDelegate {
    private let model: AppModel
    private var navigationControl: NSSegmentedControl?
    private var sectionObservation: AnyCancellable?

    private static let navigationItem = NSToolbarItem.Identifier("navigation")

    init(model: AppModel) {
        self.model = model
        let sidebar = NSHostingController(rootView: SidebarView().environmentObject(model))
        let detail = NSHostingController(rootView: DetailView().environmentObject(model).environmentObject(model.router))
        sidebar.sizingOptions = []
        detail.sizingOptions = []

        let split = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = SettingsStyle.sidebarWidth
        sidebarItem.maximumThickness = SettingsStyle.sidebarWidth
        sidebarItem.canCollapse = false
        split.addSplitViewItem(sidebarItem)
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 480
        split.addSplitViewItem(detailItem)
        split.splitView.autosaveName = "TernMainSplit"

        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.setContentSize(NSSize(width: 800, height: 690))
        window.contentMinSize = NSSize(width: 700, height: 460)
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let toolbar = NSToolbar(identifier: "TernMainToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        if !window.setFrameUsingName("TernSettingsWindowV3") { window.center() }
        window.setFrameAutosaveName("TernSettingsWindowV3")

        sectionObservation = model.$configurationSection.sink { [weak self] section in
            self?.window?.title = section.title
            DispatchQueue.main.async { self?.updateNavigationControls() }
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, Self.navigationItem, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard identifier == Self.navigationItem else { return nil }
        let control = NSSegmentedControl(images: [
            NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")!,
            NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")!
        ], trackingMode: .momentary, target: self, action: #selector(navigate(_:)))
        control.segmentStyle = .separated
        control.setToolTip("Back", forSegment: 0)
        control.setToolTip("Forward", forSegment: 1)
        navigationControl = control
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "Back/Forward"
        item.view = control
        item.isNavigational = true
        updateNavigationControls()
        return item
    }

    @objc private func navigate(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 { model.goBack() } else { model.goForward() }
        updateNavigationControls()
    }

    private func updateNavigationControls() {
        navigationControl?.setEnabled(model.canGoBack, forSegment: 0)
        navigationControl?.setEnabled(model.canGoForward, forSegment: 1)
    }
}

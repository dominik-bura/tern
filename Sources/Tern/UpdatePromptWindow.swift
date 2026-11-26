import AppKit
import SwiftUI

@MainActor final class UpdatePromptWindow: NSWindowController, NSWindowDelegate {
    private var suppressReminder = false
    private let onClose: (Bool) -> Void

    init(updater: UpdateController, release: UpdateRelease, onClose: @escaping (Bool) -> Void) {
        self.onClose = onClose
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 390),
                            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Tern Update"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        super.init(window: panel)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: UpdatePromptView(updater: updater, release: release))
        panel.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func present() { window?.makeKeyAndOrderFront(nil) }
    func closeQuietly() { suppressReminder = true; close() }
    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        onClose(!suppressReminder)
    }
}

struct UpdatePromptView: View {
    @ObservedObject var updater: UpdateController
    let release: UpdateRelease

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: TernAssets.applicationIcon).resizable().scaledToFit().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 5) {
                    Text(updater.isReady ? "Your update is ready" : "A new version is available").font(.headline)
                    Text("Tern \(updater.currentVersion) → \(release.version)")
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if updater.isDownloading || updater.isInstalling {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(updater.isInstalling ? "Restarting to update…" : "Downloading and verifying…")
                }
                Text("Links can keep routing while the update downloads. Tern won’t restart with pending links or an open rule editor.")
                    .font(.callout).foregroundStyle(.secondary)
                if !updater.isInstalling {
                    Button("Continue Using Tern") { updater.remindTomorrow(release) }
                }
            } else {
                Text("Get the latest improvements and fixes. Tern will reopen quietly in the menu bar after updating.")
                    .font(.callout).foregroundStyle(.secondary)
                if let message = updater.failureMessage ?? updater.restartBlockedReason ?? updater.installationNotice {
                    Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Link("Release Notes", destination: release.releasePageURL).font(.caption)
                HStack {
                    Button("Skip Version") { updater.skipVersion(release) }
                    Spacer()
                    Button("Update & Relaunch") { updater.installUpdate(release) }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(!updater.canInstall)
                }
                HStack {
                    Spacer()
                    Button("Remind Tomorrow") { updater.remindTomorrow(release) }.keyboardShortcut(.cancelAction)
                }
            }
            Divider()
            Toggle("Automatically install updates", isOn: $updater.automaticallyInstallsUpdates)
                .toggleStyle(.checkbox).font(.caption).disabled(updater.isInstalling)
            Text("Off by default. Restarts wait for one idle minute with no open Tern windows, pending links, or rule editing.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(22).frame(width: 440, alignment: .leading)
    }
}

struct UpdateMenuItems: View {
    @ObservedObject var updater: UpdateController
    var body: some View {
        Button(updater.menuTitle) { updater.requestUpdatePrompt() }
            .disabled(!updater.isConfigured || updater.isInstalling)
        if updater.isDownloading { Text("Downloading and verifying…") }
    }
}

struct UpdateSettingsRows: View {
    @ObservedObject var updater: UpdateController
    var body: some View {
        SettingsRow("Version") {
            Text("\(updater.currentVersion) (\(updater.buildNumber))").foregroundStyle(.secondary)
        }
        RowSeparator()
        statusRow
        RowSeparator()
        SettingsRow("Automatically Install Updates", subtitle: "Restart after a minute with no open Tern windows, pending links, or rule editing") {
            Toggle("", isOn: $updater.automaticallyInstallsUpdates)
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .disabled(!updater.isConfigured || updater.isInstalling)
        }
    }

    @ViewBuilder private var statusRow: some View {
        switch updater.state {
        case .unavailable:
            SettingsRow("Software Update") { Text("Unavailable in development builds").foregroundStyle(.secondary) }
        case .checking:
            SettingsRow("Checking for Updates…") { ProgressView().controlSize(.small) }
        case .downloading:
            SettingsRow("Downloading and Verifying…") { ProgressView().controlSize(.small) }
        case .installing:
            SettingsRow("Restarting to Update…") { ProgressView().controlSize(.small) }
        case .available(let release), .ready(let release):
            SettingsRow(updater.isReady ? "Tern \(release.version) is ready" : "Tern \(release.version) is available",
                        subtitle: updater.restartBlockedReason ?? updater.installationNotice) {
                Button("Review Update…") { updater.requestUpdatePrompt() }
            }
        case .failed(let message):
            SettingsRow("Update Needs Attention", subtitle: message) {
                Button(updater.availableRelease == nil ? "Check Again" : "Review Update…") {
                    updater.requestUpdatePrompt()
                }
            }
        case .idle, .upToDate:
            SettingsRow("Software Update", subtitle: updater.state == .idle ? nil : "Tern is up to date") {
                Button("Check Now") { Task { await updater.checkForUpdates(showPrompt: true) } }
            }
        }
    }
}

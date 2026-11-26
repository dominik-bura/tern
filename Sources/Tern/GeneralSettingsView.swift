import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SettingsPage {
            SettingsSection(footer: "Links you click inside a browser usually stay in that browser.") {
                SettingsRow(
                    title: model.isDefaultBrowser ? "Tern is your default browser" : "Tern is not your default browser",
                    subtitle: model.isDefaultBrowser
                        ? "Links from other apps are routed by your rules."
                        : "Links from other apps open in \(model.currentBrowserName).",
                    leading: { Image(nsImage: TernAssets.applicationIcon).resizable().frame(width: 40, height: 40) },
                    trailing: {
                        if model.isDefaultBrowser {
                            if model.canRestoreBrowser { Button("Restore Previous…") { Task { await model.restoreDefault() } } }
                        } else {
                            Button("Make Default…") { Task { await model.makeDefault() } }
                        }
                    }
                )
                .frame(minHeight: 66)
            }

            SettingsSection("Links", footer: "Everything except Resolve Short Links happens on your Mac. Outlook Safe Links and Proofpoint links still open through your organization’s scanner.") {
                SettingsRow("Unwrap Redirect Links", subtitle: "Match the real destination behind Outlook Safe Links, Google, Slack, and similar") {
                    switchToggle(Binding(get: { model.configuration.unwrapLinks }, set: { model.setUnwrapLinks($0) }))
                }
                RowSeparator()
                SettingsRow("Resolve Short Links", subtitle: "Ask t.co, bit.ly, and similar where a link points: one request over HTTPS, without cookies") {
                    switchToggle(Binding(get: { model.configuration.resolveShortLinks }, set: { model.setResolveShortLinks($0) }))
                }
                RowSeparator()
                SettingsRow("Remove Tracking Parameters", subtitle: "Strip utm_source, fbclid, gclid, and similar before opening") {
                    switchToggle(Binding(get: { model.configuration.removeTracking }, set: { model.setRemoveTracking($0) }))
                }
            }

            SettingsSection("Startup") {
                SettingsRow("Open at Login", subtitle: "Keeps Tern ready in the menu bar so links route instantly") {
                    switchToggle(Binding(get: { model.opensAtLogin }, set: { model.setOpensAtLogin($0) }))
                }
                RowSeparator()
                SettingsRow("Welcome Guide", subtitle: "Set up Tern step by step") {
                    Button("Show…") { model.showsOnboarding = true }
                }
            }

            SettingsSection("Rules File") {
                SettingsRow("Import Rules", subtitle: "Replace your current rules from a file") {
                    Button("Import…") { model.importRules() }
                }
                RowSeparator()
                SettingsRow("Export Rules", subtitle: "Save a copy of your rules as JSON") {
                    Button("Export…") { model.exportRules() }
                }
                RowSeparator()
                SettingsRow("Location") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.fileURL]) }
                }
            }

            SettingsSection("Updates") {
                UpdateSettingsRows(updater: model.updater)
            }
        }
    }

    private func switchToggle(_ isOn: Binding<Bool>) -> some View {
        Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
    }

}

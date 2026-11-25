import AppKit
import SwiftUI

/// All installed browsers. Browsers with profile support expand to show their profiles.
struct DestinationsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var expanded: Set<String> = []

    var body: some View {
        SettingsPage {
            SettingsSection(footer: "Expand a browser to see its profiles. Rules and the link picker can open links directly in a profile.") {
                ForEach(Array(model.browsers.enumerated()), id: \.element.id) { index, browser in
                    if index > 0 { RowSeparator() }
                    browserRow(browser)
                    if model.supportsProfiles(browser), expanded.contains(browser.id) {
                        profileRows(for: browser)
                    }
                }
            }
        }
    }

    @ViewBuilder private func browserRow(_ browser: InstalledBrowser) -> some View {
        let canExpand = model.supportsProfiles(browser)
        let isExpanded = expanded.contains(browser.id)
        let count = model.profileItems(of: browser).count
        SettingsRow(title: browser.name, leading: {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 12)
                .opacity(canExpand ? 1 : 0)
            Image(nsImage: NSWorkspace.shared.icon(forFile: browser.url.path)).resizable().frame(width: 20, height: 20)
        }) {
            if canExpand {
                Text(count == 0 ? "Profiles" : count == 1 ? "1 Profile" : "\(count) Profiles").foregroundStyle(.secondary)
                if isExpanded, BrowserProfiles.cachedProfiles(for: browser.id) != nil {
                    Button("Reload Names…") { model.chooseProfileList(for: browser) }.controlSize(.small)
                } else if isExpanded, count > 0 {
                    if model.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button { Task { await model.refreshDestinations() } } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless).help("Refresh Profiles").accessibilityLabel("Refresh Profiles")
                    }
                }
            }
        }
        .onTapGesture {
            guard canExpand else { return }
            withAnimation(.snappy(duration: 0.2)) {
                if isExpanded { expanded.remove(browser.id) } else { expanded.insert(browser.id) }
            }
        }
        .accessibilityAddTraits(canExpand ? .isButton : [])
        .accessibilityHint(canExpand ? (isExpanded ? "Collapse profiles" : "Show profiles") : "")
    }

    @ViewBuilder private func profileRows(for browser: InstalledBrowser) -> some View {
        let items = model.profileItems(of: browser)
        if model.profileNamesHidden.contains(browser.id) {
            RowSeparator().padding(.leading, 34)
            SettingsRow(
                title: "Show Profile Names",
                subtitle: "\(browser.name) keeps them private. Select “\(BrowserProfiles.listFileName(for: browser.id))” once to show them.",
                leading: { Image(systemName: "lock.fill").foregroundStyle(.secondary).frame(width: 20) },
                trailing: { Button("Select File…") { model.chooseProfileList(for: browser) } }
            )
            .padding(.leading, 34)
        }
        if items.isEmpty, !model.profileNamesHidden.contains(browser.id) {
            RowSeparator().padding(.leading, 34)
            SettingsRow("No profiles found", subtitle: "Open \(browser.name) once, then refresh.") {
                refreshButton
            }
            .padding(.leading, 34)
        }
        ForEach(items) { item in
            RowSeparator().padding(.leading, 34)
            SettingsRow(title: item.name, leading: { ProfileBadge(item: item, size: 20) }) {
                if item.canSwitch, case .dia(let profile) = item.destination {
                    Button("Switch") { Task { await model.switchProfile(profile) } }
                        .help("Switch the frontmost \(browser.name) window to \(profile.name)")
                    Menu {
                        Button("Open Current Page in \(profile.name)") { Task { await model.openCurrentPage(in: profile) } }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                        .help("Profile Actions").accessibilityLabel("Actions for \(profile.name)")
                }
            }
            .padding(.leading, 34)
        }
    }

    @ViewBuilder private var refreshButton: some View {
        if model.isRefreshing {
            ProgressView().controlSize(.small)
        } else {
            Button("Refresh") { Task { await model.refreshDestinations() } }
        }
    }
}

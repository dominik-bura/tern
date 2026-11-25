import SwiftUI
import UniformTypeIdentifiers

struct RuleEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var rule: RoutingRule
    @State private var validation: String?

    private var isNew: Bool { !model.configuration.rules.contains(where: { $0.id == rule.id }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New Rule" : "Edit Rule").font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, SettingsStyle.rowInset)

            SettingsSection {
                SettingsRow("Name") { field("Work GitHub", text: $rule.name) }
                RowSeparator()
                SettingsRow("Enabled") { toggle($rule.enabled) }
                RowSeparator()
                SettingsRow("Group") {
                    field("None", text: Binding(get: { rule.group ?? "" }, set: { rule.group = $0.isEmpty ? nil : $0 }))
                    if !model.configuration.groups.isEmpty {
                        Menu {
                            Button("None") { rule.group = nil }
                            Divider()
                            ForEach(model.configuration.groups, id: \.self) { group in Button(group) { rule.group = group } }
                        } label: { Image(systemName: "chevron.up.chevron.down") }
                            .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                            .help("Choose a Group").accessibilityLabel("Choose a Group")
                    }
                }
            }

            SettingsSection(title: "Match", footer: matchFooter) {
                switch rule.matcher.kind {
                case .domain:
                    SettingsRow("Domain") {
                        field("Any domain", text: $rule.matcher.host)
                            .onSubmit(normalizeDomain)
                            .onChange(of: rule.matcher.host) { old, new in
                                // A paste inserts several characters at once; typing adds one.
                                if new.count - old.count > 1 { normalizeDomain() }
                            }
                    }
                    RowSeparator()
                    SettingsRow("Include Subdomains") { toggle($rule.matcher.includeSubdomains) }
                    RowSeparator()
                    SettingsRow("Path") {
                        field("Optional, e.g. /team", text: $rule.matcher.pathPrefix)
                            .onSubmit { rule.matcher.pathPrefix = URLMatcher.parsePathInput(rule.matcher.pathPrefix) }
                            .onChange(of: rule.matcher.pathPrefix) { old, new in
                                if new.count - old.count > 1 { rule.matcher.pathPrefix = URLMatcher.parsePathInput(new) }
                            }
                    }
                case .wildcard:
                    SettingsRow("Pattern") { field("*.atlassian.net/wiki/*", text: $rule.matcher.pattern) }
                case .regex:
                    SettingsRow("Expression") {
                        field("^https://github\\.com/statworx/", text: $rule.matcher.pattern)
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
                RowSeparator()
                SettingsRow("Clicked In", subtitle: rule.matcher.sourceApps.isEmpty ? "Any app" : nil) {
                    SourceAppsField(apps: $rule.matcher.sourceApps)
                }
            } accessory: {
                Picker("Match Type", selection: $rule.matcher.kind) {
                    Text("Domain").tag(URLMatcher.Kind.domain)
                    Text("Wildcard").tag(URLMatcher.Kind.wildcard)
                    Text("Regex").tag(URLMatcher.Kind.regex)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
            }

            SettingsSection("Destination") {
                SettingsRow("Open In") {
                    DestinationPicker(title: "Open In", selection: $rule.destination).labelsHidden().fixedSize()
                    Button { Task { await model.refreshDestinations() } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).disabled(model.isRefreshing)
                        .help("Refresh Profiles").accessibilityLabel("Refresh Profiles")
                }
            }

            if let validation {
                Label(validation, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(.red)
                    .padding(.horizontal, SettingsStyle.rowInset)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Rule" : "Save", action: save).keyboardShortcut(.defaultAction)
                    .nativeProminentButtonStyle()
            }
            .nativeButtonStyle()
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 520)
        .background(SettingsStyle.content)
    }

    private var matchFooter: String {
        switch rule.matcher.kind {
        case .domain: return "Leave Domain empty to match every link from the chosen apps. Paths match whole segments and ignore case: /team matches /Team/docs but not /teammate."
        case .wildcard: return "* matches anything. Without a /, the pattern is checked against the domain only. Case is ignored."
        case .regex: return "Tested against the whole link, including https://. Case is ignored."
        }
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(verbatim: prompt))
            .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
            .frame(maxWidth: 240)
    }

    private func toggle(_ isOn: Binding<Bool>) -> some View {
        Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
    }

    /// Converts a pasted link or "*.domain" into the Domain, Path, and subdomain settings.
    private func normalizeDomain() {
        guard rule.matcher.kind == .domain, let parsed = URLMatcher.parseDomainInput(rule.matcher.host) else { return }
        rule.matcher.host = parsed.host
        if parsed.includeSubdomains { rule.matcher.includeSubdomains = true }
        if let path = parsed.path, rule.matcher.pathPrefix.trimmingCharacters(in: .whitespaces).isEmpty {
            rule.matcher.pathPrefix = path
        }
        if rule.name.trimmingCharacters(in: .whitespaces).isEmpty { rule.name = parsed.host }
        validation = nil
    }

    private func save() {
        normalizeDomain()
        rule.matcher.pathPrefix = URLMatcher.parsePathInput(rule.matcher.pathPrefix)
        do {
            rule.matcher.host = rule.matcher.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            rule.matcher.pattern = rule.matcher.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            rule.name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
            rule.group = rule.group?.trimmingCharacters(in: .whitespacesAndNewlines)
            if rule.group?.isEmpty == true { rule.group = nil }
            if rule.name.isEmpty, rule.matcher.kind != .domain { rule.name = rule.matcher.pattern }
            if rule.name.isEmpty, rule.matcher.host.isEmpty, let app = rule.matcher.sourceApps.first {
                rule.name = "Links from \(AppInfo.name(for: app))"
            }
            try rule.matcher.validate(); try rule.destination.validate()
            guard !rule.name.isEmpty else { throw TernError.message("Give this rule a name.") }
            model.save(rule)
            if model.configuration.rules.contains(rule) { dismiss() }
        } catch { validation = error.localizedDescription }
    }
}

/// The apps a rule is limited to, shown as removable chips with an Add menu.
private struct SourceAppsField: View {
    @EnvironmentObject private var model: AppModel
    @Binding var apps: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(apps, id: \.self) { id in
                HStack(spacing: 4) {
                    Image(nsImage: AppInfo.icon(for: id)).resizable().frame(width: 16, height: 16)
                    Text(AppInfo.name(for: id)).lineLimit(1)
                    Button { apps.removeAll { $0 == id } } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .accessibilityLabel("Remove \(AppInfo.name(for: id))")
                }
                .padding(.leading, 6).padding(.trailing, 4).padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
            }
            Menu {
                ForEach(model.sourceAppCandidates().filter { !apps.contains($0) }, id: \.self) { id in
                    Button { apps.append(id) } label: {
                        Label { Text(AppInfo.name(for: id)) } icon: { Image(nsImage: AppInfo.icon(for: id)) }
                    }
                }
                Divider()
                Button("Other App…", action: chooseApp)
            } label: { Image(systemName: "plus") }
                .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                .help("Add App").accessibilityLabel("Add App")
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Add App"
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier,
              !apps.contains(id), !BrowserRegistry.isTern(id) else { return }
        apps.append(id)
    }
}

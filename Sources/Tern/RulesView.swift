import SwiftUI
import UniformTypeIdentifiers

struct RulesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var testURL = ""
    @State private var testSource: String?
    @State private var dragging: UUID?
    @State private var indicator: DropIndicator?
    @State private var renaming: String?
    @State private var groupName = ""

    private var rules: [RoutingRule] { model.configuration.rules }

    /// Sections in the order rules are checked: ungrouped rules first, then each group.
    private var sections: [(group: String?, rules: [RoutingRule])] {
        let groups = model.configuration.groups
        var result: [(String?, [RoutingRule])] = []
        let ungrouped = rules.filter { $0.group == nil }
        if !ungrouped.isEmpty || groups.isEmpty { result.append((nil, ungrouped)) }
        for group in groups { result.append((group, rules.filter { $0.group == group })) }
        return result
    }

    var body: some View {
        SettingsPage {
            let sections = sections
            ForEach(Array(sections.enumerated()), id: \.element.group) { index, section in
                ruleSection(section.group, rules: section.rules, isFirst: index == 0, isLast: index == sections.count - 1)
            }

            SettingsSection("Unmatched Links") {
                SettingsRow("Open In", subtitle: "Where links go when no rule matches") {
                    DestinationPicker(title: "Open In", selection: Binding(get: { model.configuration.fallback }, set: { model.setFallback($0) }))
                        .labelsHidden().fixedSize()
                }
            }

            SettingsSection("Test a Link", footer: "Shows where a link would open, without opening it.") {
                SettingsRow("URL") {
                    TextField("URL", text: $testURL, prompt: Text(verbatim: "https://example.com/team"))
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                        .accessibilityLabel("Test URL")
                }
                RowSeparator()
                SettingsRow("Clicked In") {
                    Picker("Clicked In", selection: $testSource) {
                        Text("Any App").tag(String?.none)
                        Divider()
                        ForEach(model.sourceAppCandidates(), id: \.self) { id in
                            Text(AppInfo.name(for: id)).tag(Optional(id))
                        }
                    }
                    .labelsHidden().fixedSize()
                }
                if !testURL.isEmpty {
                    RowSeparator()
                    testResult
                }
            }
        }
        .alert("Rename Group", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $groupName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") { if let renaming { model.renameGroup(renaming, to: groupName) }; renaming = nil }
        }
    }

    @ViewBuilder private func ruleSection(_ group: String?, rules: [RoutingRule], isFirst: Bool, isLast: Bool) -> some View {
        SettingsSection(
            title: group ?? "Rules",
            footer: isLast ? "Rules are checked from top to bottom, and the first enabled match wins. Drag rules to reorder them or move them between groups." : nil
        ) {
            if rules.isEmpty {
                SettingsRow("No rules yet", subtitle: "Open a site in a specific browser or profile.") {
                    Button("Add Rule…") { model.editingRule = RoutingRule() }
                }
            } else {
                ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                    if index > 0 { RowSeparator() }
                    RuleRow(rule: rule, isFirst: index == 0, isLast: index == rules.count - 1,
                            groups: model.configuration.groups, indicator: indicator?.ruleID == rule.id ? indicator?.edge : nil)
                        .onDrag {
                            dragging = rule.id
                            return NSItemProvider(object: rule.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: RuleDropDelegate(
                            target: rule, next: index + 1 < rules.count ? rules[index + 1].id : nil,
                            model: model, dragging: $dragging, indicator: $indicator))
                }
            }
        } accessory: {
            HStack(spacing: 6) {
                if let group {
                    Menu {
                        Button("Add Rule to Group…") { model.editingRule = RoutingRule(group: group) }
                        Divider()
                        Button("Enable All") { model.setGroupEnabled(group, true) }
                        Button("Disable All") { model.setGroupEnabled(group, false) }
                        Divider()
                        Button("Rename Group…") { groupName = group; renaming = group }
                        Button("Ungroup") { model.ungroup(group) }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                        .help("Group Actions").accessibilityLabel("Actions for \(group)")
                } else if isFirst, !self.rules.isEmpty {
                    Button("Add Rule…") { model.editingRule = RoutingRule() }.controlSize(.small)
                }
            }
        }
        .onDrop(of: [.text], delegate: GroupDropDelegate(group: group, model: model, dragging: $dragging, indicator: $indicator))
    }

    @ViewBuilder private var testResult: some View {
        if let url = URL(string: testURL.trimmingCharacters(in: .whitespaces)), IncomingURLRequest.isSupported(url) {
            let options = model.configuration
            let cleaned = LinkCleaner.cleanLocally(url, unwrap: options.unwrapLinks, removeTracking: options.removeTracking)
            let decision = RuleEngine.decide(cleaned, sourceApp: testSource, configuration: options)
            if cleaned != url {
                SettingsRow("Cleaned Link", subtitle: cleaned.absoluteString) { EmptyView() }
                RowSeparator()
            }
            SettingsRow("Opens In", subtitle: decision.ruleName.map { "Matched “\($0)”" } ?? "No rule matched") {
                DestinationIcon(destination: decision.destination, size: 16)
                Text(model.destinationName(decision.destination)).font(.system(size: 13, weight: .medium))
            }
        } else {
            SettingsRow("Opens In", subtitle: "Enter a complete http:// or https:// link.") { EmptyView() }
        }
    }
}

struct DropIndicator: Equatable {
    enum Edge { case top, bottom }
    let ruleID: UUID
    let edge: Edge
}

/// Dropping on the upper half of a row inserts before it, on the lower half after it.
private struct RuleDropDelegate: DropDelegate {
    let target: RoutingRule
    let next: UUID?
    let model: AppModel
    @Binding var dragging: UUID?
    @Binding var indicator: DropIndicator?

    private func edge(_ info: DropInfo) -> DropIndicator.Edge { info.location.y < SettingsStyle.rowHeight / 2 + 4 ? .top : .bottom }

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        indicator = dragging == target.id ? nil : DropIndicator(ruleID: target.id, edge: edge(info))
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { if indicator?.ruleID == target.id { indicator = nil } }
    func performDrop(info: DropInfo) -> Bool {
        defer { dragging = nil; indicator = nil }
        guard let id = dragging else { return false }
        let before = edge(info) == .top ? target.id : next
        MainActor.assumeIsolated { model.moveRule(id, toGroup: target.group, before: before) }
        return true
    }
}

/// Dropping on a section outside its rows moves the rule to the end of that group.
private struct GroupDropDelegate: DropDelegate {
    let group: String?
    let model: AppModel
    @Binding var dragging: UUID?
    @Binding var indicator: DropIndicator?

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        defer { dragging = nil; indicator = nil }
        guard let id = dragging else { return false }
        MainActor.assumeIsolated { model.moveRule(id, toGroup: group, before: nil) }
        return true
    }
}

private struct RuleRow: View {
    @EnvironmentObject private var model: AppModel
    let rule: RoutingRule
    let isFirst: Bool
    let isLast: Bool
    let groups: [String]
    let indicator: DropIndicator.Edge?
    @State private var newGroup = ""
    @State private var askingForGroup = false

    private var subtitle: String {
        var parts = [rule.matcher.summary]
        if !rule.matcher.sourceApps.isEmpty {
            parts[0] = (rule.matcher.kind == .domain && rule.matcher.host.isEmpty ? "Links" : parts[0])
                + " from " + rule.matcher.sourceApps.map(AppInfo.name(for:)).formatted(.list(type: .or))
        }
        if let usage = model.ruleUsage[rule.id] {
            let when = usage.lastUsed.formatted(.relative(presentation: .named))
            parts.append(usage.count == 1 ? "Used once, \(when)" : "Used \(usage.count) times, last \(when)")
        } else {
            parts.append("Not used yet")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        SettingsRow(rule.name, subtitle: subtitle, dimmed: !rule.enabled) {
            HStack(spacing: 6) {
                DestinationIcon(destination: rule.destination, size: 16)
                Text(model.destinationName(rule.destination)).foregroundStyle(.secondary).lineLimit(1)
            }
            .opacity(rule.enabled ? 1 : 0.5)
            Toggle("Enabled", isOn: Binding(get: { rule.enabled }, set: { _ in model.toggle(rule) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel("Enable \(rule.name)")
            Menu { actions } label: { Image(systemName: "ellipsis") }
                .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                .help("Rule Actions").accessibilityLabel("Actions for \(rule.name)")
        }
        .overlay(alignment: indicator == .top ? .top : .bottom) {
            if indicator != nil {
                Capsule().fill(Color.accentColor).frame(height: 2).padding(.horizontal, 8)
                    .offset(y: indicator == .top ? -1 : 1)
            }
        }
        .onTapGesture(count: 2) { model.editingRule = rule }
        .contextMenu { actions }
        .alert("New Group", isPresented: $askingForGroup) {
            TextField("Name", text: $newGroup)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newGroup.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { model.moveRule(rule.id, toGroup: name, before: nil) }
            }
        } message: { Text("“\(rule.name)” moves into the new group.") }
    }

    @ViewBuilder private var actions: some View {
        Button("Edit…") { model.editingRule = rule }
        Menu("Move to Group") {
            Button("New Group…") { newGroup = ""; askingForGroup = true }
            if !groups.isEmpty { Divider() }
            ForEach(groups, id: \.self) { group in
                Button(group) { model.moveRule(rule.id, toGroup: group, before: nil) }.disabled(rule.group == group)
            }
            if rule.group != nil {
                Divider()
                Button("Remove from Group") { model.moveRule(rule.id, toGroup: nil, before: nil) }
            }
        }
        Divider()
        Button("Move Up") { model.move(rule.id, by: -1) }.disabled(isFirst)
        Button("Move Down") { model.move(rule.id, by: 1) }.disabled(isLast)
        Divider()
        Button("Delete", role: .destructive) { model.remove(rule.id) }
    }
}

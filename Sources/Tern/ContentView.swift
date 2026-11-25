import SwiftUI

enum ConfigurationSection: String, CaseIterable, Identifiable {
    case rules = "Rules"
    case destinations = "Browsers"
    case settings = "General"
    var id: Self { self }
    var title: String { rawValue }
    var symbol: String {
        switch self {
        case .settings: return "gearshape.fill"
        case .rules: return "arrow.triangle.branch"
        case .destinations: return "globe"
        }
    }
    var color: Color {
        switch self {
        case .settings: return .gray
        case .rules: return .blue
        case .destinations: return .orange
        }
    }
    var searchTerms: String {
        switch self {
        case .settings: return "general settings default browser configuration import export update version"
        case .rules: return "rules routing hostname path fallback unmatched test url"
        case .destinations: return "browsers profiles dia switch destinations"
        }
    }
}

/// The sidebar column: a search field and the section list.
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""

    private var visibleSections: [ConfigurationSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return ConfigurationSection.allCases.filter { section in
            query.isEmpty || section.title.localizedCaseInsensitiveContains(query) ||
                section.searchTerms.localizedCaseInsensitiveContains(query) ||
                (section == .rules && model.configuration.rules.contains { "\($0.name) \($0.matcher.host)".localizedCaseInsensitiveContains(query) }) ||
                (section == .destinations && (model.browserProfiles.values.joined().contains { $0.name.localizedCaseInsensitiveContains(query) } || model.profiles.contains { $0.name.localizedCaseInsensitiveContains(query) } || model.browsers.contains { $0.name.localizedCaseInsensitiveContains(query) }))
        }
    }

    private var selection: Binding<ConfigurationSection?> {
        Binding(get: { model.configurationSection }, set: { if let value = $0 { model.configurationSection = value } })
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $searchText, prompt: "Search settings…")
                .controlSize(.large)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 18)
            List(selection: selection) {
                ForEach(visibleSections) { section in
                    Label { Text(section.title) } icon: { SidebarIcon(symbol: section.symbol, color: section.color) }
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .overlay {
                if visibleSections.isEmpty { Text("No Results").foregroundStyle(.secondary) }
            }
        }
        .background(SettingsStyle.sidebar.ignoresSafeArea())
        .overlay(alignment: .trailing) { SettingsStyle.sidebarDivider.frame(width: 1).ignoresSafeArea() }
        .onChange(of: searchText) { _, _ in
            if !visibleSections.contains(model.configurationSection), let first = visibleSections.first { model.configurationSection = first }
        }
    }
}

/// The system search field (Liquid Glass on macOS 26 and later).
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        if #available(macOS 26.0, *) { field.controlSize = .extraLarge } else { field.controlSize = .large }
        field.setAccessibilityLabel("Search settings")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

/// The detail column: the selected section's settings.
struct DetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.configurationSection {
            case .settings: GeneralSettingsView()
            case .rules: RulesView()
            case .destinations: DestinationsView()
            }
        }
        .sheet(isPresented: $model.showsOnboarding) { OnboardingView().environmentObject(model) }
        .frame(minWidth: 480, minHeight: 440)
        .background(SettingsStyle.content)
        .nativeButtonStyle()
        .sheet(item: $model.editingRule) { rule in RuleEditorView(rule: rule).environmentObject(model) }
        .alert("Tern needs your attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}


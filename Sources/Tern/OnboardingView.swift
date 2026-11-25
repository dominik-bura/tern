import SwiftUI

/// First-run guide: make Tern the default browser, choose where links go, add a first rule.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var step = 0
    @State private var domain = ""
    @State private var destination: BrowserDestination = .ask
    @State private var validation: String?

    private let stepCount = 4

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: defaultBrowser
                case 2: firstRule
                default: finish
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 28).padding(.top, 28)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<stepCount, id: \.self) { index in
                        Circle().fill(index == step ? Color.primary : Color.secondary.opacity(0.35)).frame(width: 6, height: 6)
                    }
                }
                .accessibilityElement().accessibilityLabel("Step \(step + 1) of \(stepCount)")
                Spacer()
                if step > 0 { Button("Back") { step -= 1 } }
                if step == 0 { Button("Not Now") { model.completeOnboarding() }.keyboardShortcut(.cancelAction) }
                Button(primaryTitle, action: advance).keyboardShortcut(.defaultAction).nativeProminentButtonStyle()
            }
            .nativeButtonStyle()
            .padding(20)
        }
        .frame(width: 520, height: 440)
        .background(SettingsStyle.content)
        // The window's own alert is hidden behind this sheet.
        .alert("Tern needs your attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var primaryTitle: String {
        switch step {
        case 0: return "Get Started"
        case 1: return model.isDefaultBrowser ? "Continue" : "Skip"
        case 2: return domain.trimmingCharacters(in: .whitespaces).isEmpty ? "Skip" : "Add Rule"
        default: return "Done"
        }
    }

    private func advance() {
        validation = nil
        switch step {
        case 2 where !domain.trimmingCharacters(in: .whitespaces).isEmpty:
            guard addRule() else { return }
            step += 1
        case stepCount - 1:
            model.completeOnboarding()
        default:
            step += 1
        }
    }

    private func header(_ symbol: String, _ color: Color, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 40, height: 40).background(color.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 18)
    }

    private var welcome: some View {
        VStack(alignment: .center, spacing: 14) {
            Image(nsImage: TernAssets.applicationIcon).resizable().frame(width: 96, height: 96).padding(.top, 24)
            Text("Welcome to Tern").font(.system(size: 24, weight: .semibold))
            Text("Tern opens every link in the right browser and profile: work links in your work profile, everything else where you’d expect.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity)
    }

    private var defaultBrowser: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("globe", .blue, "Make Tern Your Default Browser",
                   "Links you click in other apps then come to Tern first. Tern remembers \(model.usualBrowserName ?? "your current browser") so you can switch back anytime.")
            SettingsSection {
                SettingsRow(model.isDefaultBrowser ? "Tern is your default browser" : "Not set up yet",
                            subtitle: model.isDefaultBrowser ? nil : "macOS asks you to confirm") {
                    if model.isDefaultBrowser {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 18))
                    } else {
                        Button("Make Default…") { Task { await model.makeDefault() } }
                    }
                }
            }
        }
    }

    private var firstRule: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("arrow.triangle.branch", .orange, "Where Should Links Go?",
                   "Links that match no rule open in your usual browser. Add a first rule for a site you use for work, or skip this.")
            SettingsSection {
                SettingsRow("Unmatched Links") {
                    DestinationPicker(title: "Unmatched Links", selection: Binding(get: { model.configuration.fallback }, set: { model.setFallback($0) }))
                        .labelsHidden().fixedSize()
                }
            }
            .padding(.bottom, 14)
            SettingsSection("First Rule") {
                SettingsRow("Domain") {
                    TextField("", text: $domain, prompt: Text(verbatim: "github.com"))
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(maxWidth: 220)
                        .onSubmit(advance)
                }
                RowSeparator()
                SettingsRow("Open In") {
                    DestinationPicker(title: "Open In", selection: $destination).labelsHidden().fixedSize()
                }
            }
            if let validation {
                Label(validation, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(.red)
                    .padding(.top, 8).padding(.horizontal, SettingsStyle.rowInset)
            }
        }
        .onAppear { if destination == .ask { destination = model.configuration.fallback } }
    }

    private var finish: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("checkmark", .green, "You’re All Set",
                   "Tern lives in the menu bar. Use New Rule… there or in this window to add more rules, and the Test a Link field to check where a link would go.")
            SettingsSection {
                SettingsRow("Open at Login", subtitle: "Recommended, so links always route instantly") {
                    Toggle("", isOn: Binding(get: { model.opensAtLogin }, set: { model.setOpensAtLogin($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        }
    }

    private func addRule() -> Bool {
        var matcher = URLMatcher(host: domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        if let parsed = URLMatcher.parseDomainInput(domain) {
            matcher.host = parsed.host
            matcher.pathPrefix = parsed.path ?? ""
        }
        let rule = RoutingRule(name: matcher.host, matcher: matcher, destination: destination)
        do {
            try matcher.validate()
            try destination.validate()
            model.save(rule)
            return model.configuration.rules.contains(rule)
        } catch {
            validation = error.localizedDescription
            return false
        }
    }
}

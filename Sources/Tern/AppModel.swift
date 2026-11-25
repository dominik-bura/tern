import AppKit
import ServiceManagement
import SwiftUI

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published private(set) var configuration = RoutingConfiguration()
    @Published var browsers: [InstalledBrowser] = []
    @Published var profiles: [DiaProfileReference] = []
    /// Profiles read from each Chromium-based browser's files, by bundle identifier (includes Dia's metadata).
    @Published private(set) var browserProfiles: [String: [BrowserProfileInfo]] = [:]
    /// Browsers that keep their profile list private and whose profile names Tern hasn't been shown yet.
    @Published private(set) var profileNamesHidden: Set<String> = []
    /// How often each rule opened a link, and when it last did.
    @Published private(set) var ruleUsage: [UUID: RuleUsage] = [:]
    @Published private(set) var opensAtLogin = false
    @Published var showsOnboarding = false
    @Published var error: String?
    @Published var isRefreshing = false
    @Published private(set) var isDefaultBrowser = false
    /// The browser that currently receives external links when Tern is not the default.
    @Published private(set) var currentBrowserName = ""
    @Published private(set) var canRestoreBrowser = false
    /// The browser links open in without Tern, if known.
    var usualBrowserName: String? {
        defaults.systemBrowserID.flatMap { id in browsers.first(where: { $0.id == id })?.name }
    }
    @Published var updateState: UpdateState = .unavailable
    @Published var configurationSection: ConfigurationSection = .rules {
        didSet {
            guard configurationSection != oldValue, !isNavigatingHistory else { return }
            backHistory.append(oldValue)
            forwardHistory.removeAll()
        }
    }
    @Published var editingRule: RoutingRule?
    private var backHistory: [ConfigurationSection] = []
    private var forwardHistory: [ConfigurationSection] = []
    private var isNavigatingHistory = false
    var canGoBack: Bool { !backHistory.isEmpty }
    var canGoForward: Bool { !forwardHistory.isEmpty }

    func goBack() {
        guard let previous = backHistory.popLast() else { return }
        forwardHistory.append(configurationSection)
        isNavigatingHistory = true
        configurationSection = previous
        isNavigatingHistory = false
    }
    func goForward() {
        guard let next = forwardHistory.popLast() else { return }
        backHistory.append(configurationSection)
        isNavigatingHistory = true
        configurationSection = next
        isNavigatingHistory = false
    }
    let dia: DiaService
    let router: RoutingCoordinator
    let defaults = DefaultBrowserService()
    let store: RuleStore
    let updates = UpdateService()
    var showDashboard: (() -> Void)?
    private var storageHealthy = true
    private var updateTask: Task<Void, Never>?

    init(store: RuleStore = RuleStore()) {
        self.store = store
        let dia = DiaService()
        self.dia = dia
        router = RoutingCoordinator(opener: BrowserOpener(dia: dia))
        do { configuration = try store.load(); configuration.normalizeGroups() }
        catch { storageHealthy = false; self.error = "Could not load rules. Your file has been preserved. \(error.localizedDescription)" }
        let updateErrorFile = store.fileURL.deletingLastPathComponent().appendingPathComponent("update-error.txt")
        if let text = try? String(contentsOf: updateErrorFile, encoding: .utf8) {
            error = text
            try? FileManager.default.removeItem(at: updateErrorFile)
        }
        browsers = BrowserRegistry.installed()
        loadBrowserProfiles()
        refreshDefaultStatus()
        adoptSystemBrowserAsFallback()
        ruleUsage = RuleUsage.load()
        opensAtLogin = SMAppService.mainApp.status == .enabled
        router.onOpened = { [weak self] decision in self?.recordUse(of: decision) }
        if updates.repository != nil {
            updateState = .idle
            updateTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.checkForUpdates()
                    try? await Task.sleep(for: .seconds(6 * 60 * 60))
                }
            }
        }
    }
    func commit(_ next: RoutingConfiguration) {
        do {
            guard storageHealthy else { throw TernError.message("Fix or move the preserved rules file and restart Tern before saving changes.") }
            var next = next
            next.normalizeGroups()
            try store.save(next)
            configuration = next
        } catch { self.error = error.localizedDescription }
    }
    func save(_ rule: RoutingRule) {
        var next = configuration
        if let index = next.rules.firstIndex(where: { $0.id == rule.id }) { next.rules[index] = rule }
        else { next.rules.append(rule) }
        commit(next)
    }
    func remember(host: String, destination: BrowserDestination) {
        var next = configuration
        next.rules.insert(RoutingRule(name: host, matcher: URLMatcher(host: host, includeSubdomains: false), destination: destination), at: 0)
        commit(next)
    }
    /// Opens the window on Rules with the editor for a new rule.
    func startNewRule() {
        configurationSection = .rules
        showDashboard?()
        // Present after the window exists so the sheet has a host.
        DispatchQueue.main.async { self.editingRule = RoutingRule() }
    }
    func remove(_ id: UUID) { var next = configuration; next.rules.removeAll { $0.id == id }; commit(next) }
    /// Moves a rule one place up or down within its group.
    func move(_ id: UUID, by offset: Int) {
        var next = configuration
        guard let index = next.rules.firstIndex(where: { $0.id == id }) else { return }
        let group = next.rules[index].group
        let neighbors = next.rules.indices.filter { next.rules[$0].group == group }
        guard let position = neighbors.firstIndex(of: index), neighbors.indices.contains(position + offset) else { return }
        next.rules.swapAt(index, neighbors[position + offset]); commit(next)
    }
    /// Moves a rule into a group, before another rule or to the end of the group.
    func moveRule(_ id: UUID, toGroup group: String?, before target: UUID?) {
        guard id != target else { return }
        var next = configuration
        guard let index = next.rules.firstIndex(where: { $0.id == id }) else { return }
        var rule = next.rules.remove(at: index)
        rule.group = group
        if let target, let targetIndex = next.rules.firstIndex(where: { $0.id == target }) {
            next.rules.insert(rule, at: targetIndex)
        } else if let last = next.rules.lastIndex(where: { $0.group == group }) {
            next.rules.insert(rule, at: last + 1)
        } else {
            next.rules.append(rule)
        }
        commit(next)
    }
    func renameGroup(_ old: String, to new: String) {
        let name = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != old else { return }
        var next = configuration
        for index in next.rules.indices where next.rules[index].group == old { next.rules[index].group = name }
        commit(next)
    }
    /// Removes the group; its rules stay, ungrouped.
    func ungroup(_ group: String) {
        var next = configuration
        for index in next.rules.indices where next.rules[index].group == group { next.rules[index].group = nil }
        commit(next)
    }
    func setGroupEnabled(_ group: String?, _ enabled: Bool) {
        var next = configuration
        for index in next.rules.indices where next.rules[index].group == group { next.rules[index].enabled = enabled }
        commit(next)
    }
    func toggle(_ rule: RoutingRule) { var updated = rule; updated.enabled.toggle(); save(updated) }
    /// Unmatched links open in the user's usual browser instead of asking. Applied once,
    /// so choosing "Ask Every Time" later sticks.
    private func adoptSystemBrowserAsFallback() {
        let key = "adoptedSystemBrowserFallback"
        guard !UserDefaults.standard.bool(forKey: key), storageHealthy else { return }
        guard configuration.fallback == .ask else { UserDefaults.standard.set(true, forKey: key); return }
        guard let id = defaults.systemBrowserID, browsers.contains(where: { $0.id == id }) else { return }
        setFallback(.browser(id))
        if configuration.fallback == .browser(id) { UserDefaults.standard.set(true, forKey: key) }
    }
    func setFallback(_ value: BrowserDestination) { var next = configuration; next.fallback = value; commit(next) }
    func setUnwrapLinks(_ value: Bool) { var next = configuration; next.unwrapLinks = value; commit(next) }
    func setRemoveTracking(_ value: Bool) { var next = configuration; next.removeTracking = value; commit(next) }

    private var intake: Task<Void, Never>?
    /// Cleans links (unwrapping redirects may need the network), then routes them in arrival order.
    func receive(_ urls: [URL], sourceApp: String? = nil) {
        let previous = intake
        intake = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let options = self.configuration
            var cleaned: [URL] = []
            for url in urls {
                cleaned.append(await LinkCleaner.clean(url, unwrap: options.unwrapLinks, removeTracking: options.removeTracking))
            }
            self.router.enqueue(cleaned, sourceApp: sourceApp, configuration: self.configuration)
        }
    }

    private func recordUse(of decision: RoutingDecision) {
        guard let id = decision.ruleID else { return }
        var usage = ruleUsage[id] ?? RuleUsage(count: 0, lastUsed: Date())
        usage.count += 1
        usage.lastUsed = Date()
        ruleUsage[id] = usage
        RuleUsage.save(ruleUsage.filter { key, _ in configuration.rules.contains { $0.id == key } })
    }

    // MARK: Open at login

    func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            self.error = "Couldn’t change Open at Login. \(error.localizedDescription)"
        }
        let status = SMAppService.mainApp.status
        opensAtLogin = status == .enabled
        if enabled, status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    // MARK: Onboarding

    private static let onboardingKey = "completedOnboarding"
    var needsOnboarding: Bool { !UserDefaults.standard.bool(forKey: Self.onboardingKey) && configuration.rules.isEmpty }
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        showsOnboarding = false
    }
    func refreshDestinations() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        browsers = BrowserRegistry.installed()
        loadBrowserProfiles()
        // Dia's names come from its files when available; scripting is the fallback.
        guard profiles.isEmpty, browsers.contains(where: { $0.id == BrowserRegistry.diaID }) else { return }
        do { profiles = try await dia.profiles() }
        catch { self.error = error.localizedDescription }
    }
    func switchProfile(_ profile: DiaProfileReference) async {
        do { try await dia.switchProfile(profile) } catch { self.error = error.localizedDescription }
    }
    func openCurrentPage(in profile: DiaProfileReference) async {
        do {
            let url = try await dia.currentURL()
            try await dia.open(IncomingURLRequest(url: url), profile: profile)
        }
        catch { self.error = error.localizedDescription }
    }
    func openClipboard() {
        guard let value = NSPasteboard.general.string(forType: .string), let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)), IncomingURLRequest.isSupported(url) else {
            error = "The clipboard does not contain an HTTP or HTTPS URL."; return
        }
        receive([url])
    }
    func refreshDefaultStatus() {
        let handlers = defaults.handlers
        isDefaultBrowser = defaults.isDefault
        canRestoreBrowser = defaults.canRestore
        let names = Set(["http", "https"].map { scheme -> String in
            let id = handlers[scheme] ?? ""
            if id == "com.dominikbura.tern.dev" { return "Tern Dev" }
            if id == "com.dominikbura.tern" { return "Tern" }
            return browsers.first(where: { $0.id == id })?.name ?? (id.isEmpty ? "No Browser" : id)
        })
        currentBrowserName = names.sorted().joined(separator: " / ")
    }
    func makeDefault() async {
        adoptSystemBrowserAsFallback()
        do { try await defaults.makeDefault() } catch { self.error = error.localizedDescription }
        refreshDefaultStatus()
    }
    func restoreDefault() async {
        do { try await defaults.restore() } catch { self.error = error.localizedDescription }
        refreshDefaultStatus()
    }
    func importRules() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let next = try RuleStore.decode(Data(contentsOf: url)); commit(next) }
        catch { self.error = error.localizedDescription }
    }
    func exportRules() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Tern-rules.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try RuleStore.encode(configuration).write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
    func checkForUpdates() async {
        guard updates.repository != nil else { return }
        switch updateState { case .checking, .downloading: return; default: break }
        updateState = .checking
        do { if let release = try await updates.checkForUpdate() { updateState = .available(release) } else { updateState = .upToDate(Date()) } }
        catch { updateState = .failed(error.localizedDescription) }
    }
    func installUpdate(_ release: UpdateRelease) async {
        guard router.current == nil, !router.isDelivering, router.queuedCount == 0 else {
            error = "Finish or cancel pending links before installing the update."; return
        }
        updateState = .downloading(release)
        do {
            let service = updates
            let staged = try await Task.detached { try await service.downloadAndStage(release) }.value
            guard router.current == nil else { updateState = .available(release); error = "A link arrived. Finish routing it before updating."; return }
            try updates.launchInstaller(for: staged)
        } catch { updateState = .failed(error.localizedDescription) }
    }
    /// Reads profile lists from disk. This never launches or scripts a browser.
    func loadBrowserProfiles() {
        var result: [String: [BrowserProfileInfo]] = [:]
        var hidden: Set<String> = []
        for browser in browsers where BrowserProfiles.supported[browser.id] != nil {
            switch BrowserProfiles.discover(for: browser.id) {
            case .profiles(let list):
                result[browser.id] = list
            case .restricted(let detected):
                if let cached = BrowserProfiles.cachedProfiles(for: browser.id) {
                    result[browser.id] = cached
                } else {
                    result[browser.id] = detected
                    hidden.insert(browser.id)
                }
            }
        }
        browserProfiles = result
        profileNamesHidden = hidden
        if let dia = result[BrowserRegistry.diaID], !dia.isEmpty {
            profiles = dia.map { DiaProfileReference(name: $0.name) }
        }
    }

    /// For browsers that keep their files private: the person picks the profile list file once,
    /// which lets Tern read it, and Tern remembers the names.
    func chooseProfileList(for browser: InstalledBrowser) {
        guard let folder = BrowserProfiles.dataDirectory(for: browser.id) else { return }
        let fileName = BrowserProfiles.listFileName(for: browser.id)
        let panel = NSOpenPanel()
        panel.directoryURL = folder
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Select “\(fileName)” to show your \(browser.name) profile names. Tern only reads profile names and colors."
        panel.prompt = "Show Profiles"
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard url.lastPathComponent == fileName else {
                throw TernError.message("Select the file named “\(fileName)” in the \(browser.name) folder.")
            }
            let list = try BrowserProfiles.parse(file: url, browserID: browser.id)
            guard !list.isEmpty else { throw TernError.message("No profiles were found in that file.") }
            BrowserProfiles.cache(list, for: browser.id)
            loadBrowserProfiles()
        } catch let error as TernError {
            self.error = error.localizedDescription
        } catch {
            self.error = "Tern couldn’t read that file. \(error.localizedDescription)"
        }
    }

    /// Whether Tern can list and target profiles of this browser.
    func supportsProfiles(_ browser: InstalledBrowser) -> Bool {
        browser.id == BrowserRegistry.diaID || BrowserProfiles.supportsLaunchArguments(browser.id)
    }

    /// The profiles of a browser as routing destinations (empty for browsers without profile support).
    func profileItems(of browser: InstalledBrowser) -> [ProfileItem] {
        if browser.id == BrowserRegistry.diaID {
            let info = browserProfiles[browser.id] ?? []
            return profiles.map { profile in
                let match = info.first { $0.name == profile.name }
                return ProfileItem(destination: .dia(profile), name: profile.name, color: match?.color, pictureURL: match?.pictureURL, canSwitch: true)
            }
        }
        guard BrowserProfiles.supportsLaunchArguments(browser.id) else { return [] }
        return (browserProfiles[browser.id] ?? []).map { info in
            ProfileItem(destination: .profile(ProfileReference(browserID: browser.id, directory: info.directory, name: info.name)),
                        name: info.name, color: info.color, pictureURL: info.pictureURL, canSwitch: false)
        }
    }

    /// Display metadata for a profile destination.
    func profileItem(for destination: BrowserDestination) -> ProfileItem? {
        let browserID: String
        switch destination {
        case .dia: browserID = BrowserRegistry.diaID
        case .profile(let profile): browserID = profile.browserID
        default: return nil
        }
        guard let browser = browsers.first(where: { $0.id == browserID }) else { return nil }
        return profileItems(of: browser).first { $0.destination == destination }
    }
    func destinationName(_ value: BrowserDestination) -> String {
        switch value {
        case .browser(let id): return browsers.first(where: { $0.id == id })?.name ?? "Missing browser (\(id))"
        case .profile(let profile): return "\(browsers.first(where: { $0.id == profile.browserID })?.name ?? profile.browserID) · \(profile.name)"
        default: return value.label
        }
    }

    /// Apps to offer as link sources: apps already used in rules, then running apps.
    func sourceAppCandidates() -> [String] {
        var seen = Set<String>()
        let fromRules = configuration.rules.flatMap(\.matcher.sourceApps)
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .filter { !BrowserRegistry.isTern($0) }
        return (fromRules + running).filter { seen.insert($0).inserted }
            .sorted { AppInfo.name(for: $0).localizedCaseInsensitiveCompare(AppInfo.name(for: $1)) == .orderedAscending }
    }
}

struct RuleUsage: Codable, Equatable {
    var count: Int
    var lastUsed: Date

    private static let key = "ruleUsage"
    static func load() -> [UUID: RuleUsage] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: RuleUsage].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
    }
    static func save(_ usage: [UUID: RuleUsage]) {
        let encoded = Dictionary(uniqueKeysWithValues: usage.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(encoded) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// Names and icons of apps, by bundle identifier.
enum AppInfo {
    static func url(for bundleID: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    static func name(for bundleID: String) -> String {
        guard let url = url(for: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
    static func icon(for bundleID: String) -> NSImage {
        guard let url = url(for: bundleID) else { return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage() }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

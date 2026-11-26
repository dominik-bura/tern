import Foundation
import Combine
import TernUpdateCore

/// Update UX and scheduling; download validation and replacement stay in the existing service/helper.
@MainActor final class UpdateController: ObservableObject {
    @Published private(set) var state: UpdateState
    @Published private(set) var availableRelease: UpdateRelease?
    @Published private(set) var presentedRelease: UpdateRelease?
    @Published private(set) var installationNotice: String?
    @Published var automaticallyInstallsUpdates: Bool {
        didSet {
            guard automaticallyInstallsUpdates != oldValue else { return }
            preferences.set(automaticallyInstallsUpdates, forKey: Self.automaticKey)
            idleSince = nil
            if automaticallyInstallsUpdates { beginAutomaticPreparation() }
        }
    }

    let isConfigured: Bool
    let currentVersion: String
    let buildNumber: String
    // Conservative until AppModel connects the routing/window snapshot.
    var activityProvider: () -> UpdateActivity = { UpdateActivity(hasModalWindow: true) }
    private let execution: UpdateExecution
    private let preferences: UserDefaults
    private var policy: UpdatePromptPolicy
    private var stagedUpdate: (release: UpdateRelease, app: URL)?
    private var manuallyApprovedVersion: String?
    private var failedAutomaticVersion: String?
    private var pendingExplicitPrompt = false
    private var menuIsTracking = false
    private var checkingUpdates = false
    private var idleSince: Date?
    private var checksTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    static let automaticKey = "automaticallyInstallsUpdates.v1"
    static let policyKey = "updatePromptPolicy.v1"

    init(service: UpdateService = UpdateService(), execution: UpdateExecution? = nil,
         preferences: UserDefaults = .standard, startsTimers: Bool = true) {
        self.execution = execution ?? .live(service: service)
        self.preferences = preferences
        isConfigured = execution != nil || service.repository != nil
        currentVersion = service.currentVersion
        buildNumber = service.buildNumber
        state = isConfigured ? .idle : .unavailable
        automaticallyInstallsUpdates = preferences.bool(forKey: Self.automaticKey)
        policy = preferences.data(forKey: Self.policyKey)
            .flatMap { try? JSONDecoder().decode(UpdatePromptPolicy.self, from: $0) } ?? UpdatePromptPolicy()
        if isConfigured, startsTimers {
            checksTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.checkForUpdates()
                    do { try await Task.sleep(for: .seconds(6 * 60 * 60)) } catch { return }
                }
            }
            heartbeatTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    guard let self else { return }
                    self.beginAutomaticPreparation()
                    self.considerAutomaticInstallation()
                    self.considerPrompt()
                }
            }
        }
    }

    deinit { checksTask?.cancel(); heartbeatTask?.cancel(); downloadTask?.cancel() }

    var isDownloading: Bool { if case .downloading = state { return true }; return false }
    var isInstalling: Bool { if case .installing = state { return true }; return false }
    var isReady: Bool { if case .ready = state { return true }; return false }
    var failureMessage: String? { if case let .failed(message) = state { return message }; return nil }
    var restartBlockedReason: String? { activityProvider().restartBlockedReason }
    var canInstall: Bool {
        guard availableRelease != nil, restartBlockedReason == nil else { return false }
        switch state { case .available, .ready, .failed: return true; default: return false }
    }
    var menuTitle: String {
        switch state {
        case .unavailable: return "Updates Unavailable"
        case .checking: return "Checking for Updates…"
        case .downloading: return "Downloading Update…"
        case .installing: return "Restarting to Update…"
        case .ready: return "Update Ready…"
        case .available: return "Update Available…"
        case .failed: return availableRelease == nil ? "Check for Updates…" : "Update Needs Attention…"
        case .idle, .upToDate: return "Check for Updates…"
        }
    }

    func checkForUpdates(showPrompt: Bool = false) async {
        guard isConfigured, !isDownloading, !isInstalling else { return }
        if showPrompt { pendingExplicitPrompt = true }
        guard !checkingUpdates else { return }
        // A check must not replace the release the user is currently approving.
        guard presentedRelease == nil else { return }
        checkingUpdates = true
        defer { checkingUpdates = false }
        if stagedUpdate == nil { state = .checking }
        do {
            let result = try await execution.check()
            guard !isInstalling, !isDownloading else { return }
            if let release = result {
                if availableRelease != release {
                    failedAutomaticVersion = nil
                    stagedUpdate = nil
                }
                availableRelease = release
                state = stagedUpdate?.release == release ? .ready(release) : .available(release)
                beginAutomaticPreparation()
                considerPrompt()
            } else {
                availableRelease = nil
                stagedUpdate = nil
                state = .upToDate(Date())
                pendingExplicitPrompt = false
            }
        } catch {
            guard !isInstalling, !isDownloading else { return }
            state = .failed(error.localizedDescription)
            if availableRelease == nil { pendingExplicitPrompt = false }
            considerPrompt()
        }
    }

    func requestUpdatePrompt() {
        guard isConfigured, !isInstalling else { return }
        pendingExplicitPrompt = true
        if availableRelease != nil { considerPrompt() }
        else { Task { await checkForUpdates(showPrompt: true) } }
    }

    func considerPrompt(now: Date = Date()) {
        guard presentedRelease == nil, !isInstalling, !menuIsTracking, let release = availableRelease else { return }
        if let reason = restartBlockedReason {
            if pendingExplicitPrompt { installationNotice = reason; pendingExplicitPrompt = false }
            return
        }
        let explicit = pendingExplicitPrompt
        guard explicit || (!isDownloading && activityProvider().isInteracting
            && (!automaticallyInstallsUpdates || failureMessage != nil)
            && policy.shouldPresent(version: release.version, now: now)) else { return }
        pendingExplicitPrompt = false
        policy.presented(release.version)
        persistPolicy()
        idleSince = nil
        presentedRelease = release
    }

    func remindTomorrow(_ release: UpdateRelease, now: Date = Date()) {
        policy.remindTomorrow(release.version, now: now)
        persistPolicy()
        dismissPrompt()
    }
    func skipVersion(_ release: UpdateRelease) {
        policy.skip(release.version)
        persistPolicy()
        dismissPrompt()
    }
    func promptClosedByUser(_ release: UpdateRelease) { remindTomorrow(release) }
    private func dismissPrompt() {
        manuallyApprovedVersion = nil
        pendingExplicitPrompt = false
        idleSince = nil
        presentedRelease = nil
    }
    private func persistPolicy() {
        if let data = try? JSONEncoder().encode(policy) { preferences.set(data, forKey: Self.policyKey) }
    }

    /// Every busy edge resets the clock, even if a fast delivery completes between heartbeat ticks.
    func activityDidChange() {
        idleSince = nil
        objectWillChange.send()
        Task { @MainActor [weak self] in
            await Task.yield() // @Published routing notifications are sent before their value changes.
            guard let self else { return }
            if self.installationNotice != nil { self.installationNotice = self.restartBlockedReason }
            self.considerPrompt()
        }
    }
    func setMenuTracking(_ tracking: Bool) {
        menuIsTracking = tracking
        activityDidChange()
    }

    func installUpdate(_ release: UpdateRelease) {
        guard isConfigured, availableRelease == release, !isInstalling else { return }
        guard restartBlockedReason == nil else { installationNotice = restartBlockedReason; return }
        installationNotice = nil
        manuallyApprovedVersion = release.version
        if let stagedUpdate, stagedUpdate.release == release {
            installStagedUpdate(stagedUpdate, automatic: false)
        } else if downloadTask == nil {
            startDownload(release)
        }
    }

    private func beginAutomaticPreparation(now: Date = Date()) {
        guard isConfigured, automaticallyInstallsUpdates, let release = availableRelease,
              case .available = state, downloadTask == nil, stagedUpdate == nil,
              failedAutomaticVersion != release.version,
              policy.allowsAutomaticUpdate(version: release.version, now: now) else { return }
        startDownload(release)
    }

    private func startDownload(_ release: UpdateRelease) {
        guard downloadTask == nil else { return }
        idleSince = nil
        state = .downloading(release)
        let execution = self.execution
        downloadTask = Task { [weak self] in
            do {
                let app = try await execution.download(release)
                guard let self else { return }
                self.downloadTask = nil
                let staged = (release: release, app: app)
                self.stagedUpdate = staged
                self.state = .ready(release)
                if self.manuallyApprovedVersion == release.version {
                    self.manuallyApprovedVersion = nil
                    // A link or editor may have appeared during the download. Keep the verified
                    // update ready, but require a fresh click instead of restarting later by surprise.
                    guard self.restartBlockedReason == nil else {
                        self.installationNotice = self.restartBlockedReason
                        return
                    }
                    self.installStagedUpdate(staged, automatic: false)
                }
            } catch {
                guard let self else { return }
                self.downloadTask = nil
                self.manuallyApprovedVersion = nil
                self.failedAutomaticVersion = release.version
                self.state = .failed("Could not prepare the update: \(error.localizedDescription)")
                self.considerPrompt()
            }
        }
    }

    func considerAutomaticInstallation(now: Date = Date()) {
        guard automaticallyInstallsUpdates, let stagedUpdate, state == .ready(stagedUpdate.release),
              failedAutomaticVersion != stagedUpdate.release.version, presentedRelease == nil,
              policy.allowsAutomaticUpdate(version: stagedUpdate.release.version, now: now),
              !menuIsTracking, activityProvider().permitsAutomaticRestart else {
            idleSince = nil
            return
        }
        guard let since = idleSince else { idleSince = now; return }
        guard now.timeIntervalSince(since) >= 60 else { return }
        installStagedUpdate(stagedUpdate, automatic: true)
    }

    private func installStagedUpdate(_ staged: (release: UpdateRelease, app: URL), automatic: Bool) {
        if automatic {
            guard automaticallyInstallsUpdates, !menuIsTracking, presentedRelease == nil,
                  policy.allowsAutomaticUpdate(version: staged.release.version, now: Date()),
                  activityProvider().permitsAutomaticRestart else { idleSince = nil; return }
        }
        guard availableRelease == staged.release, !isInstalling, restartBlockedReason == nil else {
            manuallyApprovedVersion = nil
            installationNotice = restartBlockedReason
            idleSince = nil
            return
        }
        // No suspension between this last activity check and helper handoff.
        state = .installing(staged.release)
        manuallyApprovedVersion = nil
        idleSince = nil
        do { try execution.install(staged.app, staged.release.version) }
        catch {
            // Never open a browser or activate a window after an automatic failure.
            failedAutomaticVersion = staged.release.version
            if error is InstallationError || (error as? UpdateError) == .invalidApplication
                || (error as? UpdateError) == .invalidSignature {
                stagedUpdate = nil
            }
            state = .failed("Could not install the update: \(error.localizedDescription). Retry from Software Update.")
            if !automatic { considerPrompt() }
        }
    }
}

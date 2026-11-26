import XCTest
import TernUpdateCore
@testable import Tern

private enum FixtureFailure: Error { case download, install }

private actor ReleaseFeed {
    var release: UpdateRelease?
    private(set) var calls = 0
    init(_ release: UpdateRelease?) { self.release = release }
    func check() -> UpdateRelease? { calls += 1; return release }
    func change(to release: UpdateRelease?) { self.release = release }
}

private actor DownloadGate {
    private(set) var calls = 0
    private var continuation: CheckedContinuation<URL, Error>?
    func download(_ release: UpdateRelease) async throws -> URL {
        calls += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(failing: Bool = false) {
        let pending = continuation
        continuation = nil
        if failing { pending?.resume(throwing: FixtureFailure.download) }
        else { pending?.resume(returning: URL(fileURLWithPath: "/fixture/verified/Tern.app")) }
    }
}

@MainActor private final class UpdateFixture {
    static func release(_ version: String = "0.1.2") -> UpdateRelease {
        UpdateRelease(version: version,
                      downloadURL: URL(string: "https://github.com/dominik-bura/tern/releases/download/v\(version)/Tern-\(version).zip")!,
                      checksumURL: nil, digest: "sha256:" + String(repeating: "a", count: 64),
                      releasePageURL: URL(string: "https://github.com/dominik-bura/tern/releases/tag/v\(version)")!)
    }
    final class Context {
        var activity = UpdateActivity()
        var installs: [(URL, String)] = []
        var installError: Error?
    }
    let context = Context()
    let feed: ReleaseFeed
    let gate = DownloadGate()
    let preferences: UserDefaults
    let suite = "TernUpdateTests-\(UUID().uuidString)"
    let model: UpdateController
    let execution: UpdateExecution
    let release: UpdateRelease

    init() {
        release = Self.release()
        feed = ReleaseFeed(release)
        preferences = UserDefaults(suiteName: suite)!
        let feed = self.feed, gate = self.gate, context = self.context
        execution = UpdateExecution(check: { await feed.check() }, download: { try await gate.download($0) },
                                    install: { url, version in
            context.installs.append((url, version))
            if let error = context.installError { throw error }
        })
        model = UpdateController(execution: execution, preferences: preferences, startsTimers: false)
        model.activityProvider = { context.activity }
    }
    func reset() { preferences.removePersistentDomain(forName: suite) }
    func wait(_ predicate: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(3)
        while !(await predicate()) {
            if Date() >= deadline { XCTFail("Timed out waiting for controlled update transition", file: file, line: line); return }
            await Task.yield()
        }
    }
    func prepareAutomatic() async {
        model.automaticallyInstallsUpdates = true
        await model.checkForUpdates()
        await wait { await self.gate.calls == 1 }
        await gate.finish()
        await wait { self.model.isReady }
    }
}

@MainActor final class UpdateControllerTests: XCTestCase {
    func testAutomaticUpdatesAreOffByDefaultAndPreferencePersists() async {
        let f = UpdateFixture(); defer { f.reset() }
        XCTAssertFalse(f.model.automaticallyInstallsUpdates)
        await f.model.checkForUpdates()
        let calls = await f.gate.calls
        XCTAssertEqual(calls, 0)
        f.model.automaticallyInstallsUpdates = true
        XCTAssertTrue(f.preferences.bool(forKey: UpdateController.automaticKey))
        await f.wait { await f.gate.calls == 1 }
        let restarted = UpdateController(execution: f.execution, preferences: f.preferences, startsTimers: false)
        XCTAssertTrue(restarted.automaticallyInstallsUpdates)
        await f.gate.finish(); await f.wait { f.model.isReady }
        XCTAssertTrue(f.context.installs.isEmpty)
    }

    func testBackgroundDiscoveryWaitsForInteractionAndDoesNotRepeatAcrossRestart() async {
        let f = UpdateFixture(); defer { f.reset() }
        await f.model.checkForUpdates()
        XCTAssertEqual(f.model.availableRelease, f.release)
        XCTAssertEqual(f.model.menuTitle, "Update Available…")
        XCTAssertNil(f.model.presentedRelease)
        f.context.activity.isInteracting = true
        f.model.activityDidChange()
        await f.wait { f.model.presentedRelease == f.release }
        let restarted = UpdateController(execution: f.execution, preferences: f.preferences, startsTimers: false)
        restarted.activityProvider = { f.context.activity }
        await restarted.checkForUpdates()
        XCTAssertNil(restarted.presentedRelease)
    }

    func testSkipAndReminderPersistButExplicitReviewAndApprovalStillWork() async {
        for skip in [true, false] {
            let f = UpdateFixture(); defer { f.reset() }
            await f.model.checkForUpdates()
            if skip { f.model.skipVersion(f.release) } else { f.model.remindTomorrow(f.release) }
            let restarted = UpdateController(execution: f.execution, preferences: f.preferences, startsTimers: false)
            restarted.activityProvider = { UpdateActivity(isInteracting: true) }
            await restarted.checkForUpdates()
            XCTAssertNil(restarted.presentedRelease)
            restarted.requestUpdatePrompt()
            XCTAssertEqual(restarted.presentedRelease, f.release)
            restarted.installUpdate(f.release)
            await f.wait { await f.gate.calls == 1 }
            await f.gate.finish()
            await f.wait { f.context.installs.count == 1 }
            XCTAssertEqual(f.context.installs.first?.1, f.release.version)
        }
    }

    func testAutomaticPreparationStaysQuietAndRequiresFullIdleMinute() async {
        let f = UpdateFixture(); defer { f.reset() }
        await f.prepareAutomatic()
        XCTAssertNil(f.model.presentedRelease)
        XCTAssertEqual(f.model.menuTitle, "Update Ready…")
        let t = Date()
        f.model.considerAutomaticInstallation(now: t)
        f.model.considerAutomaticInstallation(now: t.addingTimeInterval(59))
        XCTAssertTrue(f.context.installs.isEmpty)
        f.model.considerAutomaticInstallation(now: t.addingTimeInterval(60))
        f.model.considerAutomaticInstallation(now: t.addingTimeInterval(120))
        XCTAssertEqual(f.context.installs.count, 1)
        XCTAssertEqual(f.context.installs.first?.1, "0.1.2")
        XCTAssertTrue(f.model.isInstalling)
    }

    func testEveryBusyConditionDefersAutomaticRestart() async {
        let blockers: [UpdateActivity] = [
            .init(incomingLinks: 1), .init(queuedLinks: 1), .init(hasPendingLink: true),
            .init(isDelivering: true), .init(isPickerOpen: true), .init(isEditingRules: true),
            .init(isManagingRulesFile: true), .init(isOnboarding: true), .init(hasModalWindow: true),
            .init(hasVisibleWindows: true), .init(isAppActive: true), .init(isInteracting: true)
        ]
        for activity in blockers {
            let f = UpdateFixture(); defer { f.reset() }
            await f.prepareAutomatic()
            let t = Date()
            f.model.considerAutomaticInstallation(now: t)
            f.context.activity = activity
            f.model.activityDidChange()
            f.model.considerAutomaticInstallation(now: t.addingTimeInterval(120))
            XCTAssertTrue(f.context.installs.isEmpty, "Must defer for \(activity)")
            f.context.activity = UpdateActivity()
            f.model.activityDidChange()
            f.model.considerAutomaticInstallation(now: t.addingTimeInterval(200))
            f.model.considerAutomaticInstallation(now: t.addingTimeInterval(259))
            XCTAssertTrue(f.context.installs.isEmpty)
            f.model.considerAutomaticInstallation(now: t.addingTimeInterval(260))
            XCTAssertEqual(f.context.installs.count, 1)
        }
    }

    func testMenuInteractionAndShortLinkBurstsResetContinuousIdleTime() async {
        let f = UpdateFixture(); defer { f.reset() }
        await f.prepareAutomatic()
        let t = Date()
        f.model.considerAutomaticInstallation(now: t)
        f.model.setMenuTracking(true)
        f.model.considerAutomaticInstallation(now: t.addingTimeInterval(100))
        XCTAssertTrue(f.context.installs.isEmpty)
        f.model.setMenuTracking(false)
        f.model.considerAutomaticInstallation(now: t.addingTimeInterval(110))
        // Entire burst fits between heartbeat ticks; both edges still invalidate idle time.
        f.context.activity.incomingLinks = 1; f.model.activityDidChange()
        f.context.activity.incomingLinks = 0; f.model.activityDidChange()
        f.model.considerAutomaticInstallation(now: t.addingTimeInterval(160))
        f.model.considerAutomaticInstallation(now: t.addingTimeInterval(219))
        XCTAssertTrue(f.context.installs.isEmpty)
        f.model.considerAutomaticInstallation(now: t.addingTimeInterval(220))
        XCTAssertEqual(f.context.installs.count, 1)
    }

    func testTurningOffDuringDownloadKeepsVerifiedManualUpdate() async {
        let f = UpdateFixture(); defer { f.reset() }
        f.model.automaticallyInstallsUpdates = true
        await f.model.checkForUpdates(); await f.wait { await f.gate.calls == 1 }
        f.model.automaticallyInstallsUpdates = false
        await f.gate.finish(); await f.wait { f.model.isReady }
        f.model.considerAutomaticInstallation(now: Date().addingTimeInterval(3600))
        XCTAssertTrue(f.context.installs.isEmpty)
        f.model.installUpdate(f.release)
        XCTAssertEqual(f.context.installs.count, 1)
        let calls = await f.gate.calls
        XCTAssertEqual(calls, 1)
    }

    func testPreparedUpdateRespectsReminderAndSkip() async {
        for skip in [true, false] {
            let f = UpdateFixture(); defer { f.reset() }
            await f.prepareAutomatic()
            let t = Date()
            f.model.considerAutomaticInstallation(now: t)
            if skip { f.model.skipVersion(f.release) }
            else { f.model.remindTomorrow(f.release, now: t) }
            f.model.considerAutomaticInstallation(now: t.addingTimeInterval(120))
            f.model.considerAutomaticInstallation(now: t.addingTimeInterval(240))
            XCTAssertTrue(f.context.installs.isEmpty)
            XCTAssertTrue(f.model.isReady)
            // These choices suppress automatic restarts, but explicit approval still works.
            f.model.requestUpdatePrompt()
            f.model.installUpdate(f.release)
            XCTAssertEqual(f.context.installs.count, 1)
        }
    }

    func testOptingOutAndBackInRequiresANewIdleMinute() async {
        let f = UpdateFixture(); defer { f.reset() }
        await f.prepareAutomatic()
        let t = Date()
        f.model.considerAutomaticInstallation(now: t)
        f.model.automaticallyInstallsUpdates = false
        f.model.considerAutomaticInstallation(now: t.addingTimeInterval(120))
        XCTAssertTrue(f.context.installs.isEmpty)
        f.model.automaticallyInstallsUpdates = true
        f.model.considerAutomaticInstallation(now: t.addingTimeInterval(200))
        f.model.considerAutomaticInstallation(now: t.addingTimeInterval(259))
        XCTAssertTrue(f.context.installs.isEmpty)
        f.model.considerAutomaticInstallation(now: t.addingTimeInterval(260))
        XCTAssertEqual(f.context.installs.count, 1)
    }

    func testManualDownloadRechecksAllCriticalWorkBeforeHelperHandoff() async {
        for activity in [UpdateActivity(incomingLinks: 1), .init(queuedLinks: 1), .init(hasPendingLink: true),
                         .init(isDelivering: true), .init(isPickerOpen: true), .init(isEditingRules: true),
                         .init(isManagingRulesFile: true), .init(isOnboarding: true), .init(hasModalWindow: true)] {
            let f = UpdateFixture(); defer { f.reset() }
            await f.model.checkForUpdates()
            f.model.installUpdate(f.release)
            await f.wait { await f.gate.calls == 1 }
            f.context.activity = activity
            await f.gate.finish(); await f.wait { f.model.isReady }
            XCTAssertTrue(f.context.installs.isEmpty, "Must recheck \(activity) after download")
            XCTAssertNotNil(f.model.installationNotice)
            f.context.activity = UpdateActivity(); f.model.activityDidChange()
            await f.wait { f.model.installationNotice == nil }
            XCTAssertTrue(f.context.installs.isEmpty, "Finishing a link does not silently revive manual approval")
            f.model.installUpdate(f.release)
            XCTAssertEqual(f.context.installs.count, 1)
        }
    }

    func testManualInstallWhileEditingNeverDownloads() async {
        let f = UpdateFixture(); defer { f.reset() }
        await f.model.checkForUpdates()
        f.context.activity.isEditingRules = true
        f.model.installUpdate(f.release)
        let calls = await f.gate.calls
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(f.model.canInstall)
        XCTAssertNotNil(f.model.installationNotice)
    }

    func testChecksDoNotDuplicateDownloadOrDiscardStagedVersion() async {
        let f = UpdateFixture(); defer { f.reset() }
        f.model.automaticallyInstallsUpdates = true
        await f.model.checkForUpdates(); await f.wait { await f.gate.calls == 1 }
        await f.model.checkForUpdates()
        let before = await f.feed.calls
        XCTAssertEqual(before, 1)
        await f.gate.finish(); await f.wait { f.model.isReady }
        await f.model.checkForUpdates()
        XCTAssertTrue(f.model.isReady)
        let calls = await f.gate.calls
        XCTAssertEqual(calls, 1)
    }

    func testSkippingPreparedVersionDoesNotHideANewerRelease() async {
        let f = UpdateFixture(); defer { f.reset() }
        await f.prepareAutomatic()
        f.model.skipVersion(f.release)
        let newer = UpdateFixture.release("0.1.3")
        await f.feed.change(to: newer)
        await f.model.checkForUpdates()
        await f.wait { await f.gate.calls == 2 }
        await f.gate.finish(); await f.wait { f.model.state == .ready(newer) }
        f.model.installUpdate(newer)
        XCTAssertEqual(f.context.installs.first?.1, "0.1.3")
    }

    func testDownloadFailureStaysVisibleAndDoesNotRetryAutomatically() async {
        let f = UpdateFixture(); defer { f.reset() }
        f.model.automaticallyInstallsUpdates = true
        await f.model.checkForUpdates(); await f.wait { await f.gate.calls == 1 }
        await f.gate.finish(failing: true)
        await f.wait { f.model.failureMessage != nil }
        XCTAssertEqual(f.model.availableRelease, f.release)
        await f.model.checkForUpdates()
        f.model.considerAutomaticInstallation(now: Date().addingTimeInterval(3600))
        let before = await f.gate.calls
        XCTAssertEqual(before, 1)
        XCTAssertTrue(f.context.installs.isEmpty)
        f.model.installUpdate(f.release)
        await f.wait { await f.gate.calls == 2 }
        await f.gate.finish(); await f.wait { f.context.installs.count == 1 }
    }

    func testInstallationFailureRequiresExplicitRetryAndReusesStage() async {
        let f = UpdateFixture(); defer { f.reset() }
        await f.prepareAutomatic()
        f.context.installError = FixtureFailure.install
        let t = Date()
        f.model.considerAutomaticInstallation(now: t)
        f.model.considerAutomaticInstallation(now: t.addingTimeInterval(60))
        XCTAssertNotNil(f.model.failureMessage)
        f.model.considerAutomaticInstallation(now: t.addingTimeInterval(3600))
        XCTAssertEqual(f.context.installs.count, 1)
        f.context.installError = nil
        f.model.installUpdate(f.release)
        XCTAssertEqual(f.context.installs.count, 2)
        let calls = await f.gate.calls
        XCTAssertEqual(calls, 1)
    }

    func testInvalidStagingRequiresFreshDownloadBeforeRetry() async {
        let f = UpdateFixture(); defer { f.reset() }
        await f.prepareAutomatic()
        f.context.installError = InstallationError.invalidSignature
        f.model.installUpdate(f.release)
        XCTAssertNotNil(f.model.failureMessage)
        f.context.installError = nil
        f.model.installUpdate(f.release)
        await f.wait { await f.gate.calls == 2 }
        await f.gate.finish(); await f.wait { f.context.installs.count == 2 }
    }

    func testRemindDuringManualDownloadWithdrawsRestartApproval() async {
        let f = UpdateFixture(); defer { f.reset() }
        await f.model.checkForUpdates()
        f.model.installUpdate(f.release)
        await f.wait { await f.gate.calls == 1 }
        f.model.remindTomorrow(f.release)
        await f.gate.finish(); await f.wait { f.model.isReady }
        XCTAssertTrue(f.context.installs.isEmpty)
    }
}

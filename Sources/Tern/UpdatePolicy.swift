import Foundation

struct UpdatePromptPolicy: Codable, Equatable {
    var lastPresentedVersion: String?
    var skippedVersion: String?
    var reminderVersion: String?
    var remindAfter: Date?

    func allowsAutomaticUpdate(version: String, now: Date) -> Bool {
        skippedVersion != version && (reminderVersion != version || remindAfter.map { now >= $0 } != false)
    }

    func shouldPresent(version: String, now: Date) -> Bool {
        guard allowsAutomaticUpdate(version: version, now: now) else { return false }
        if reminderVersion == version, let remindAfter { return now >= remindAfter }
        return lastPresentedVersion != version
    }

    mutating func presented(_ version: String) {
        lastPresentedVersion = version
        if reminderVersion == version { reminderVersion = nil; remindAfter = nil }
    }

    mutating func remindTomorrow(_ version: String, now: Date) {
        if skippedVersion == version { skippedVersion = nil }
        reminderVersion = version
        remindAfter = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
    }

    mutating func skip(_ version: String) {
        skippedVersion = version
        if reminderVersion == version { reminderVersion = nil; remindAfter = nil }
    }
}

/// Snapshot read synchronously again immediately before handing off to the helper.
struct UpdateActivity: Equatable {
    var incomingLinks = 0
    var queuedLinks = 0
    var hasPendingLink = false
    var isDelivering = false
    var isPickerOpen = false
    var isEditingRules = false
    var isManagingRulesFile = false
    var isOnboarding = false
    var hasModalWindow = false
    var hasVisibleWindows = false
    var isAppActive = false
    var isInteracting = false

    var restartBlockedReason: String? {
        if incomingLinks > 0 { return "Finish resolving incoming links before updating." }
        if queuedLinks > 0 || hasPendingLink || isDelivering || isPickerOpen {
            return "Finish or cancel pending links before updating."
        }
        if isEditingRules { return "Finish editing your rule before updating." }
        if isManagingRulesFile || hasModalWindow { return "Close the open dialog before updating." }
        if isOnboarding { return "Finish the welcome guide before updating." }
        return nil
    }

    var permitsAutomaticRestart: Bool {
        restartBlockedReason == nil && !hasVisibleWindows && !isAppActive && !isInteracting
    }
}

struct UpdateExecution: Sendable {
    var check: @Sendable () async throws -> UpdateRelease?
    var download: @Sendable (UpdateRelease) async throws -> URL
    var install: @MainActor @Sendable (URL, String) throws -> Void

    static func live(service: UpdateService) -> Self {
        Self(check: { try await service.checkForUpdate() },
             download: { try await service.downloadAndStage($0) },
             install: { try service.launchInstaller(for: $0, expectedVersion: $1) })
    }
}

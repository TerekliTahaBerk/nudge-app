import Foundation
import UserNotifications

// MARK: - NotificationScheduler
// Wraps UNUserNotificationCenter.  All scheduling, cancellation, and
// action handling happens here so the rest of the app stays decoupled.

@MainActor
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationScheduler()

    // Notification action identifiers
    static let doneActionID   = "JGR_DONE"
    static let laterActionID  = "JGR_LATER"
    static let categoryID     = "JGR_NUDGE"

    // Callback invoked on the main actor when user acts on a notification.
    var onNudgeDone:  ((UUID) -> Void)?
    var onNudgeLater: ((UUID) -> Void)?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    // ── MARK: Permission ──────────────────────────────────────────────────────

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    var isAuthorized: Bool {
        get async {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return settings.authorizationStatus == .authorized
        }
    }

    // ── MARK: Schedule a nudge ────────────────────────────────────────────────

    func scheduleNudge(for reminder: Reminder, settings: AppSettings) async {
        guard await isAuthorized else { return }
        guard !reminder.isDone else { return }

        let totalSent = 0   // conservative: let the engine compute without cap for scheduling
        let fireDate  = reminder.nextNudgeAt ?? AdaptiveEngine.nextNudgeDate(
            for: reminder, settings: settings, dailyTotalSent: totalSent
        )
        guard fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title           = "A small nudge"
        content.body            = AdaptiveEngine.nudgeBody(for: reminder)
        content.sound           = .default
        content.categoryIdentifier = Self.categoryID
        content.userInfo        = ["reminderId": reminder.id.uuidString]

        let comps   = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: reminder.id.uuidString,
            content: content,
            trigger: trigger
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    // Convenience: schedule all non-done reminders.
    func scheduleAll(_ reminders: [Reminder], settings: AppSettings) async {
        for reminder in reminders where !reminder.isDone {
            await scheduleNudge(for: reminder, settings: settings)
        }
    }

    // ── MARK: Cancellation ────────────────────────────────────────────────────

    func cancel(reminderId: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminderId.uuidString])
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // ── MARK: Pending count ───────────────────────────────────────────────────

    func pendingCount() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests().count
    }

    // ── MARK: UNUserNotificationCenterDelegate ────────────────────────────────

    // Show notifications even when app is in foreground (as a banner).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // We handle in-app nudges ourselves; suppress system banner when foregrounded.
        return []
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let idString = response.notification.request.content.userInfo["reminderId"] as? String,
              let id = UUID(uuidString: idString) else { return }

        await MainActor.run {
            switch response.actionIdentifier {
            case Self.doneActionID:
                onNudgeDone?(id)
            case Self.laterActionID, UNNotificationDismissActionIdentifier:
                onNudgeLater?(id)
            default:
                break   // tapping the notification body opens the app
            }
        }
    }

    // ── MARK: Private ─────────────────────────────────────────────────────────

    private func registerCategories() {
        let doneAction = UNNotificationAction(
            identifier: Self.doneActionID,
            title: "Done",
            options: [.foreground]
        )
        let laterAction = UNNotificationAction(
            identifier: Self.laterActionID,
            title: "Later",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [doneAction, laterAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

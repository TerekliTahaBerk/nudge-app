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
    var onNudgeOpened: ((UUID) -> Void)?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    // ── MARK: Permission ──────────────────────────────────────────────────────

    nonisolated static func requestID(for reminderId: UUID) -> String {
        "JGR_REMINDER_\(reminderId.uuidString)"
    }

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

    func scheduleNudge(for reminder: Reminder, settings: AppSettings, allReminders: [Reminder]? = nil) async {
        guard await isAuthorized else { return }
        guard !reminder.isDone else { return }

        let result = NotificationPlanner.plan(
            for: reminder,
            context: NudgeDecisionContext(allReminders: allReminders ?? [reminder], settings: settings)
        )
        let fireDate = reminder.nextNudgeAt ?? result.plan?.nextFireDate
        guard result.status == .scheduled || reminder.nextNudgeAt != nil else {
            DebugLog.notification("Skipped \(reminder.id): \(result.status.rawValue) - \(result.explanation.text)")
            return
        }
        guard let fireDate, fireDate > .now else {
            DebugLog.notification("Skipped \(reminder.id): no future fire date")
            return
        }

        let content = UNMutableNotificationContent()
        content.title           = "A small nudge"
        content.body            = NotificationPlanner.calmCopy(for: reminder)
        content.sound           = .default
        content.categoryIdentifier = Self.categoryID
        content.userInfo        = ["reminderId": reminder.id.uuidString]

        let comps   = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let requestID = Self.requestID(for: reminder.id)
        let request = UNNotificationRequest(
            identifier: requestID,
            content: content,
            trigger: trigger
        )

        cancel(reminderId: reminder.id)
        do {
            try await UNUserNotificationCenter.current().add(request)
            DebugLog.notification("Scheduled \(requestID) at \(fireDate)")
        } catch {
            DebugLog.notification("Failed scheduling \(requestID): \(error.localizedDescription)")
        }
    }

    // Convenience: schedule all non-done reminders.
    func scheduleAll(_ reminders: [Reminder], settings: AppSettings) async {
        for reminder in reminders where !reminder.isDone {
            await scheduleNudge(for: reminder, settings: settings, allReminders: reminders)
        }
    }

    // ── MARK: Cancellation ────────────────────────────────────────────────────

    func cancel(reminderId: UUID) {
        let requestID = Self.requestID(for: reminderId)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [requestID])
        DebugLog.notification("Cancelled \(requestID)")
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // ── MARK: Pending count ───────────────────────────────────────────────────

    func pendingCount() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests().count
    }

    // ── MARK: UNUserNotificationCenterDelegate ────────────────────────────────

    // Show notifications even when app is in foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
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
                onNudgeOpened?(id)
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
            title: "Maybe later",
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

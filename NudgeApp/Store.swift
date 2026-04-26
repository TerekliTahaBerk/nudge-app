import Foundation

// MARK: - Store
// Persists reminders and settings as JSON in the app's Documents directory.
// Fast, synchronous reads; background writes via async Task.

enum Store {

    private static let remindersURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("reminders.json")
    }()

    private static let settingsURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("settings.json")
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // ── MARK: Reminders ───────────────────────────────────────────────────────

    static func loadReminders() -> [Reminder] {
        guard let data = try? Data(contentsOf: remindersURL),
              let reminders = try? decoder.decode([Reminder].self, from: data) else {
            return []
        }
        return refreshDailyStatus(reminders)
    }

    static func saveReminders(_ reminders: [Reminder]) {
        Task.detached(priority: .background) {
            guard let data = try? encoder.encode(reminders) else { return }
            try? data.write(to: remindersURL, options: .atomic)
        }
    }

    // ── MARK: Settings ────────────────────────────────────────────────────────

    static func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? decoder.decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    static func saveSettings(_ settings: AppSettings) {
        Task.detached(priority: .background) {
            guard let data = try? encoder.encode(settings) else { return }
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    // ── MARK: Daily Reset ─────────────────────────────────────────────────────
    // Resets `isDone` for repeating reminders if they were completed on a prior day.

    static func refreshDailyStatus(_ reminders: [Reminder]) -> [Reminder] {
        let today = Calendar.current.startOfDay(for: .now)
        let todayStr = ISO8601DateFormatter().string(from: today).prefix(10).description

        return reminders.map { r in
            guard r.isRepeating, r.isDone,
                  let doneDate = r.doneDate, doneDate < todayStr else { return r }
            var updated = r
            updated.isDone   = false
            updated.doneDate = nil
            return updated
        }
    }
}

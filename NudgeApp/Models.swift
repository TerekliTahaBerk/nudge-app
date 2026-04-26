import Foundation

// MARK: - Category

enum ReminderCategory: String, Codable, CaseIterable, Hashable {
    case body, move, mind, grow, none

    var displayName: String {
        switch self {
        case .body: return "body"
        case .move: return "move"
        case .mind: return "mind"
        case .grow: return "grow"
        case .none: return ""
        }
    }

    // Default nudge frequency for this category when no prior data exists.
    var defaultFrequency: FrequencyPreference {
        switch self {
        case .body:  return .smart   // water/break → smart (2–3× day)
        case .move:  return .daily   // movement → once a day
        case .mind:  return .daily   // mindfulness → once a day
        case .grow:  return .weekly  // learning/growth → few times a week
        case .none:  return .smart
        }
    }

    // Preferred time windows for each category.
    var defaultHours: [Int] {
        switch self {
        case .body:  return [9, 12, 15, 18]   // throughout day
        case .move:  return [7, 12, 17]        // morning / lunch / after work
        case .mind:  return [8, 21]            // morning / evening
        case .grow:  return [9, 14]            // morning / afternoon
        case .none:  return [10, 14, 18]
        }
    }
}

// MARK: - Frequency

enum FrequencyPreference: String, Codable, CaseIterable {
    case smart      // "Leave it to me"
    case daily      // "Once a day"
    case weekly     // "A few times a week"
    case occasional // "Now and then"

    var label: String {
        switch self {
        case .smart:      return "Leave it to me"
        case .daily:      return "Once a day"
        case .weekly:     return "A few times a week"
        case .occasional: return "Now and then"
        }
    }

    var hint: String? {
        switch self {
        case .smart: return "recommended"
        case .daily: return "evening"
        default:     return nil
        }
    }

    // Max nudges per day allowed by this preference.
    var maxDailyNudges: Int {
        switch self {
        case .smart:      return 3
        case .daily:      return 1
        case .weekly:     return 1   // not every day
        case .occasional: return 1
        }
    }
}

// MARK: - Time Preference

enum TimePreference: String, Codable {
    case morning, evening, flexible

    var preferredHours: [Int] {
        switch self {
        case .morning:  return [7, 8, 9, 10]
        case .evening:  return [18, 19, 20, 21]
        case .flexible: return [9, 12, 15, 18]
        }
    }
}

// MARK: - Interaction

enum InteractionType: String, Codable {
    case completed  // +2
    case skipped    // -1
    case ignored    // -2
}

struct Interaction: Codable, Identifiable {
    let id: UUID
    let type: InteractionType
    let timestamp: Date

    init(type: InteractionType, at timestamp: Date = .now) {
        self.id        = UUID()
        self.type      = type
        self.timestamp = timestamp
    }
}

// MARK: - Reminder

struct Reminder: Identifiable, Codable {
    let id: UUID
    var text: String
    var category: ReminderCategory
    var frequency: FrequencyPreference
    var timePreference: TimePreference
    var isRepeating: Bool      // resets `isDone` each day
    var dueDate: Date?

    var isDone: Bool
    var doneDate: String?      // ISO-8601 date string for daily reset
    var hasGap: Bool           // visual breathing room above this row

    var interactions: [Interaction]
    var nextNudgeAt: Date?
    var pausedUntil: Date?

    let createdAt: Date

    // Adaptive score — read-only, always fresh from interactions.
    var effectivenessScore: Double {
        AdaptiveEngine.score(for: interactions)
    }

    // Today-only nudge count for this reminder.
    var todayNudgeCount: Int {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return interactions.filter { $0.timestamp >= startOfDay }.count
    }

    // MARK: Init

    init(
        text: String,
        category: ReminderCategory = .none,
        frequency: FrequencyPreference = .smart,
        timePreference: TimePreference = .flexible,
        isRepeating: Bool = false,
        dueDate: Date? = nil,
        hasGap: Bool = false
    ) {
        self.id             = UUID()
        self.text           = text
        self.category       = category
        self.frequency      = frequency
        self.timePreference = timePreference
        self.isRepeating    = isRepeating
        self.dueDate        = dueDate
        self.isDone         = false
        self.doneDate       = nil
        self.hasGap         = hasGap
        self.interactions   = []
        self.nextNudgeAt    = nil
        self.pausedUntil    = nil
        self.createdAt      = .now
    }

    // MARK: Seed reminders for first launch

    static func seedReminders() -> [Reminder] {
        [
            Reminder(text: "Drink some water",            category: .body, frequency: .smart, isRepeating: true,  hasGap: false),
            Reminder(text: "Take a short break",          category: .body, frequency: .smart, isRepeating: false, hasGap: false),
            Reminder(text: "Step outside for a moment",   category: .move, frequency: .daily, isRepeating: false, hasGap: true),
            Reminder(text: "Breathe deeply for a minute", category: .mind, frequency: .daily, isRepeating: true,  hasGap: false),
        ]
    }
}

// MARK: - Settings

enum NotificationLevel: String, Codable, CaseIterable {
    case low, medium, high

    var maxDailyNudgesGlobal: Int {
        switch self { case .low: return 2; case .medium: return 4; case .high: return 6 }
    }

    var label: String { rawValue.capitalized }
}

struct AppSettings: Codable {
    var userName: String               = ""
    var onboarded: Bool                = false
    var notificationLevel: NotificationLevel = .medium
    var smartTimingEnabled: Bool       = true
    var quietHoursStart: Int           = 23   // 23:00
    var quietHoursEnd: Int             = 8    // 08:00
}

// MARK: - Text Analysis Result

struct TextAnalysis {
    let category: ReminderCategory
    let suggestedFrequency: FrequencyPreference
    let suggestedTimePreference: TimePreference
    let isHabit: Bool
    let confidence: Double   // 0–1
}

// MARK: - Active Nudge (in-app banner)

struct ActiveNudge: Identifiable {
    let id = UUID()
    let reminderId: UUID
    let body: String
    let category: ReminderCategory
}

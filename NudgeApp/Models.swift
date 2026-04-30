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

// MARK: - Reminder Kind (type)

enum ReminderType: String, Codable, CaseIterable {
    case standard, trigger, voice, linked, oneoff

    var label: String {
        switch self {
        case .standard: return "A reminder"
        case .trigger:  return "When something happens"
        case .voice:    return "In my own voice"
        case .linked:   return "After another"
        case .oneoff:   return "Just for today"
        }
    }

    var hint: String {
        switch self {
        case .standard: return "text + timing"
        case .trigger:  return "a moment or a place"
        case .voice:    return "5 seconds, on-device"
        case .linked:   return "follows on"
        case .oneoff:   return "one-off"
        }
    }
}

// Trigger payload — a "moment" (device event) or a "place" (geofence) or freeform.
struct TriggerInfo: Codable, Hashable {
    enum Kind: String, Codable { case moment, place, custom }
    var kind: Kind
    var id: String?     // canonical id e.g. "open_laptop"
    var label: String   // human-readable
}

// Voice payload — a tiny recording. We store duration + sampled waveform
// (samples are 0…1 floats used to redraw the waveform).
struct VoiceInfo: Codable, Hashable {
    var duration: Double
    var samples: [Double]
}

// Linked payload — fires after another reminder is checked, with a delay.
struct LinkInfo: Codable, Hashable {
    var parentId: UUID
    var delayMin: Int
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

    // Reminder kind — standard by default. Non-standard kinds carry payloads.
    var type: ReminderType = .standard
    var trigger: TriggerInfo?
    var voice: VoiceInfo?
    var link: LinkInfo?

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
        self.type           = .standard
        self.trigger        = nil
        self.voice          = nil
        self.link           = nil
        self.createdAt      = .now
    }

    // Custom decoder so reminders saved before kind/trigger/voice/link existed
    // continue to decode (missing keys default to standard/nil).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id             = try c.decode(UUID.self, forKey: .id)
        self.text           = try c.decode(String.self, forKey: .text)
        self.category       = try c.decode(ReminderCategory.self, forKey: .category)
        self.frequency      = try c.decode(FrequencyPreference.self, forKey: .frequency)
        self.timePreference = try c.decode(TimePreference.self, forKey: .timePreference)
        self.isRepeating    = try c.decode(Bool.self, forKey: .isRepeating)
        self.dueDate        = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        self.isDone         = try c.decode(Bool.self, forKey: .isDone)
        self.doneDate       = try c.decodeIfPresent(String.self, forKey: .doneDate)
        self.hasGap         = try c.decode(Bool.self, forKey: .hasGap)
        self.interactions   = try c.decode([Interaction].self, forKey: .interactions)
        self.nextNudgeAt    = try c.decodeIfPresent(Date.self, forKey: .nextNudgeAt)
        self.pausedUntil    = try c.decodeIfPresent(Date.self, forKey: .pausedUntil)
        self.type           = try c.decodeIfPresent(ReminderType.self, forKey: .type) ?? .standard
        self.trigger        = try c.decodeIfPresent(TriggerInfo.self, forKey: .trigger)
        self.voice          = try c.decodeIfPresent(VoiceInfo.self, forKey: .voice)
        self.link           = try c.decodeIfPresent(LinkInfo.self, forKey: .link)
        self.createdAt      = try c.decode(Date.self, forKey: .createdAt)
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

    // "Read my rhythm" — Behavior layer. On by default; reads interactions to
    // bias future nudge times. Stays on this device.
    var receptivityEnabled: Bool       = true
    // Set true after the user dismisses the eased-back banner; cleared the
    // next time the engine eases back again.
    var easedBackAcknowledged: Bool    = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.userName              = try c.decodeIfPresent(String.self, forKey: .userName) ?? ""
        self.onboarded             = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        self.notificationLevel     = try c.decodeIfPresent(NotificationLevel.self, forKey: .notificationLevel) ?? .medium
        self.smartTimingEnabled    = try c.decodeIfPresent(Bool.self, forKey: .smartTimingEnabled) ?? true
        self.quietHoursStart       = try c.decodeIfPresent(Int.self, forKey: .quietHoursStart) ?? 23
        self.quietHoursEnd         = try c.decodeIfPresent(Int.self, forKey: .quietHoursEnd) ?? 8
        self.receptivityEnabled    = try c.decodeIfPresent(Bool.self, forKey: .receptivityEnabled) ?? true
        self.easedBackAcknowledged = try c.decodeIfPresent(Bool.self, forKey: .easedBackAcknowledged) ?? false
    }
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

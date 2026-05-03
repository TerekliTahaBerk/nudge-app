import Foundation

// MARK: - Category

enum ReminderCategory: String, Codable, CaseIterable, Hashable {
    case body, move, mind, grow, social, task, errand, health, home, work, none

    var displayName: String {
        switch self {
        case .body: return "body"
        case .move: return "move"
        case .mind: return "mind"
        case .grow: return "grow"
        case .social: return "social"
        case .task: return "task"
        case .errand: return "errand"
        case .health: return "health"
        case .home: return "home"
        case .work: return "work"
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
        case .social: return .weekly
        case .task: return .smart
        case .errand: return .weekly
        case .health: return .smart
        case .home: return .weekly
        case .work: return .smart
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
        case .social: return [18, 19, 20]
        case .task: return [10, 14, 17]
        case .errand: return [11, 15, 18]
        case .health: return [8, 12, 18]
        case .home: return [18, 20]
        case .work: return [9, 11, 14]
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

enum ReminderKind: String, Codable, Equatable {
    case timeBased = "time_based"
    case eventBased = "event_based"
    case voice
    case followOn = "follow_on"
    case oneOff = "one_off"
}

enum SuggestedCadence: String, Codable, Equatable {
    case smartGentle = "smart_gentle"
    case daily
    case fewTimesPerWeek = "few_times_per_week"
    case occasional
    case oneOff = "one_off"
}

enum ReminderIntent: String, Codable, Hashable {
    case remind
    case call
    case send
    case drink
    case move
    case household
    case errand
    case unknown
}

enum ReminderUrgency: String, Codable, Hashable {
    case low, normal, high
}

enum RecurrenceExpectation: String, Codable, Hashable {
    case oneOff = "one_off"
    case recurring
    case flexibleCadence = "flexible_cadence"
    case eventDriven = "event_driven"
}

enum ReminderConfidenceTier: String, Codable, Hashable {
    case high
    case medium
    case low
}

enum ReminderSchedulingPolicy: String, Codable, Hashable {
    case adaptive
    case exactDate = "exact_date"
    case relativeOffset = "relative_offset"
    case approximateWindow = "approximate_window"
    case recurring
    case eventTrigger = "event_trigger"
    case pendingSetup = "pending_setup"
    case unsupported
}

struct ReminderRecurrenceRule: Codable, Hashable, Equatable {
    enum Unit: String, Codable, Hashable {
        case day
        case week
        case month
    }

    var unit: Unit
    var interval: Int
    var timesPerUnit: Int?
    var preferredWindow: NudgeTimeWindow?
    var sourcePhrase: String

    init(
        unit: Unit,
        interval: Int = 1,
        timesPerUnit: Int? = nil,
        preferredWindow: NudgeTimeWindow? = nil,
        sourcePhrase: String
    ) {
        self.unit = unit
        self.interval = max(1, interval)
        self.timesPerUnit = timesPerUnit
        self.preferredWindow = preferredWindow
        self.sourcePhrase = sourcePhrase
    }
}

enum ReminderAmbiguityFlag: String, Codable, Hashable {
    case missingLocationAlias = "missing_location_alias"
    case unsupportedTrigger = "unsupported_trigger"
    case lowTriggerConfidence = "low_trigger_confidence"
    case calendarPermissionNeeded = "calendar_permission_needed"
    case needsConfirmation = "needs_confirmation"
}

struct NudgeTimeWindow: Codable, Hashable {
    var startHour: Int
    var endHour: Int
    var label: TimeWindowLabel

    static func around(hour: Int, label: TimeWindowLabel) -> NudgeTimeWindow {
        NudgeTimeWindow(startHour: max(0, hour - 1), endHour: min(23, hour + 1), label: label)
    }

    func nextDateAvoidingQuietHours(settings: AppSettings, from now: Date = .now) -> Date {
        let cal = Calendar.current
        let preferredHour = (startHour + endHour) / 2
        let candidate = cal.date(bySettingHour: preferredHour, minute: 15, second: 0, of: now) ?? now
        let future = candidate > now ? candidate : cal.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        let hour = cal.component(.hour, from: future)
        if !AdaptiveEngine.isQuiet(hour: hour, settings: settings) {
            return future
        }
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
        let fallbackHour = (settings.quietHoursEnd + 1) % 24
        return cal.date(bySettingHour: fallbackHour, minute: 15, second: 0, of: tomorrow) ?? tomorrow
    }
}

// Trigger payload — a "moment" (device event) or a "place" (geofence) or freeform.
struct TriggerInfo: Codable, Hashable {
    enum Kind: String, Codable { case moment, place, custom }
    var kind: Kind
    var id: String?     // canonical id e.g. "open_laptop"
    var label: String   // human-readable
}

enum TriggerType: String, Codable, CaseIterable, Hashable {
    case appOpen = "app_open"
    case geofenceEnter = "geofence_enter"
    case geofenceExit = "geofence_exit"
    case deviceUnlock = "device_unlock"
    case chargingStarted = "charging_started"
    case musicStarted = "music_started"
    case spotifyOpened = "spotify_opened"
    case mediaContextUnsupported = "media_context_unsupported"
    case headphonesConnected = "headphones_connected"
    case bluetoothConnected = "bluetooth_connected"
    case bluetoothDisconnected = "bluetooth_disconnected"
    case carBluetoothConnected = "car_bluetooth_connected"
    case carBluetoothDisconnected = "car_bluetooth_disconnected"
    case carplayConnected = "carplay_connected"
    case carplayDisconnected = "carplay_disconnected"
    case wifiConnected = "wifi_connected"
    case homeWifiConnected = "home_wifi_connected"
    case workoutEnded = "workout_ended"
    case calendarEventEnded = "calendar_event_ended"
    case morningFirstUnlock = "morning_first_unlock"
    case eveningWindow = "evening_window"
    case customContext = "custom_context"
    case unknownRequiresClarification = "unknown_requires_clarification"
}

enum PermissionKind: String, Codable, CaseIterable, Hashable {
    case notifications
    case location
    case motionFitness = "motion_fitness"
    case calendar
    case bluetooth
    case localNetwork = "local_network"
    case microphone
}

struct TriggerCondition: Codable, Hashable, Equatable {
    var type: TriggerType
    var subject: String?
    var locationAlias: String?
    var metadata: [String: String]
    var requiresPermission: [PermissionKind]
    var minimumConfidence: Double
    var cooldownSeconds: TimeInterval?

    init(
        type: TriggerType,
        subject: String? = nil,
        locationAlias: String? = nil,
        metadata: [String: String] = [:],
        requiresPermission: [PermissionKind] = [.notifications],
        minimumConfidence: Double = 0.65,
        cooldownSeconds: TimeInterval? = 3600
    ) {
        self.type = type
        self.subject = subject
        self.locationAlias = locationAlias
        self.metadata = metadata
        self.requiresPermission = requiresPermission
        self.minimumConfidence = minimumConfidence
        self.cooldownSeconds = cooldownSeconds
    }
}

struct ReminderTrigger: Codable, Hashable, Equatable {
    var id: UUID
    var condition: TriggerCondition
    var confidence: Double
    var createdAt: Date
    var lastFiredAt: Date?
    var enabled: Bool

    init(
        id: UUID = UUID(),
        condition: TriggerCondition,
        confidence: Double,
        createdAt: Date = .now,
        lastFiredAt: Date? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.condition = condition
        self.confidence = confidence
        self.createdAt = createdAt
        self.lastFiredAt = lastFiredAt
        self.enabled = enabled
    }
}

struct ReminderSchedule: Codable, Hashable {
    var cadence: SuggestedCadence
    var preferredWindow: NudgeTimeWindow?
    var dailyCap: Int
    var lastPlannedAt: Date?
    var confidence: Double? = nil
    var lastExplanation: NudgeExplanation? = nil
    var lastPlanStatus: NudgePlanStatus? = nil
    var interpretationSummary: String? = nil
    var fallbackSummary: String? = nil
    var exactDate: Date? = nil
    var approximateDate: Date? = nil
    var relativeOffsetSeconds: TimeInterval? = nil
    var recurrenceRule: ReminderRecurrenceRule? = nil
    var confidenceTier: ReminderConfidenceTier? = nil
    var grammarExplanation: String? = nil
    var schedulingPolicy: ReminderSchedulingPolicy? = nil
    var conflictGroupKey: String? = nil
    var conflictAnchorReminderId: UUID? = nil
    var conflictResolvedFireDate: Date? = nil
    var conflictResolvedRank: Int? = nil
    var conflictResolvedAt: Date? = nil
}

enum NudgePlanStatus: String, Codable, Hashable {
    case scheduled
    case waitingForTrigger
    case needsClarification
    case missingPermission
    case missingLocationAlias
    case unsupported
    case dailyCapReached
    case quietHours
    case clustered
    case paused
}

enum NudgeExplanationCode: String, Codable, Hashable {
    case matchedMorningWaterPattern
    case matchedMorningHabit
    case selectedSocialEvening
    case categoryDefaultWindow
    case learnedRhythmWindow
    case parsedTimeHint
    case quietHoursDelayed
    case dailyCapReached
    case notificationClusterPrevented
    case waitingForTrigger
    case missingPermission
    case missingLocationAlias
    case unsupportedTrigger
    case needsClarification
    case recentMistimedEasedBack
    case lowConfidenceTriggerFallback
    case triggeredByEvent
    case maybeLaterDelayed
    case ignoredWindowReduced
    case openedPositiveSignal
    case delayedDueToAnotherReminder
}

struct NudgeExplanation: Codable, Hashable {
    var code: NudgeExplanationCode
    var text: String
}

struct NudgePlan: Codable, Hashable {
    var reminderId: UUID
    var nextFireDate: Date
    var window: NudgeTimeWindow
    var confidence: Double
    var explanation: NudgeExplanation
}

struct NudgePlanResult: Codable, Hashable {
    var status: NudgePlanStatus
    var plan: NudgePlan?
    var explanation: NudgeExplanation
    var confidence: Double
    var conflictGroupKey: String? = nil
    var conflictAnchorReminderId: UUID? = nil
    var conflictResolvedRank: Int? = nil
    var conflictResolvedAt: Date? = nil

    var isScheduled: Bool { (status == .scheduled || status == .clustered) && plan != nil }
}

struct NudgeDecisionContext {
    var allReminders: [Reminder]
    var settings: AppSettings
    var now: Date
    var triggeredBy: TriggerEvent?

    init(allReminders: [Reminder], settings: AppSettings, now: Date = .now, triggeredBy: TriggerEvent? = nil) {
        self.allReminders = allReminders
        self.settings = settings
        self.now = now
        self.triggeredBy = triggeredBy
    }
}

struct TriggerEvent: Codable, Hashable {
    var type: TriggerType
    var subject: String?
    var confidence: Double
    var createdAt: Date

    init(type: TriggerType, subject: String? = nil, confidence: Double = 1.0, createdAt: Date = .now) {
        self.type = type
        self.subject = subject
        self.confidence = confidence
        self.createdAt = createdAt
    }
}

struct TriggerEventLog: Codable, Identifiable, Hashable {
    let id: UUID
    var triggerType: TriggerType
    var subject: String?
    var reminderId: UUID?
    var confidence: Double
    var createdAt: Date
    var fired: Bool

    init(id: UUID = UUID(), triggerType: TriggerType, subject: String? = nil, reminderId: UUID? = nil, confidence: Double, createdAt: Date = .now, fired: Bool = false) {
        self.id = id
        self.triggerType = triggerType
        self.subject = subject
        self.reminderId = reminderId
        self.confidence = confidence
        self.createdAt = createdAt
        self.fired = fired
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        triggerType = try c.decode(TriggerType.self, forKey: .triggerType)
        subject = try c.decodeIfPresent(String.self, forKey: .subject)
        reminderId = try c.decodeIfPresent(UUID.self, forKey: .reminderId)
        confidence = try c.decode(Double.self, forKey: .confidence)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        fired = try c.decode(Bool.self, forKey: .fired)
    }
}

struct NudgeHistory: Codable, Identifiable, Hashable {
    let id: UUID
    var reminderId: UUID
    var plannedAt: Date
    var deliveredAt: Date?
    var action: UserFeedbackAction?

    init(id: UUID = UUID(), reminderId: UUID, plannedAt: Date, deliveredAt: Date? = nil, action: UserFeedbackAction? = nil) {
        self.id = id
        self.reminderId = reminderId
        self.plannedAt = plannedAt
        self.deliveredAt = deliveredAt
        self.action = action
    }
}

enum UserFeedbackAction: String, Codable, Hashable {
    case done
    case maybeLater = "maybe_later"
    case ignored
    case dismissed
    case opened
}

struct UserFeedback: Codable, Identifiable, Hashable {
    let id: UUID
    var reminderId: UUID
    var action: UserFeedbackAction
    var createdAt: Date

    init(id: UUID = UUID(), reminderId: UUID, action: UserFeedbackAction, createdAt: Date = .now) {
        self.id = id
        self.reminderId = reminderId
        self.action = action
        self.createdAt = createdAt
    }
}

struct UserRhythmProfile: Codable, Hashable {
    var preferredHoursByCategory: [String: [Int: Double]] = [:]
    var feedbackCountsByCategory: [String: [String: Int]] = [:]
    var mistimingStreakByCategory: [String: Int] = [:]
    var successStreakByCategory: [String: Int] = [:]
    var confidenceByCategory: [String: Double] = [:]
    var lastPatternNoticeAt: Date?
    var updatedAt: Date = .now

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.preferredHoursByCategory = try c.decodeIfPresent([String: [Int: Double]].self, forKey: .preferredHoursByCategory) ?? [:]
        self.feedbackCountsByCategory = try c.decodeIfPresent([String: [String: Int]].self, forKey: .feedbackCountsByCategory) ?? [:]
        self.mistimingStreakByCategory = try c.decodeIfPresent([String: Int].self, forKey: .mistimingStreakByCategory) ?? [:]
        self.successStreakByCategory = try c.decodeIfPresent([String: Int].self, forKey: .successStreakByCategory) ?? [:]
        self.confidenceByCategory = try c.decodeIfPresent([String: Double].self, forKey: .confidenceByCategory) ?? [:]
        self.lastPatternNoticeAt = try c.decodeIfPresent(Date.self, forKey: .lastPatternNoticeAt)
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }
}

struct QuietHours: Codable, Hashable {
    var startHour: Int
    var endHour: Int
}

struct LocationAlias: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var latitude: Double?
    var longitude: Double?
    var radiusMeters: Double

    init(id: UUID = UUID(), name: String, latitude: Double? = nil, longitude: Double? = nil, radiusMeters: Double = 150) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
    }
}

enum LocationAliasCatalog {
    static let defaultNames = ["home", "work", "gym", "gas_station"]

    static func normalized(_ aliases: [LocationAlias]) -> [LocationAlias] {
        var result: [LocationAlias] = []
        var seen = Set<String>()

        for name in defaultNames {
            if let existing = aliases.first(where: { canonicalName($0.name) == name }) {
                var alias = existing
                alias.name = name
                result.append(alias)
            } else {
                result.append(LocationAlias(name: name))
            }
            seen.insert(name)
        }

        for alias in aliases {
            let key = canonicalName(alias.name)
            guard !seen.contains(key) else { continue }
            var normalized = alias
            normalized.name = key
            result.append(normalized)
            seen.insert(key)
        }

        return result
    }

    static func canonicalName(_ name: String) -> String {
        TriggerParser.normalize(name)
            .replacingOccurrences(of: " ", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func displayName(_ name: String) -> String {
        switch canonicalName(name) {
        case "home": return "Home"
        case "work": return "Work"
        case "gym": return "Gym"
        case "gas_station": return "Gas Station"
        default:
            return name
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }
}

enum PermissionStatus: String, Codable, Hashable {
    case unknown
    case granted
    case denied
    case unavailable
}

struct PermissionState: Codable, Hashable {
    var permission: PermissionKind
    var status: PermissionStatus
    var updatedAt: Date

    init(permission: PermissionKind, status: PermissionStatus = .unknown, updatedAt: Date = .now) {
        self.permission = permission
        self.status = status
        self.updatedAt = updatedAt
    }
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

    var kind: ReminderKind = .timeBased
    var schedule: ReminderSchedule?
    var triggerDefinition: ReminderTrigger?

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
        self.kind           = .timeBased
        self.schedule       = nil
        self.triggerDefinition = nil
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
        self.kind           = try c.decodeIfPresent(ReminderKind.self, forKey: .kind)
            ?? ReminderKind(fromLegacyType: self.type)
        self.schedule       = try c.decodeIfPresent(ReminderSchedule.self, forKey: .schedule)
        self.triggerDefinition = try c.decodeIfPresent(ReminderTrigger.self, forKey: .triggerDefinition)
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

private extension ReminderKind {
    init(fromLegacyType type: ReminderType) {
        switch type {
        case .standard: self = .timeBased
        case .trigger: self = .eventBased
        case .voice: self = .voice
        case .linked: self = .followOn
        case .oneoff: self = .oneOff
        }
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
    var userRhythmProfile: UserRhythmProfile = UserRhythmProfile()
    var quietHours: QuietHours = QuietHours(startHour: 23, endHour: 8)
    var locationAliases: [LocationAlias] = []
    var permissionStates: [PermissionState] = []
    var triggerEventLog: [TriggerEventLog] = []
    var nudgeHistory: [NudgeHistory] = []
    var userFeedback: [UserFeedback] = []
    var patternNoticesShown: [String] = []
    var lastMorningFirstUnlockDate: String?

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
        self.userRhythmProfile     = try c.decodeIfPresent(UserRhythmProfile.self, forKey: .userRhythmProfile) ?? UserRhythmProfile()
        self.quietHours            = try c.decodeIfPresent(QuietHours.self, forKey: .quietHours) ?? QuietHours(startHour: self.quietHoursStart, endHour: self.quietHoursEnd)
        self.locationAliases       = LocationAliasCatalog.normalized(try c.decodeIfPresent([LocationAlias].self, forKey: .locationAliases) ?? [])
        self.permissionStates      = try c.decodeIfPresent([PermissionState].self, forKey: .permissionStates) ?? []
        self.triggerEventLog       = try c.decodeIfPresent([TriggerEventLog].self, forKey: .triggerEventLog) ?? []
        self.nudgeHistory          = try c.decodeIfPresent([NudgeHistory].self, forKey: .nudgeHistory) ?? []
        self.userFeedback          = try c.decodeIfPresent([UserFeedback].self, forKey: .userFeedback) ?? []
        self.patternNoticesShown   = try c.decodeIfPresent([String].self, forKey: .patternNoticesShown) ?? []
        self.lastMorningFirstUnlockDate = try c.decodeIfPresent(String.self, forKey: .lastMorningFirstUnlockDate)
    }
}

#if DEBUG
struct ReminderDebugSummary: Hashable {
    var kind: ReminderKind
    var category: ReminderCategory
    var trigger: TriggerCondition?
    var nextPlannedNudge: Date?
    var confidence: Double
    var status: NudgePlanStatus
    var explanation: NudgeExplanation
}
#endif

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

struct RemovedReminderReceipt: Identifiable {
    let id = UUID()
    let reminder: Reminder
    let triggerEventLog: [TriggerEventLog]
    let nudgeHistory: [NudgeHistory]
    let userFeedback: [UserFeedback]
}

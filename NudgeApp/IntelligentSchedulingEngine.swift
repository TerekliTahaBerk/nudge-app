import Foundation

protocol AIIntentService {
    func parseIntent(from text: String, history: [Reminder]) async -> ParsedReminderIntent
}

struct ParsedReminderIntent: Codable, Equatable {
    var reminderText: String
    var kind: ReminderKind
    var category: ReminderCategory
    var suggestedCadence: SuggestedCadence
    var timeWindow: NudgeTimeWindow?
    var trigger: ReminderTrigger?
    var confidence: Double
    var needsClarification: Bool
    var clarifyingQuestion: String?
    var explanation: NudgeExplanation?
    var cleanText: String = ""
    var intent: ReminderIntent = .unknown
    var urgency: ReminderUrgency = .normal
    var recurrenceExpectation: RecurrenceExpectation = .oneOff
    var timeHints: [String] = []
    var eventTriggerHints: [String] = []
    var locationHints: [String] = []
    var deviceContextHints: [String] = []
    var requiredPermissions: [PermissionKind] = []
    var ambiguityFlags: [ReminderAmbiguityFlag] = []
    var interpretationSummary: String = ""
    var triggerReadiness: TriggerReadiness?
}

struct TriggerReadiness: Codable, Equatable {
    var triggerType: TriggerType
    var confidence: Double
    var requiredPermissions: [PermissionKind]
    var requiredSetup: [String]
    var isCurrentlyActionable: Bool
    var fallbackStrategy: FallbackStrategy?
    var explanation: String
}

struct LocalHeuristicIntentService: AIIntentService {
    func parseIntent(from text: String, history: [Reminder] = []) async -> ParsedReminderIntent {
        ReminderUnderstandingEngine.parse(text, history: history)
    }
}

enum ReminderIntentParser {
    static func parse(_ rawText: String, history: [Reminder] = []) -> ParsedReminderIntent {
        ReminderUnderstandingEngine.parse(rawText, history: history)
    }
}

enum ReminderUnderstandingEngine {
    static func parse(_ rawText: String, history: [Reminder] = []) -> ParsedReminderIntent {
        let text = ReminderInputValidator.sanitize(rawText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let analysis = TextAnalyzer.analyze(text)
        let triggerResult = TriggerParser.parse(text)
        let category = ReminderCategoryClassifier.classify(text: text, analysis: analysis)
        let cadence = CadenceController.defaultCadence(for: text, category: category, analysis: analysis)
        let window = NudgeDecisionEngine.suggestedWindow(
            text: text,
            category: category,
            analysis: analysis,
            history: history
        )

        let hasTrigger = triggerResult.condition.type != .unknownRequiresClarification
        let minConfidence = triggerResult.condition.minimumConfidence
        let isSupported = triggerResult.condition.type.isSupportedWithoutClarification
        let cleanedText = triggerResult.reminderText ?? stripReminderPrefix(from: text)
        let readiness = hasTrigger ? triggerReadiness(for: triggerResult) : nil
        let ambiguity = ambiguityFlags(triggerResult: triggerResult, hasTrigger: hasTrigger)
        let requiredPermissions = hasTrigger ? triggerResult.condition.requiresPermission : [.notifications]
        let recurrence = recurrenceExpectation(cadence: cadence, hasTrigger: hasTrigger, text: text)
        let intent = inferIntent(from: cleanedText, category: category)
        let urgency = inferUrgency(from: text)
        let summary = summary(
            text: cleanedText,
            kind: hasTrigger ? .eventBased : kindForTimeReminder(text: text, cadence: cadence),
            category: category,
            triggerResult: hasTrigger ? triggerResult : nil,
            recurrence: recurrence
        )

        if hasTrigger && triggerResult.confidence < minConfidence {
            if isSupported {
                return ParsedReminderIntent(
                    reminderText: cleanedText,
                    kind: .timeBased,
                    category: category,
                    suggestedCadence: cadence,
                    timeWindow: window,
                    trigger: nil,
                    confidence: max(0.35, analysis.confidence),
                    needsClarification: false,
                    clarifyingQuestion: nil,
                    explanation: NudgeExplanation(
                        code: .lowConfidenceTriggerFallback,
                        text: "Low-confidence trigger fell back to a time-based nudge."
                    ),
                    cleanText: cleanedText,
                    intent: intent,
                    urgency: urgency,
                    recurrenceExpectation: recurrence,
                    timeHints: timeHints(from: text),
                    eventTriggerHints: hasTrigger ? [triggerResult.condition.type.rawValue] : [],
                    locationHints: locationHints(from: triggerResult.condition),
                    deviceContextHints: deviceHints(from: triggerResult.condition),
                    requiredPermissions: requiredPermissions,
                    ambiguityFlags: ambiguity + [.lowTriggerConfidence],
                    interpretationSummary: summary,
                    triggerReadiness: readiness
                )
            }

            return ParsedReminderIntent(
                reminderText: cleanedText,
                kind: .eventBased,
                category: category,
                suggestedCadence: cadence,
                timeWindow: nil,
                trigger: ReminderTrigger(condition: triggerResult.condition, confidence: triggerResult.confidence),
                confidence: triggerResult.confidence,
                needsClarification: true,
                clarifyingQuestion: triggerResult.clarifyingQuestion ?? "I need a little more context for this trigger.",
                explanation: NudgeExplanation(code: .needsClarification, text: triggerResult.explanation),
                cleanText: cleanedText,
                intent: intent,
                urgency: urgency,
                recurrenceExpectation: .eventDriven,
                timeHints: timeHints(from: text),
                eventTriggerHints: [triggerResult.condition.type.rawValue],
                locationHints: locationHints(from: triggerResult.condition),
                deviceContextHints: deviceHints(from: triggerResult.condition),
                requiredPermissions: requiredPermissions,
                ambiguityFlags: ambiguity + [.lowTriggerConfidence],
                interpretationSummary: summary,
                triggerReadiness: readiness
            )
        }

        let confidence = min(1.0, max(analysis.confidence, triggerResult.confidence))
        let kind = hasTrigger ? ReminderKind.eventBased : kindForTimeReminder(text: text, cadence: cadence)
        return ParsedReminderIntent(
            reminderText: cleanedText,
            kind: kind,
            category: category,
            suggestedCadence: cadence,
            timeWindow: hasTrigger ? nil : window,
            trigger: hasTrigger ? ReminderTrigger(condition: triggerResult.condition, confidence: triggerResult.confidence) : nil,
            confidence: confidence,
            needsClarification: triggerResult.needsClarification,
            clarifyingQuestion: triggerResult.clarifyingQuestion,
            explanation: hasTrigger
                ? NudgeExplanation(code: .waitingForTrigger, text: triggerResult.explanation)
                : NudgeExplanation(code: .parsedTimeHint, text: summary),
            cleanText: cleanedText,
            intent: intent,
            urgency: urgency,
            recurrenceExpectation: recurrence,
            timeHints: timeHints(from: text),
            eventTriggerHints: hasTrigger ? [triggerResult.condition.type.rawValue] : [],
            locationHints: hasTrigger ? locationHints(from: triggerResult.condition) : [],
            deviceContextHints: hasTrigger ? deviceHints(from: triggerResult.condition) : [],
            requiredPermissions: requiredPermissions,
            ambiguityFlags: ambiguity,
            interpretationSummary: summary,
            triggerReadiness: readiness
        )
    }

    private static func triggerReadiness(for result: TriggerParser.Result) -> TriggerReadiness {
        let condition = result.condition
        let fallback = FallbackStrategy.strategy(for: condition)
        let setup: [String]
        if let alias = condition.locationAlias {
            setup = ["saved_\(alias)_location"]
        } else if condition.type == .customContext {
            setup = [condition.metadata["fallback"] ?? fallback.explanation]
        } else if condition.type == .calendarEventEnded {
            setup = ["calendar_access"]
        } else if condition.type == .workoutEnded {
            setup = ["motion_fitness_access"]
        } else {
            setup = []
        }
        let actionable = condition.metadata["actionable"] != "false" && condition.type != .customContext
        return TriggerReadiness(
            triggerType: condition.type,
            confidence: result.confidence,
            requiredPermissions: condition.requiresPermission,
            requiredSetup: setup,
            isCurrentlyActionable: actionable,
            fallbackStrategy: fallback,
            explanation: result.explanation
        )
    }

    private static func ambiguityFlags(triggerResult: TriggerParser.Result, hasTrigger: Bool) -> [ReminderAmbiguityFlag] {
        guard hasTrigger else { return [] }
        var flags: [ReminderAmbiguityFlag] = []
        if triggerResult.condition.locationAlias != nil { flags.append(.missingLocationAlias) }
        if triggerResult.condition.type == .customContext { flags.append(.unsupportedTrigger) }
        if triggerResult.condition.type == .calendarEventEnded { flags.append(.calendarPermissionNeeded) }
        if triggerResult.condition.subject == "fuel_stop" { flags.append(.needsConfirmation) }
        return flags
    }

    private static func recurrenceExpectation(cadence: SuggestedCadence, hasTrigger: Bool, text: String) -> RecurrenceExpectation {
        if hasTrigger { return .eventDriven }
        switch cadence {
        case .daily, .smartGentle, .fewTimesPerWeek: return .recurring
        case .occasional: return .flexibleCadence
        case .oneOff: return .oneOff
        }
    }

    private static func kindForTimeReminder(text: String, cadence: SuggestedCadence) -> ReminderKind {
        let lower = TriggerParser.normalize(text)
        if lower.contains("bugun") || lower.contains("today") || lower.contains("tonight") { return .oneOff }
        return cadence == .oneOff ? .oneOff : .timeBased
    }

    private static func inferIntent(from text: String, category: ReminderCategory) -> ReminderIntent {
        let lower = TriggerParser.normalize(text)
        if lower.contains("ara") || lower.contains("call") { return .call }
        if lower.contains("gonder") || lower.contains("send") || lower.contains("mail") || lower.contains("email") { return .send }
        if lower.contains("ic") || lower.contains("drink") { return .drink }
        if lower.contains("yuru") || lower.contains("walk") { return .move }
        if category == .home { return .household }
        if category == .errand { return .errand }
        return .remind
    }

    private static func inferUrgency(from text: String) -> ReminderUrgency {
        let lower = TriggerParser.normalize(text)
        if lower.contains("acil") || lower.contains("urgent") || lower.contains("asap") { return .high }
        if lower.contains("bazen") || lower.contains("sometimes") || lower.contains("ara sira") { return .low }
        return .normal
    }

    private static func timeHints(from text: String) -> [String] {
        let lower = TriggerParser.normalize(text)
        var hints: [String] = []
        if lower.contains("sabah") || lower.contains("morning") { hints.append("morning") }
        if lower.contains("ogle") || lower.contains("lunch") { hints.append("late_morning") }
        if lower.contains("aksam") || lower.contains("tonight") || lower.contains("evening") { hints.append("evening") }
        if lower.contains("bugun") || lower.contains("today") { hints.append("today") }
        return hints
    }

    private static func locationHints(from condition: TriggerCondition) -> [String] {
        condition.locationAlias.map { [$0] } ?? []
    }

    private static func deviceHints(from condition: TriggerCondition) -> [String] {
        switch condition.type {
        case .chargingStarted, .morningFirstUnlock, .deviceUnlock, .bluetoothConnected, .bluetoothDisconnected, .carplayConnected, .carplayDisconnected:
            return [condition.type.rawValue]
        case .customContext:
            return [condition.subject ?? condition.type.rawValue]
        default:
            return []
        }
    }

    private static func summary(
        text: String,
        kind: ReminderKind,
        category: ReminderCategory,
        triggerResult: TriggerParser.Result?,
        recurrence: RecurrenceExpectation
    ) -> String {
        if let triggerResult {
            return "I'll remind you to \(text) when \(triggerResult.explanation.lowercased())"
        }
        if recurrence == .flexibleCadence {
            return "I'll nudge gently now and then for \(text)."
        }
        return "I'll treat this as a \(kind.rawValue.replacingOccurrences(of: "_", with: " ")) \(category.displayName) reminder."
    }

    private static func stripReminderPrefix(from text: String) -> String {
        let lower = TriggerParser.normalize(text)
        let prefixes = ["remind me to ", "remind me ", "bana hatirlat ", "hatirlat "]
        for prefix in prefixes where lower.hasPrefix(prefix) {
            let idx = text.index(text.startIndex, offsetBy: min(prefix.count, text.count))
            return String(text[idx...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}

enum ReminderCategoryClassifier {
    static func classify(text: String, analysis: TextAnalysis) -> ReminderCategory {
        let lower = text.lowercased(with: Locale(identifier: "tr_TR"))
        let weighted: [(ReminderCategory, [String])] = [
            (.social, ["call", "mom", "dad", "friend", "family", "ara", "annemi", "babamı", "arkadaş"]),
            (.errand, ["buy", "pickup", "fuel", "grocery", "anahtar", "fiş", "benzin", "yakıt", "market"]),
            (.health, ["medicine", "pill", "doctor", "workout", "protein", "ilaç", "doktor"]),
            (.home, ["laundry", "trash", "dishes", "home", "çamaşır", "çöp", "bulaşık", "ev"]),
            (.work, ["report", "email", "meeting", "office", "rapor", "mail", "toplantı", "ofis", "iş"]),
            (.task, ["send", "finish", "review", "prepare", "gönder", "bitir", "hazırla"]),
        ]
        if let match = weighted.first(where: { _, words in words.contains { lower.contains($0) } }) {
            return match.0
        }
        return analysis.category
    }
}

struct UserRhythmModel {
    var profile: UserRhythmProfile

    func hourScore(for category: ReminderCategory, hour: Int) -> Double {
        profile.preferredHoursByCategory[category.rawValue]?[hour] ?? 0
    }

    mutating func record(_ feedback: UserFeedback, category: ReminderCategory) {
        let hour = Calendar.current.component(.hour, from: feedback.createdAt)
        let delta: Double = switch feedback.action {
        case .done: 0.35
        case .maybeLater: -0.18
        case .ignored, .dismissed: -0.32
        case .opened: 0.08
        }
        let key = category.rawValue
        var bucket = profile.preferredHoursByCategory[category.rawValue] ?? [:]
        bucket[hour, default: 0] = max(-1.0, min(1.2, bucket[hour, default: 0] + delta))
        profile.preferredHoursByCategory[key] = bucket

        var counts = profile.feedbackCountsByCategory[key] ?? [:]
        counts[feedback.action.rawValue, default: 0] += 1
        profile.feedbackCountsByCategory[key] = counts

        switch feedback.action {
        case .done:
            profile.successStreakByCategory[key, default: 0] += 1
            profile.mistimingStreakByCategory[key] = max(0, (profile.mistimingStreakByCategory[key] ?? 0) - 1)
            profile.confidenceByCategory[key, default: 0.4] = min(1.0, profile.confidenceByCategory[key, default: 0.4] + 0.04)
        case .opened:
            profile.confidenceByCategory[key, default: 0.4] = min(1.0, profile.confidenceByCategory[key, default: 0.4] + 0.015)
        case .maybeLater, .ignored, .dismissed:
            profile.mistimingStreakByCategory[key, default: 0] += feedback.action == .maybeLater ? 1 : 2
            profile.successStreakByCategory[key] = 0
            profile.confidenceByCategory[key, default: 0.4] = max(0.05, profile.confidenceByCategory[key, default: 0.4] - 0.03)
        }
        profile.updatedAt = .now
    }
}

enum NudgeDecisionEngine {
    static func suggestedWindow(
        text: String,
        category: ReminderCategory,
        analysis: TextAnalysis,
        history: [Reminder]
    ) -> NudgeTimeWindow {
        let lower = text.lowercased(with: Locale(identifier: "tr_TR"))
        if lower.contains("before lunch") || lower.contains("öğle") {
            return NudgeTimeWindow(startHour: 10, endHour: 12, label: .lateMorning)
        }
        if lower.contains("morning") || lower.contains("sabah") {
            return NudgeTimeWindow(startHour: 8, endHour: 11, label: .morning)
        }
        if lower.contains("evening") || lower.contains("akşam") || lower.contains("call") || lower.contains("ara") {
            return NudgeTimeWindow(startHour: 18, endHour: 21, label: .evening)
        }
        let hour = category.defaultHours.first ?? analysis.suggestedTimePreference.preferredHours.first ?? 10
        return NudgeTimeWindow.around(hour: hour, label: TimeWindowLabel.label(for: hour))
    }
}

enum CadenceController {
    static func defaultCadence(for text: String, category: ReminderCategory, analysis: TextAnalysis) -> SuggestedCadence {
        let lower = text.lowercased(with: Locale(identifier: "tr_TR"))
        let normalized = TriggerParser.normalize(text)
        if normalized.contains("bugun") || normalized.contains("today") || normalized.contains("tonight") { return .oneOff }
        if normalized.contains("bazen") || normalized.contains("ara sira") || normalized.contains("sometimes") || normalized.contains("occasionally") { return .occasional }
        if lower.contains("water") || lower.contains("su") { return .smartGentle }
        if lower.contains("walk") || lower.contains("yürü") { return .fewTimesPerWeek }
        return switch analysis.suggestedFrequency {
        case .daily: .daily
        case .weekly: .fewTimesPerWeek
        case .occasional: .occasional
        case .smart: category == .body ? .smartGentle : .fewTimesPerWeek
        }
    }

    static func shouldReduceCadence(for reminder: Reminder) -> Bool {
        let recent = reminder.interactions.suffix(5)
        let negative = recent.filter { $0.type == .ignored || $0.type == .skipped }.count
        return recent.count >= 3 && negative >= 3
    }

    static func maybeLaterDelay(for reminder: Reminder) -> TimeInterval {
        let recentSkips = reminder.interactions.suffix(4).filter { $0.type == .skipped }.count
        return TimeInterval(min(8, 2 + recentSkips * 2) * 3600)
    }
}

enum NotificationPlanner {
    struct TimingScore: Hashable {
        var hour: Int
        var semanticScore: Double
        var rhythmScore: Double
        var recencyScore: Double
        var fatiguePenalty: Double
        var quietHourPenalty: Double
        var clusteringPenalty: Double
        var confidenceScore: Double

        var total: Double {
            semanticScore + rhythmScore + recencyScore + confidenceScore - fatiguePenalty - quietHourPenalty - clusteringPenalty
        }
    }

    static func plan(for reminder: Reminder, context: NudgeDecisionContext) -> NudgePlanResult {
        let settings = context.settings
        let now = context.now
        let calendar = Calendar.current

        if reminder.isDone {
            return notScheduled(.paused, .recentMistimedEasedBack, "Reminder is already done.", confidence: 0)
        }
        if let pausedUntil = reminder.pausedUntil, pausedUntil > now {
            return notScheduled(.paused, .recentMistimedEasedBack, "Recent nudges felt mistimed, so this is paused.", confidence: 0.35)
        }
        if hasExplicitlyDeniedNotifications(settings) {
            return notScheduled(.missingPermission, .missingPermission, "Notification permission is denied.", confidence: 0)
        }

        if reminder.kind == .eventBased || reminder.triggerDefinition != nil {
            guard let trigger = reminder.triggerDefinition else {
                return notScheduled(.needsClarification, .needsClarification, "Event-based reminder has no trigger definition.", confidence: 0)
            }
            let resolution = TriggerResolver.resolve(
                trigger.condition,
                aliases: settings.locationAliases,
                permissions: settings.permissionStates
            )
            if !resolution.isReady {
                if !resolution.missingPermissions.isEmpty {
                    return notScheduled(.missingPermission, .missingPermission, "Trigger is waiting for permission.", confidence: trigger.confidence)
                }
                if case .askToDefineLocation = resolution.fallback {
                    return notScheduled(.missingLocationAlias, .missingLocationAlias, "Trigger is waiting for a saved place.", confidence: trigger.confidence)
                }
                if resolution.fallback == .shortcutsAutomation ||
                    resolution.fallback == .manualReminder ||
                    resolution.fallback == .companionOrSignal ||
                    resolution.fallback == .oneTapConfirmation {
                    return notScheduled(.unsupported, .unsupportedTrigger, resolution.fallback?.explanation ?? "Trigger needs an external signal before it can fire.", confidence: trigger.confidence)
                }
            }
            guard let event = context.triggeredBy else {
                return notScheduled(.waitingForTrigger, .waitingForTrigger, "Waiting for \(trigger.condition.type.rawValue).", confidence: trigger.confidence)
            }
            guard TriggerExecutionPolicy.matches(event, condition: trigger.condition) else {
                return notScheduled(.waitingForTrigger, .waitingForTrigger, "Received event does not match this trigger.", confidence: trigger.confidence)
            }

            // Trigger matched — schedule immediately, respecting only daily cap and quiet hours.
            let dailyCountTriggered = dailyPlannedOrSentCount(settings: settings, reminders: context.allReminders, now: now)
            if dailyCountTriggered >= settings.notificationLevel.maxDailyNudgesGlobal {
                return notScheduled(.dailyCapReached, .dailyCapReached, "Daily notification cap has been reached.", confidence: 0.4)
            }
            let immediateCandidate = now.addingTimeInterval(5)
            let immediateHour = calendar.component(.hour, from: immediateCandidate)
            let fireDate = AdaptiveEngine.isQuiet(hour: immediateHour, settings: settings)
                ? firstNonQuietDate(after: immediateCandidate, settings: settings)
                : immediateCandidate
            let fireHour = calendar.component(.hour, from: fireDate)
            let nowWindow = NudgeTimeWindow.around(hour: fireHour, label: TimeWindowLabel.label(for: fireHour))
            return scheduled(
                reminder: reminder,
                date: fireDate,
                selected: (window: nowWindow, confidence: 0.9, explanation: .triggeredByEvent),
                explanation: .triggeredByEvent
            )
        }

        let dailyCount = dailyPlannedOrSentCount(settings: settings, reminders: context.allReminders, now: now)
        if dailyCount >= settings.notificationLevel.maxDailyNudgesGlobal {
            return notScheduled(.dailyCapReached, .dailyCapReached, "Daily notification cap has been reached.", confidence: 0.4)
        }

        if CadenceController.shouldReduceCadence(for: reminder) {
            let date = nextAllowedDate(
                for: selectedWindow(for: reminder, settings: settings).window,
                reminder: reminder,
                context: context,
                minimumOffset: 48 * 3600
            )
            return scheduled(reminder: reminder, date: date, selected: selectedWindow(for: reminder, settings: settings), explanation: .recentMistimedEasedBack)
        }

        let selected = selectedWindow(for: reminder, settings: settings)
        let candidate = nextAllowedDate(for: selected.window, reminder: reminder, context: context)
        let candidateHour = calendar.component(.hour, from: candidate)
        if AdaptiveEngine.isQuiet(hour: candidateHour, settings: settings) {
            let shifted = firstNonQuietDate(after: candidate, settings: settings)
            return scheduled(reminder: reminder, date: shifted, selected: selected, explanation: .quietHoursDelayed)
        }

        if isClustered(candidate, reminder: reminder, allReminders: context.allReminders) {
            let shifted = candidate.addingTimeInterval(AdaptiveEngine.clusterGapSeconds)
            return scheduled(reminder: reminder, date: firstNonQuietDate(after: shifted, settings: settings), selected: selected, explanation: .notificationClusterPrevented)
        }

        let explanation: NudgeExplanationCode = context.triggeredBy == nil ? selected.explanation : .triggeredByEvent
        return scheduled(reminder: reminder, date: candidate, selected: selected, explanation: explanation)
    }

    static func calmCopy(for reminder: Reminder) -> String {
        let text = reminder.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "A gentle reminder, just for you." }
        return "If it feels right, \(text.lowercased())."
    }

    private static func selectedWindow(for reminder: Reminder, settings: AppSettings) -> (window: NudgeTimeWindow, confidence: Double, explanation: NudgeExplanationCode) {
        let baseHours = reminder.schedule?.preferredWindow.map { Array($0.startHour...$0.endHour) }
            ?? reminder.category.defaultHours
        let rhythm = UserRhythmModel(profile: settings.userRhythmProfile)
        let categoryKey = reminder.category.rawValue
        let mistimingStreak = settings.userRhythmProfile.mistimingStreakByCategory[categoryKey] ?? 0
        let confidence = settings.userRhythmProfile.confidenceByCategory[categoryKey] ?? 0.35
        let scored = baseHours.map { hour -> TimingScore in
            let semantic = semanticScore(for: reminder, hour: hour)
            let rhythmScore = rhythm.hourScore(for: reminder.category, hour: hour)
            let recency = interactionScore(for: reminder, hour: hour)
            let fatigue = min(0.35, Double(mistimingStreak) * 0.08)
            let quietPenalty = AdaptiveEngine.isQuiet(hour: hour, settings: settings) ? 0.6 : 0
            let confidenceScore = min(0.25, confidence * 0.2)
            return TimingScore(
                hour: hour,
                semanticScore: semantic,
                rhythmScore: rhythmScore,
                recencyScore: recency,
                fatiguePenalty: fatigue,
                quietHourPenalty: quietPenalty,
                clusteringPenalty: 0,
                confidenceScore: confidenceScore
            )
        }
        let best = scored.max { a, b in
            if a.total == b.total { return a.hour > b.hour }
            return a.total < b.total
        } ?? TimingScore(hour: 10, semanticScore: 0.35, rhythmScore: 0, recencyScore: 0, fatiguePenalty: 0, quietHourPenalty: 0, clusteringPenalty: 0, confidenceScore: 0)
        let code: NudgeExplanationCode
        if reminder.text.localizedCaseInsensitiveContains("water"), (8...11).contains(best.hour) {
            code = .matchedMorningWaterPattern
        } else if (reminder.text.localizedCaseInsensitiveContains("morning") || reminder.text.localizedCaseInsensitiveContains("sabah")), (7...11).contains(best.hour) {
            code = .matchedMorningHabit
        } else if reminder.category == .social && (18...21).contains(best.hour) {
            code = .selectedSocialEvening
        } else if mistimingStreak >= 3 {
            code = .recentMistimedEasedBack
        } else if abs(best.total - 0.35) > 0.2 {
            code = .learnedRhythmWindow
        } else if reminder.schedule?.preferredWindow != nil {
            code = .parsedTimeHint
        } else {
            code = .categoryDefaultWindow
        }
        return (NudgeTimeWindow.around(hour: best.hour, label: TimeWindowLabel.label(for: best.hour)), max(0.1, min(1.0, best.total)), code)
    }

    private static func semanticScore(for reminder: Reminder, hour: Int) -> Double {
        var score = reminder.category.defaultHours.contains(hour) ? 0.48 : 0.3
        let lower = TriggerParser.normalize(reminder.text)
        if (lower.contains("water") || lower.contains("su") || lower.contains("sabah") || lower.contains("morning")), (7...11).contains(hour) {
            score += 0.22
        }
        if reminder.category == .social && (18...21).contains(hour) {
            score += 0.22
        }
        if reminder.category == .work && (9...16).contains(hour) {
            score += 0.18
        }
        if reminder.category == .home && (17...21).contains(hour) {
            score += 0.16
        }
        if reminder.category == .move && ([7, 12, 17].contains(hour)) {
            score += 0.16
        }
        return min(1.0, score)
    }

    private static func interactionScore(for reminder: Reminder, hour: Int) -> Double {
        reminder.interactions.reduce(0) { partial, interaction in
            guard Calendar.current.component(.hour, from: interaction.timestamp) == hour else { return partial }
            let age = max(0, Date.now.timeIntervalSince(interaction.timestamp))
            let weight = pow(0.5, age / AdaptiveEngine.halfLife)
            let value: Double = switch interaction.type {
            case .completed: 0.25
            case .skipped: -0.18
            case .ignored: -0.28
            }
            return partial + weight * value
        }
    }

    private static func dailyPlannedOrSentCount(settings: AppSettings, reminders: [Reminder], now: Date) -> Int {
        let start = Calendar.current.startOfDay(for: now)
        let history = settings.nudgeHistory.filter { $0.plannedAt >= start || ($0.deliveredAt ?? .distantPast) >= start }.count
        let interactions = reminders.reduce(0) { total, reminder in
            total + reminder.interactions.filter { $0.timestamp >= start }.count
        }
        return max(history, interactions)
    }

    private static func hasExplicitlyDeniedNotifications(_ settings: AppSettings) -> Bool {
        settings.permissionStates.contains {
            $0.permission == .notifications && ($0.status == .denied || $0.status == .unavailable)
        }
    }

    private static func nextAllowedDate(
        for window: NudgeTimeWindow,
        reminder: Reminder,
        context: NudgeDecisionContext,
        minimumOffset: TimeInterval = 5 * 60
    ) -> Date {
        let now = context.now
        let calendar = Calendar.current
        let hour = (window.startHour + window.endHour) / 2
        let minute = stableMinute(for: reminder.id)
        let earliest = now.addingTimeInterval(minimumOffset)
        let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? earliest
        let candidate = today > earliest ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? earliest
        return firstNonQuietDate(after: candidate, settings: context.settings)
    }

    private static func firstNonQuietDate(after date: Date, settings: AppSettings) -> Date {
        let calendar = Calendar.current
        var candidate = date
        for _ in 0..<48 {
            let hour = calendar.component(.hour, from: candidate)
            if !AdaptiveEngine.isQuiet(hour: hour, settings: settings) { return candidate }
            candidate = calendar.date(byAdding: .hour, value: 1, to: candidate) ?? candidate.addingTimeInterval(3600)
        }
        return candidate
    }

    private static func isClustered(_ date: Date, reminder: Reminder, allReminders: [Reminder]) -> Bool {
        allReminders.contains { other in
            guard other.id != reminder.id, let planned = other.nextNudgeAt else { return false }
            return abs(planned.timeIntervalSince(date)) < AdaptiveEngine.clusterGapSeconds
        }
    }

    private static func stableMinute(for id: UUID) -> Int {
        let sum = id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return 5 + (sum % 40)
    }

    private static func scheduled(
        reminder: Reminder,
        date: Date,
        selected: (window: NudgeTimeWindow, confidence: Double, explanation: NudgeExplanationCode),
        explanation: NudgeExplanationCode
    ) -> NudgePlanResult {
        let text = explanationText(for: explanation)
        let plan = NudgePlan(
            reminderId: reminder.id,
            nextFireDate: date,
            window: selected.window,
            confidence: selected.confidence,
            explanation: NudgeExplanation(code: explanation, text: text)
        )
        return NudgePlanResult(status: .scheduled, plan: plan, explanation: plan.explanation, confidence: selected.confidence)
    }

    private static func notScheduled(_ status: NudgePlanStatus, _ code: NudgeExplanationCode, _ text: String, confidence: Double) -> NudgePlanResult {
        NudgePlanResult(status: status, plan: nil, explanation: NudgeExplanation(code: code, text: text), confidence: confidence)
    }

    private static func explanationText(for code: NudgeExplanationCode) -> String {
        switch code {
        case .matchedMorningWaterPattern: return "Matched a morning water pattern."
        case .matchedMorningHabit: return "Matched a morning habit."
        case .selectedSocialEvening: return "Selected evening because social reminders tend to work better then."
        case .categoryDefaultWindow: return "Used the default window for this reminder category."
        case .learnedRhythmWindow: return "Used the user's learned rhythm for this category."
        case .parsedTimeHint: return "Used a time hint from the reminder text."
        case .quietHoursDelayed: return "Moved the nudge outside quiet hours."
        case .notificationClusterPrevented: return "Moved the nudge to avoid clustering."
        case .recentMistimedEasedBack: return "Recent nudges felt mistimed, so cadence eased back."
        case .triggeredByEvent: return "Scheduled after a matching trigger event."
        case .maybeLaterDelayed: return "Moved later after Maybe Later."
        case .ignoredWindowReduced: return "Reduced confidence for a recently ignored window."
        case .openedPositiveSignal: return "Opened from notification, a mild positive signal."
        default: return code.rawValue
        }
    }
}

enum FeedbackRecorder {
    static func record(_ action: UserFeedbackAction, reminder: inout Reminder, settings: AppSettings, at date: Date = .now) -> UserFeedback {
        let feedback = UserFeedback(reminderId: reminder.id, action: action, createdAt: date)
        let interaction: InteractionType? = switch action {
        case .done: .completed
        case .maybeLater: .skipped
        case .ignored, .dismissed: .ignored
        case .opened: nil
        }
        if let interaction {
            reminder.interactions.append(Interaction(type: interaction, at: date))
        }
        let cutoff = date.addingTimeInterval(-90 * 86400)
        reminder.interactions.removeAll { $0.timestamp < cutoff }
        if action == .maybeLater {
            reminder.nextNudgeAt = date.addingTimeInterval(CadenceController.maybeLaterDelay(for: reminder))
            reminder.schedule?.lastExplanation = NudgeExplanation(code: .maybeLaterDelayed, text: "Maybe later delayed the next nudge.")
        }
        return feedback
    }
}

enum TimeWindowLabel: String, Codable, Hashable {
    case earlyMorning = "early morning"
    case morning
    case lateMorning = "late morning"
    case afternoon
    case evening
    case night

    static func label(for hour: Int) -> TimeWindowLabel {
        switch hour {
        case 5..<8: return .earlyMorning
        case 8..<11: return .morning
        case 11..<13: return .lateMorning
        case 13..<17: return .afternoon
        case 17..<22: return .evening
        default: return .night
        }
    }
}

private extension TriggerType {
    var isSupportedWithoutClarification: Bool {
        switch self {
        case .chargingStarted, .morningFirstUnlock, .bluetoothConnected, .bluetoothDisconnected, .carplayConnected, .carplayDisconnected:
            return true
        case .geofenceEnter, .geofenceExit, .deviceUnlock, .wifiConnected, .workoutEnded, .calendarEventEnded:
            return true
        case .customContext, .unknownRequiresClarification:
            return false
        }
    }
}

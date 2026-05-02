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
    var exactDate: Date? = nil
    var approximateDate: Date? = nil
    var approximateWindow: NudgeTimeWindow? = nil
    var relativeOffsetSeconds: TimeInterval? = nil
    var recurrenceRule: ReminderRecurrenceRule? = nil
    var pendingLocationAlias: String? = nil
    var schedulingPolicy: ReminderSchedulingPolicy = .adaptive
    var confidenceTier: ReminderConfidenceTier = .medium
    var grammarClauses: ReminderGrammarClauses = ReminderGrammarClauses()
#if DEBUG
    var confidenceBreakdown: [String: Double] = [:]
#endif
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

struct ReminderGrammarClauses: Codable, Equatable, Hashable {
    var triggerClause: String?
    var actionClause: String?
    var timeClause: String?
    var recurrenceClause: String?
    var placeClause: String?
    var deviceContextClause: String?
}

struct ParsedTimeExpression: Equatable, Hashable {
    var exactDate: Date?
    var approximateDate: Date?
    var approximateWindow: NudgeTimeWindow?
    var relativeOffsetSeconds: TimeInterval?
    var sourcePhrase: String
    var explanation: String
    var confidence: Double
}

struct ParsedRecurrenceExpression: Equatable, Hashable {
    var rule: ReminderRecurrenceRule
    var sourcePhrase: String
    var explanation: String
    var confidence: Double
}

struct ParsedTriggerExpression: Equatable {
    var result: TriggerParser.Result
    var sourcePhrase: String
    var placeAlias: String?
    var pendingLocationAlias: String?
    var confidenceContribution: Double
}

struct GrammarParseResult: Equatable {
    var clauses = ReminderGrammarClauses()
    var actionText: String?
    var time: ParsedTimeExpression?
    var recurrence: ParsedRecurrenceExpression?
    var trigger: ParsedTriggerExpression?
    var explanation: String = ""
}

enum TurkishNormalizer {
    static let numberWords: [String: Int] = [
        "bir": 1, "iki": 2, "uc": 3, "üç": 3, "dort": 4, "dört": 4,
        "bes": 5, "beş": 5, "alti": 6, "altı": 6, "yedi": 7,
        "sekiz": 8, "dokuz": 9, "on": 10
    ]

    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .lowercased()
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }

    static func number(from token: String) -> Int? {
        Int(token) ?? numberWords[token]
    }
}

enum EnglishNormalizer {
    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ReminderIntentGrammar {
    static func parse(_ rawText: String, now: Date = .now) -> GrammarParseResult {
        var result = GrammarParseResult()
        let text = ReminderInputValidator.sanitize(rawText).trimmingCharacters(in: .whitespacesAndNewlines)
        var action = text

        if let trigger = PlaceExpressionParser.parse(text) ?? DeviceContextExpressionParser.parse(text) {
            result.trigger = trigger
            result.clauses.triggerClause = trigger.sourcePhrase
            result.clauses.placeClause = trigger.placeAlias
            if trigger.result.condition.type == .customContext {
                result.clauses.deviceContextClause = trigger.sourcePhrase
            }
            action = removePhrase(trigger.sourcePhrase, from: action)
        }

        if let recurrence = RecurrenceParser.parse(action, now: now) ?? RecurrenceParser.parse(text, now: now) {
            result.recurrence = recurrence
            result.clauses.recurrenceClause = recurrence.sourcePhrase
            action = removePhrase(recurrence.sourcePhrase, from: action)
        }

        if let time = TimeExpressionParser.parse(action, now: now) ?? TimeExpressionParser.parse(text, now: now) {
            result.time = time
            result.clauses.timeClause = time.sourcePhrase
            action = removePhrase(time.sourcePhrase, from: action)
        }

        action = stripReminderPrefix(from: action)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        result.actionText = action.isEmpty ? nil : action
        result.clauses.actionClause = result.actionText
        result.explanation = [result.trigger?.result.explanation, result.time?.explanation, result.recurrence?.explanation]
            .compactMap { $0 }
            .joined(separator: " ")
        return result
    }

    static func removePhrase(_ phrase: String, from text: String) -> String {
        let normalizedText = TurkishNormalizer.normalize(text)
        let normalizedPhrase = TurkishNormalizer.normalize(phrase)
        guard let range = normalizedText.range(of: normalizedPhrase) else { return text }
        let startOffset = normalizedText.distance(from: normalizedText.startIndex, to: range.lowerBound)
        let endOffset = normalizedText.distance(from: normalizedText.startIndex, to: range.upperBound)
        let start = text.index(text.startIndex, offsetBy: min(startOffset, text.count))
        let end = text.index(text.startIndex, offsetBy: min(endOffset, text.count))
        return String((text[..<start] + " " + text[end...]))
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func stripReminderPrefix(from text: String) -> String {
        let normalized = TurkishNormalizer.normalize(text)
        if ["remind me", "bana hatirlat", "hatirlat"].contains(normalized) {
            return ""
        }
        for prefix in ["remind me to ", "remind me ", "bana hatirlat ", "hatirlat "] where normalized.hasPrefix(prefix) {
            let idx = text.index(text.startIndex, offsetBy: min(prefix.count, text.count))
            return String(text[idx...])
        }
        return text
    }
}

enum TimeExpressionParser {
    private static let weekdayMap: [String: Int] = [
        "sunday": 1, "pazar": 1,
        "monday": 2, "pazartesi": 2,
        "tuesday": 3, "sali": 3,
        "wednesday": 4, "carsamba": 4,
        "thursday": 5, "persembe": 5,
        "friday": 6, "cuma": 6,
        "saturday": 7, "cumartesi": 7
    ]

    static func parse(_ text: String, now: Date = .now) -> ParsedTimeExpression? {
        let normalized = TurkishNormalizer.normalize(text)
        let tokens = TurkishNormalizer.tokens(text)
        let calendar = Calendar.current

        if let offset = relativeOffset(tokens: tokens, normalized: normalized) {
            let date = now.addingTimeInterval(offset.seconds)
            return ParsedTimeExpression(
                exactDate: date,
                approximateDate: nil,
                approximateWindow: nil,
                relativeOffsetSeconds: offset.seconds,
                sourcePhrase: offset.phrase,
                explanation: "Scheduled \(offset.display).",
                confidence: 0.94
            )
        }

        if contains(normalized, "yarin sabah") || contains(normalized, "tomorrow morning") {
            let day = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            return windowResult(day: day, window: morning, phrase: phrase(normalized, original: text, options: ["yarin sabah", "tomorrow morning"]), explanation: "Scheduled for tomorrow morning.")
        }
        if contains(normalized, "bugun") || contains(normalized, "today") {
            return ParsedTimeExpression(exactDate: nil, approximateDate: calendar.startOfDay(for: now), approximateWindow: nil, relativeOffsetSeconds: nil, sourcePhrase: phrase(normalized, original: text, options: ["bugun", "today"]), explanation: "Scheduled for today.", confidence: 0.78)
        }
        if contains(normalized, "yarin") || contains(normalized, "tomorrow") {
            let day = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            return ParsedTimeExpression(exactDate: nil, approximateDate: day, approximateWindow: nil, relativeOffsetSeconds: nil, sourcePhrase: phrase(normalized, original: text, options: ["yarin", "tomorrow"]), explanation: "Scheduled for tomorrow.", confidence: 0.82)
        }
        if containsAny(normalized, ["bu aksam", "aksama dogru", "tonight", "this evening"]) || tokens.contains("aksam") {
            return windowResult(day: calendar.startOfDay(for: now), window: evening, phrase: phrase(normalized, original: text, options: ["bu aksam", "aksama dogru", "tonight", "this evening", "aksam"]), explanation: "Scheduled for this evening.")
        }
        if containsAny(normalized, ["ogleden sonra", "afternoon"]) {
            return windowResult(day: calendar.startOfDay(for: now), window: afternoon, phrase: phrase(normalized, original: text, options: ["ogleden sonra", "afternoon"]), explanation: "Scheduled for the afternoon.")
        }
        if containsAny(normalized, ["haftaya", "next week"]) {
            let day = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
            return ParsedTimeExpression(exactDate: nil, approximateDate: day, approximateWindow: nil, relativeOffsetSeconds: nil, sourcePhrase: phrase(normalized, original: text, options: ["haftaya", "next week"]), explanation: "Scheduled for next week.", confidence: 0.8)
        }

        if let weekday = tokens.first(where: { weekdayMap[$0] != nil }), let target = weekdayMap[weekday] {
            let isNext = normalized.contains("gelecek \(weekday)") || normalized.contains("next \(weekday)")
            let day = nextWeekday(target, after: now, forceNextWeek: isNext)
            let source = isNext ? phrase(normalized, original: text, options: ["gelecek \(weekday)", "next \(weekday)"]) : weekday
            return ParsedTimeExpression(exactDate: nil, approximateDate: calendar.startOfDay(for: day), approximateWindow: nil, relativeOffsetSeconds: nil, sourcePhrase: source, explanation: isNext ? "Scheduled for next \(weekday)." : "Scheduled for \(weekday).", confidence: isNext ? 0.86 : 0.78)
        }

        return nil
    }

    private static let morning = NudgeTimeWindow(startHour: 8, endHour: 11, label: .morning)
    private static let afternoon = NudgeTimeWindow(startHour: 13, endHour: 17, label: .afternoon)
    private static let evening = NudgeTimeWindow(startHour: 18, endHour: 21, label: .evening)

    private static func relativeOffset(tokens: [String], normalized: String) -> (seconds: TimeInterval, phrase: String, display: String)? {
        for idx in tokens.indices {
            guard let amount = TurkishNormalizer.number(from: tokens[idx]), idx + 2 < tokens.count else { continue }
            let unit = tokens[idx + 1]
            let marker = tokens[idx + 2]
            if (unit.hasPrefix("dakika") || unit.hasPrefix("minute")), ["sonra", "later", "minutes"].contains(marker) || normalized.contains("in \(amount) minute") {
                return (TimeInterval(amount * 60), "\(tokens[idx]) \(unit) \(marker)", "in \(amount) minutes")
            }
            if (unit.hasPrefix("saat") || unit.hasPrefix("hour")), ["sonra", "later", "hours"].contains(marker) || normalized.contains("in \(amount) hour") {
                return (TimeInterval(amount * 3600), "\(tokens[idx]) \(unit) \(marker)", "in \(amount) hours")
            }
        }
        if tokens.count >= 3, tokens[0] == "in", let amount = TurkishNormalizer.number(from: tokens[1]) {
            let unit = tokens[2]
            if unit.hasPrefix("minute") { return (TimeInterval(amount * 60), "in \(tokens[1]) \(unit)", "in \(amount) minutes") }
            if unit.hasPrefix("hour") { return (TimeInterval(amount * 3600), "in \(tokens[1]) \(unit)", "in \(amount) hours") }
        }
        return nil
    }

    private static func windowResult(day: Date, window: NudgeTimeWindow, phrase: String, explanation: String) -> ParsedTimeExpression {
        ParsedTimeExpression(exactDate: nil, approximateDate: day, approximateWindow: window, relativeOffsetSeconds: nil, sourcePhrase: phrase, explanation: explanation, confidence: 0.88)
    }

    private static func nextWeekday(_ weekday: Int, after now: Date, forceNextWeek: Bool) -> Date {
        var components = DateComponents()
        components.weekday = weekday
        let calendar = Calendar.current
        let next = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTimePreservingSmallerComponents) ?? now
        if forceNextWeek || calendar.isDate(next, inSameDayAs: now) {
            return calendar.date(byAdding: .day, value: 7, to: next) ?? next
        }
        return next
    }

    private static func contains(_ normalized: String, _ phrase: String) -> Bool {
        normalized.contains(phrase)
    }

    private static func containsAny(_ normalized: String, _ phrases: [String]) -> Bool {
        phrases.contains { normalized.contains($0) }
    }

    private static func phrase(_ normalized: String, original: String, options: [String]) -> String {
        options.first { normalized.contains($0) } ?? original
    }
}

enum RecurrenceParser {
    static func parse(_ text: String, now: Date = .now) -> ParsedRecurrenceExpression? {
        let normalized = TurkishNormalizer.normalize(text)
        let tokens = TurkishNormalizer.tokens(text)

        if normalized.contains("her sabah") || normalized.contains("every morning") {
            let window = NudgeTimeWindow(startHour: 8, endHour: 11, label: .morning)
            return result(unit: .day, interval: 1, window: window, phrase: normalized.contains("her sabah") ? "her sabah" : "every morning", explanation: "Repeats every morning.")
        }
        if normalized.contains("her aksam") || normalized.contains("every evening") {
            let window = NudgeTimeWindow(startHour: 18, endHour: 21, label: .evening)
            return result(unit: .day, interval: 1, window: window, phrase: normalized.contains("her aksam") ? "her aksam" : "every evening", explanation: "Repeats every evening.")
        }
        if normalized.contains("iki gunde bir") || normalized.contains("every other day") {
            return result(unit: .day, interval: 2, window: nil, phrase: normalized.contains("iki gunde bir") ? "iki gunde bir" : "every other day", explanation: "Repeats every other day.")
        }
        if let weekly = countBefore(tokens: tokens, first: "haftada", second: "kez") ?? countBeforeEnglish(tokens: tokens, unit: "week") {
            let rule = ReminderRecurrenceRule(unit: .week, interval: 1, timesPerUnit: weekly.count, sourcePhrase: weekly.phrase)
            return ParsedRecurrenceExpression(rule: rule, sourcePhrase: weekly.phrase, explanation: "Repeats \(weekly.count) times a week.", confidence: 0.9)
        }
        if normalized.contains("ayda bir") || normalized.contains("once a month") {
            return result(unit: .month, interval: 1, window: nil, phrase: normalized.contains("ayda bir") ? "ayda bir" : "once a month", explanation: "Repeats once a month.")
        }
        return nil
    }

    private static func result(unit: ReminderRecurrenceRule.Unit, interval: Int, window: NudgeTimeWindow?, phrase: String, explanation: String) -> ParsedRecurrenceExpression {
        let rule = ReminderRecurrenceRule(unit: unit, interval: interval, preferredWindow: window, sourcePhrase: phrase)
        return ParsedRecurrenceExpression(rule: rule, sourcePhrase: phrase, explanation: explanation, confidence: 0.91)
    }

    private static func countBefore(tokens: [String], first: String, second: String) -> (count: Int, phrase: String)? {
        guard let idx = tokens.firstIndex(of: first), idx + 2 < tokens.count, let count = TurkishNormalizer.number(from: tokens[idx + 1]), tokens[idx + 2] == second else { return nil }
        return (count, "\(first) \(tokens[idx + 1]) \(second)")
    }

    private static func countBeforeEnglish(tokens: [String], unit: String) -> (count: Int, phrase: String)? {
        guard tokens.count >= 4 else { return nil }
        for idx in 0...(tokens.count - 4) {
            if let count = TurkishNormalizer.number(from: tokens[idx]),
               tokens[idx + 1].hasPrefix("time"),
               tokens[idx + 2] == "a",
               tokens[idx + 3].hasPrefix(unit) {
                return (count, "\(tokens[idx]) \(tokens[idx + 1]) a \(tokens[idx + 3])")
            }
        }
        return nil
    }
}

enum PlaceExpressionParser {
    struct PlacePattern {
        let aliases: [String]
        let normalizedAlias: String
        let displayAlias: String
        let category: String
        let type: TriggerType
        let confidence: Double
    }

    static func parse(_ text: String) -> ParsedTriggerExpression? {
        let normalized = TurkishNormalizer.normalize(text)
        let patterns: [PlacePattern] = [
            .init(aliases: ["eve gelince", "eve varinca", "eve gidince", "when i get home", "when i arrive home", "when i come home"], normalizedAlias: "home", displayAlias: "Home", category: "home", type: .geofenceEnter, confidence: 0.9),
            .init(aliases: ["evden cikinca", "evden ayrilinca", "when i leave home"], normalizedAlias: "home", displayAlias: "Home", category: "home", type: .geofenceExit, confidence: 0.88),
            .init(aliases: ["ise gidince", "ise varinca", "ofise varinca", "when i arrive at work", "when i get to work", "when i arrive at the office"], normalizedAlias: "work", displayAlias: "Work", category: "work", type: .geofenceEnter, confidence: 0.86),
            .init(aliases: ["isten cikinca", "isten ayrilinca", "ofisten ayrilinca", "when i leave work", "when i leave the office"], normalizedAlias: "work", displayAlias: "Work", category: "work", type: .geofenceExit, confidence: 0.85),
            .init(aliases: ["spora gidince", "spora varinca", "spor salonuna gidince", "spor salonuna varinca", "when i get to the gym", "when i arrive at the gym"], normalizedAlias: "gym", displayAlias: "Gym", category: "gym", type: .geofenceEnter, confidence: 0.88),
            .init(aliases: ["spordan cikinca", "spordan ayrilinca", "spor salonundan cikinca", "spor salonundan ayrilinca", "gymden cikinca", "gymden ayrilinca", "when i leave the gym"], normalizedAlias: "gym", displayAlias: "Gym", category: "gym", type: .geofenceExit, confidence: 0.9),
            .init(aliases: ["markete gidince", "markete varinca", "when i get to the market", "when i arrive at the market"], normalizedAlias: "market", displayAlias: "Market", category: "market", type: .geofenceEnter, confidence: 0.84),
            .init(aliases: ["marketten cikinca", "marketten ayrilinca", "when i leave the market"], normalizedAlias: "market", displayAlias: "Market", category: "market", type: .geofenceExit, confidence: 0.82),
            .init(aliases: ["eczaneye gidince", "eczaneye varinca", "when i arrive at the pharmacy", "when i get to the pharmacy"], normalizedAlias: "pharmacy", displayAlias: "Pharmacy", category: "pharmacy", type: .geofenceEnter, confidence: 0.84),
            .init(aliases: ["eczaneden cikinca", "eczaneden ayrilinca", "when i leave the pharmacy"], normalizedAlias: "pharmacy", displayAlias: "Pharmacy", category: "pharmacy", type: .geofenceExit, confidence: 0.82),
            .init(aliases: ["okula gidince", "okula varinca", "when i get to school"], normalizedAlias: "school", displayAlias: "School", category: "school", type: .geofenceEnter, confidence: 0.8),
            .init(aliases: ["ofise gidince", "ofise varinca", "when i get to the office"], normalizedAlias: "office", displayAlias: "Office", category: "office", type: .geofenceEnter, confidence: 0.8),
            .init(aliases: ["kafeye gidince", "kafeye varinca", "cafeye gidince", "when i get to the cafe"], normalizedAlias: "cafe", displayAlias: "Cafe", category: "cafe", type: .geofenceEnter, confidence: 0.8),
            .init(aliases: ["doktora gidince", "doktora varinca", "when i get to the doctor"], normalizedAlias: "doctor", displayAlias: "Doctor", category: "doctor", type: .geofenceEnter, confidence: 0.8),
            .init(aliases: ["hastaneye gidince", "hastaneye varinca", "when i get to the hospital"], normalizedAlias: "hospital", displayAlias: "Hospital", category: "hospital", type: .geofenceEnter, confidence: 0.8)
        ]

        for pattern in patterns {
            if let source = pattern.aliases.first(where: { normalized.contains($0) }) {
                return place(pattern, sourcePhrase: source)
            }
        }
        return nil
    }

    private static func place(_ pattern: PlacePattern, sourcePhrase: String) -> ParsedTriggerExpression {
        let metadata = [
            "actionable": "true",
            "normalizedAlias": pattern.normalizedAlias,
            "displayAlias": pattern.displayAlias,
            "placeCategory": pattern.category,
            "sourcePhrase": sourcePhrase,
            "pendingLocationAlias": pattern.normalizedAlias
        ]
        let condition = TriggerCondition(
            type: pattern.type,
            subject: pattern.normalizedAlias,
            locationAlias: pattern.normalizedAlias,
            metadata: metadata,
            requiresPermission: [.notifications, .location],
            minimumConfidence: 0.7,
            cooldownSeconds: 3600
        )
        let result = TriggerParser.Result(
            condition: condition,
            reminderText: nil,
            confidence: pattern.confidence,
            needsClarification: true,
            clarifyingQuestion: "Where should I remember as \(pattern.displayAlias)?",
            explanation: pattern.type == .geofenceEnter ? "Understood as: when you arrive at \(pattern.displayAlias)." : "Understood as: when you leave \(pattern.displayAlias)."
        )
        return ParsedTriggerExpression(result: result, sourcePhrase: sourcePhrase, placeAlias: pattern.normalizedAlias, pendingLocationAlias: pattern.normalizedAlias, confidenceContribution: 0.2)
    }
}

enum DeviceContextExpressionParser {
    static func parse(_ text: String) -> ParsedTriggerExpression? {
        let normalized = TurkishNormalizer.normalize(text)
        if let source = first(in: normalized, ["sarja takinca", "telefonu sarja takinca", "when i plug in", "when charging starts"]) {
            return event(.chargingStarted, source: source, confidence: 0.92, permissions: [.notifications], explanation: "Understood as: when charging starts.")
        }
        if let source = first(in: normalized, ["arabaya binince", "arabama binince", "when i get in my car", "when carplay connects"]) {
            return event(.carplayConnected, source: source, confidence: 0.82, permissions: [.notifications, .bluetooth], explanation: "Understood as: when you get in the car.")
        }
        if let source = first(in: normalized, ["arabadan inince", "arabadan cikinca", "when i leave my car", "when carplay disconnects"]) {
            return event(.carplayDisconnected, source: source, confidence: 0.82, permissions: [.notifications, .bluetooth], explanation: "Understood as: when you leave the car.")
        }
        if let source = first(in: normalized, ["toplantidan sonra", "toplanti bitince", "after my meeting", "after the meeting", "when my meeting ends"]) {
            return event(.calendarEventEnded, source: source, confidence: 0.74, permissions: [.notifications, .calendar], explanation: "Needs calendar access before it can work.")
        }
        if let source = first(in: normalized, ["laptopu acinca", "laptopumu acinca", "bilgisayarimi acinca", "bilgisayarimin kapagini acinca", "when i open my laptop", "open my laptop"]) {
            let condition = TriggerCondition(
                type: .customContext,
                subject: "laptop_opened",
                metadata: ["fallback": "companion_app_bluetooth_wifi_manual", "actionable": "false", "sourcePhrase": source],
                requiresPermission: [.notifications, .bluetooth, .localNetwork],
                minimumConfidence: 0.75
            )
            let result = TriggerParser.Result(
                condition: condition,
                reminderText: nil,
                confidence: 0.45,
                needsClarification: true,
                clarifyingQuestion: "Laptop triggers need a future companion setup.",
                explanation: "Laptop triggers need a future companion setup."
            )
            return ParsedTriggerExpression(result: result, sourcePhrase: source, placeAlias: nil, pendingLocationAlias: nil, confidenceContribution: -0.25)
        }
        if let source = first(in: normalized, ["benzinden sonra", "benzin alinca", "yakit alinca", "when i get gas", "when i buy fuel", "at the gas station"]) {
            let condition = TriggerCondition(
                type: .customContext,
                subject: "fuel_stop",
                metadata: ["fallback": "gas_station_location_car_bluetooth_confirmation", "actionable": "false", "sourcePhrase": source],
                requiresPermission: [.notifications, .location, .bluetooth],
                minimumConfidence: 0.8
            )
            let result = TriggerParser.Result(
                condition: condition,
                reminderText: nil,
                confidence: 0.42,
                needsClarification: true,
                clarifyingQuestion: "Fuel-stop reminders need confirmation or setup first.",
                explanation: "Fuel stops are not supported as an automatic local trigger yet."
            )
            return ParsedTriggerExpression(result: result, sourcePhrase: source, placeAlias: nil, pendingLocationAlias: nil, confidenceContribution: -0.25)
        }
        return nil
    }

    private static func event(_ type: TriggerType, source: String, confidence: Double, permissions: [PermissionKind], explanation: String) -> ParsedTriggerExpression {
        let condition = TriggerCondition(
            type: type,
            subject: type.rawValue,
            metadata: ["actionable": "true", "sourcePhrase": source],
            requiresPermission: permissions,
            minimumConfidence: 0.65,
            cooldownSeconds: type == .morningFirstUnlock ? 22 * 3600 : 3600
        )
        let result = TriggerParser.Result(condition: condition, reminderText: nil, confidence: confidence, needsClarification: false, clarifyingQuestion: nil, explanation: explanation)
        return ParsedTriggerExpression(result: result, sourcePhrase: source, placeAlias: nil, pendingLocationAlias: nil, confidenceContribution: 0.18)
    }

    private static func first(in normalized: String, _ phrases: [String]) -> String? {
        phrases.first { normalized.contains($0) }
    }
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
    static func parse(_ rawText: String, history: [Reminder] = [], now: Date = .now) -> ParsedReminderIntent {
        let text = ReminderInputValidator.sanitize(rawText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let grammar = ReminderIntentGrammar.parse(text, now: now)
        let analysis = TextAnalyzer.analyze(text)
        let triggerResult = grammar.trigger?.result ?? TriggerParser.parse(text)
        let category = ReminderCategoryClassifier.classify(text: text, analysis: analysis)
        let cadence = cadenceForGrammar(grammar, text: text, category: category, analysis: analysis)
        let window = NudgeDecisionEngine.suggestedWindow(
            text: grammar.actionText ?? text,
            category: category,
            analysis: analysis,
            history: history
        )

        let hasTrigger = triggerResult.condition.type != .unknownRequiresClarification
        let minConfidence = triggerResult.condition.minimumConfidence
        let isSupported = triggerResult.condition.type.isSupportedWithoutClarification
        let cleanedText = grammar.actionText ?? triggerResult.reminderText ?? stripReminderPrefix(from: text)
        let readiness = hasTrigger ? triggerReadiness(for: triggerResult) : nil
        let ambiguity = ambiguityFlags(triggerResult: triggerResult, hasTrigger: hasTrigger)
        let requiredPermissions = hasTrigger ? triggerResult.condition.requiresPermission : [.notifications]
        let recurrence = grammar.recurrence == nil ? recurrenceExpectation(cadence: cadence, hasTrigger: hasTrigger, text: text) : .recurring
        let intent = inferIntent(from: cleanedText, category: category)
        let urgency = inferUrgency(from: text)
        let resolvedWindow = grammar.recurrence?.rule.preferredWindow ?? grammar.time?.approximateWindow ?? window
        let policy = schedulingPolicy(grammar: grammar, hasTrigger: hasTrigger, isSupported: isSupported)
        let confidenceDetails = confidenceBreakdown(grammar: grammar, analysis: analysis, triggerResult: hasTrigger ? triggerResult : nil, policy: policy)
        let confidence = confidenceDetails.values.reduce(0, +).clamped(to: 0...1)
        let confidenceTier = tier(for: confidence)
        let summary = summary(
            text: cleanedText,
            kind: hasTrigger ? .eventBased : kindForTimeReminder(text: text, cadence: cadence, grammar: grammar),
            category: category,
            triggerResult: hasTrigger ? triggerResult : nil,
            recurrence: recurrence,
            grammar: grammar
        )

        if hasTrigger && triggerResult.confidence < minConfidence {
            var parsed = ParsedReminderIntent(
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
                triggerReadiness: readiness,
                exactDate: grammar.time?.exactDate,
                approximateDate: grammar.time?.approximateDate,
                approximateWindow: grammar.time?.approximateWindow,
                relativeOffsetSeconds: grammar.time?.relativeOffsetSeconds,
                recurrenceRule: grammar.recurrence?.rule,
                pendingLocationAlias: grammar.trigger?.pendingLocationAlias,
                schedulingPolicy: .pendingSetup,
                confidenceTier: .low,
                grammarClauses: grammar.clauses
            )
#if DEBUG
            parsed.confidenceBreakdown = confidenceDetails
#endif
            return parsed
        }

        let kind = hasTrigger ? ReminderKind.eventBased : kindForTimeReminder(text: text, cadence: cadence, grammar: grammar)
        var parsed = ParsedReminderIntent(
            reminderText: cleanedText,
            kind: kind,
            category: category,
            suggestedCadence: cadence,
            timeWindow: hasTrigger ? nil : resolvedWindow,
            trigger: hasTrigger ? ReminderTrigger(condition: triggerResult.condition, confidence: triggerResult.confidence) : nil,
            confidence: confidence,
            needsClarification: hasTrigger ? triggerResult.needsClarification : confidenceTier == .low,
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
            triggerReadiness: readiness,
            exactDate: grammar.time?.exactDate,
            approximateDate: grammar.time?.approximateDate,
            approximateWindow: grammar.time?.approximateWindow,
            relativeOffsetSeconds: grammar.time?.relativeOffsetSeconds,
            recurrenceRule: grammar.recurrence?.rule,
            pendingLocationAlias: grammar.trigger?.pendingLocationAlias,
            schedulingPolicy: policy,
            confidenceTier: confidenceTier,
            grammarClauses: grammar.clauses
        )
#if DEBUG
        parsed.confidenceBreakdown = confidenceDetails
#endif
        return parsed
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

    private static func cadenceForGrammar(_ grammar: GrammarParseResult, text: String, category: ReminderCategory, analysis: TextAnalysis) -> SuggestedCadence {
        guard let recurrence = grammar.recurrence else {
            return CadenceController.defaultCadence(for: text, category: category, analysis: analysis)
        }
        if recurrence.rule.unit == .day, recurrence.rule.interval == 1 { return .daily }
        if recurrence.rule.unit == .week { return .fewTimesPerWeek }
        return .occasional
    }

    private static func kindForTimeReminder(text: String, cadence: SuggestedCadence, grammar: GrammarParseResult) -> ReminderKind {
        if grammar.recurrence != nil { return .timeBased }
        if grammar.time?.exactDate != nil || grammar.time?.relativeOffsetSeconds != nil || grammar.time?.approximateDate != nil {
            return .oneOff
        }
        let lower = TriggerParser.normalize(text)
        if lower.contains("bugun") || lower.contains("today") || lower.contains("tonight") { return .oneOff }
        return cadence == .oneOff ? .oneOff : .timeBased
    }

    private static func schedulingPolicy(grammar: GrammarParseResult, hasTrigger: Bool, isSupported: Bool) -> ReminderSchedulingPolicy {
        if hasTrigger { return isSupported ? .eventTrigger : .unsupported }
        if grammar.recurrence != nil { return .recurring }
        if grammar.time?.relativeOffsetSeconds != nil { return .relativeOffset }
        if grammar.time?.exactDate != nil { return .exactDate }
        if grammar.time?.approximateWindow != nil || grammar.time?.approximateDate != nil { return .approximateWindow }
        return .adaptive
    }

    private static func confidenceBreakdown(
        grammar: GrammarParseResult,
        analysis: TextAnalysis,
        triggerResult: TriggerParser.Result?,
        policy: ReminderSchedulingPolicy
    ) -> [String: Double] {
        var scores: [String: Double] = ["base": 0.5, "category": min(0.1, analysis.confidence * 0.1)]
        if grammar.clauses.actionClause != nil { scores["action_clause"] = 0.12 }
        if let time = grammar.time { scores["time_expression"] = min(0.2, time.confidence * 0.2) }
        if let recurrence = grammar.recurrence { scores["recurrence_expression"] = min(0.2, recurrence.confidence * 0.2) }
        if let trigger = triggerResult {
            scores["trigger_expression"] = min(0.28, trigger.confidence * 0.28)
            if trigger.condition.locationAlias != nil { scores["known_place_alias"] = 0.08 }
            if trigger.condition.type == .customContext { scores["unsupported_context_penalty"] = -0.28 }
            if trigger.condition.locationAlias != nil { scores["missing_setup_penalty"] = -0.04 }
        }
        if policy == .adaptive { scores["grammar_absent_penalty"] = -0.05 }
        return scores
    }

    private static func tier(for confidence: Double) -> ReminderConfidenceTier {
        if confidence >= 0.75 { return .high }
        if confidence >= 0.5 { return .medium }
        return .low
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
        recurrence: RecurrenceExpectation,
        grammar: GrammarParseResult
    ) -> String {
        if let triggerResult {
            return triggerResult.explanation
        }
        if let time = grammar.time {
            return time.explanation
        }
        if let recurrence = grammar.recurrence {
            return recurrence.explanation
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

enum ReminderPriorityScorer {
    static func score(reminder: Reminder, candidateDate: Date, context: NudgeDecisionContext) -> Double {
        let normalized = TriggerParser.normalize(reminder.text)
        var score = 0.2

        if normalized.contains("urgent") || normalized.contains("asap") || normalized.contains("acil") {
            score += 0.35
        }

        score += min(0.25, (reminder.schedule?.confidence ?? reminder.triggerDefinition?.confidence ?? 0.4) * 0.25)

        let distance = candidateDate.timeIntervalSince(context.now)
        if distance <= 0 {
            score += 0.22
        } else {
            score += max(0, 1 - min(distance, 3600) / 3600) * 0.18
        }

        if let event = context.triggeredBy,
           let condition = reminder.triggerDefinition?.condition,
           TriggerExecutionPolicy.matches(event, condition: condition) {
            score += 0.28
        }

        let recentFatigue = reminder.interactions.suffix(5).reduce(0.0) { partial, interaction in
            switch interaction.type {
            case .completed: return partial
            case .skipped: return partial + 0.07
            case .ignored: return partial + 0.12
            }
        }
        score -= min(0.3, recentFatigue)

        let categoryKey = reminder.category.rawValue
        score -= min(0.25, Double(context.settings.userRhythmProfile.mistimingStreakByCategory[categoryKey] ?? 0) * 0.05)

        let hour = Calendar.current.component(.hour, from: candidateDate)
        let rhythmScore = context.settings.userRhythmProfile.preferredHoursByCategory[categoryKey]?[hour] ?? 0
        score += max(-0.15, min(0.15, rhythmScore * 0.12))

        return score
    }
}

enum ReminderConflictCoordinator {
    struct Resolution: Hashable {
        var date: Date
        var status: NudgePlanStatus
        var explanationCode: NudgeExplanationCode
        var explanationText: String
        var groupKey: String?
        var anchorReminderId: UUID?
        var rank: Int?
        var resolvedAt: Date?
    }

    static let conflictWindowSeconds: TimeInterval = 15 * 60
    static let staggerSeconds: TimeInterval = AdaptiveEngine.clusterGapSeconds

    static func resolve(
        reminder: Reminder,
        candidateDate: Date,
        context: NudgeDecisionContext,
        explanationCode: NudgeExplanationCode,
        explanationText: String
    ) -> Resolution {
        let groupKey = key(for: reminder, candidateDate: candidateDate, context: context)

        if let schedule = reminder.schedule,
           schedule.conflictGroupKey == groupKey,
           let resolvedDate = schedule.conflictResolvedFireDate,
           let rank = schedule.conflictResolvedRank,
           resolvedDate >= context.now.addingTimeInterval(-60) {
            return Resolution(
                date: resolvedDate,
                status: rank == 0 ? .scheduled : .clustered,
                explanationCode: rank == 0 ? explanationCode : .delayedDueToAnotherReminder,
                explanationText: rank == 0 ? explanationText : "Delayed because another reminder was more timely.",
                groupKey: groupKey,
                anchorReminderId: schedule.conflictAnchorReminderId,
                rank: rank,
                resolvedAt: schedule.conflictResolvedAt ?? context.now
            )
        }

        let competitors = competingReminders(for: reminder, candidateDate: candidateDate, groupKey: groupKey, context: context)
        guard competitors.count > 1 else {
            return Resolution(date: candidateDate, status: .scheduled, explanationCode: explanationCode, explanationText: explanationText, groupKey: nil, anchorReminderId: nil, rank: nil, resolvedAt: nil)
        }

        let ranked = competitors.sorted { lhs, rhs in
            let lhsScore = ReminderPriorityScorer.score(reminder: lhs.reminder, candidateDate: lhs.date, context: context)
            let rhsScore = ReminderPriorityScorer.score(reminder: rhs.reminder, candidateDate: rhs.date, context: context)
            if lhsScore == rhsScore {
                return lhs.reminder.id.uuidString < rhs.reminder.id.uuidString
            }
            return lhsScore > rhsScore
        }

        guard let rank = ranked.firstIndex(where: { $0.reminder.id == reminder.id }) else {
            return Resolution(date: candidateDate, status: .scheduled, explanationCode: explanationCode, explanationText: explanationText, groupKey: nil, anchorReminderId: nil, rank: nil, resolvedAt: nil)
        }

        let anchorDate = firstNonQuietDate(after: ranked[0].date, settings: context.settings)
        let resolved = firstNonQuietDate(after: anchorDate.addingTimeInterval(TimeInterval(rank) * staggerSeconds), settings: context.settings)
        let anchorId = ranked[0].reminder.id
        if rank == 0 {
            return Resolution(date: resolved, status: .scheduled, explanationCode: explanationCode, explanationText: explanationText, groupKey: groupKey, anchorReminderId: anchorId, rank: 0, resolvedAt: context.now)
        }

        return Resolution(
            date: resolved,
            status: .clustered,
            explanationCode: .delayedDueToAnotherReminder,
            explanationText: "Delayed because another reminder was more timely.",
            groupKey: groupKey,
            anchorReminderId: anchorId,
            rank: rank,
            resolvedAt: context.now
        )
    }

    static func orderedDueReminders(_ reminders: [Reminder], context: NudgeDecisionContext) -> [Reminder] {
        reminders
            .filter { !$0.isDone && ($0.nextNudgeAt ?? .distantFuture) <= context.now }
            .sorted { lhs, rhs in
                let lhsDate = lhs.nextNudgeAt ?? context.now
                let rhsDate = rhs.nextNudgeAt ?? context.now
                let lhsScore = ReminderPriorityScorer.score(reminder: lhs, candidateDate: lhsDate, context: context)
                let rhsScore = ReminderPriorityScorer.score(reminder: rhs, candidateDate: rhsDate, context: context)
                if lhsScore == rhsScore { return lhsDate < rhsDate }
                return lhsScore > rhsScore
            }
    }

    private struct Competitor {
        var reminder: Reminder
        var date: Date
    }

    private static func competingReminders(for reminder: Reminder, candidateDate: Date, groupKey: String, context: NudgeDecisionContext) -> [Competitor] {
        var competitors = [Competitor(reminder: reminder, date: candidateDate)]
        for other in context.allReminders where other.id != reminder.id && !other.isDone {
            if let event = context.triggeredBy,
               let condition = other.triggerDefinition?.condition,
               TriggerExecutionPolicy.matches(event, condition: condition) {
                competitors.append(Competitor(reminder: other, date: event.createdAt.addingTimeInterval(5)))
                continue
            }
            if let otherKey = other.schedule?.conflictGroupKey, otherKey == groupKey, let date = other.schedule?.conflictResolvedFireDate ?? other.nextNudgeAt {
                competitors.append(Competitor(reminder: other, date: date))
                continue
            }
            guard let date = other.nextNudgeAt else { continue }
            if abs(date.timeIntervalSince(candidateDate)) < conflictWindowSeconds {
                competitors.append(Competitor(reminder: other, date: date))
            }
        }
        return competitors
    }

    private static func key(for reminder: Reminder, candidateDate: Date, context: NudgeDecisionContext) -> String {
        if let event = context.triggeredBy {
            return "event:\(event.type.rawValue):\(event.subject ?? ""):\(Int(event.createdAt.timeIntervalSince1970 / conflictWindowSeconds))"
        }
        let bucket = Int(candidateDate.timeIntervalSince1970 / conflictWindowSeconds)
        return "time:\(bucket)"
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
                explanation: .triggeredByEvent,
                context: context
            )
        }

        if let grammarResult = planFromGrammarSchedule(reminder: reminder, context: context) {
            return grammarResult
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
            return scheduled(reminder: reminder, date: date, selected: selectedWindow(for: reminder, settings: settings), explanation: .recentMistimedEasedBack, context: context)
        }

        let selected = selectedWindow(for: reminder, settings: settings)
        let candidate = nextAllowedDate(for: selected.window, reminder: reminder, context: context)
        let candidateHour = calendar.component(.hour, from: candidate)
        if AdaptiveEngine.isQuiet(hour: candidateHour, settings: settings) {
            let shifted = firstNonQuietDate(after: candidate, settings: settings)
            return scheduled(reminder: reminder, date: shifted, selected: selected, explanation: .quietHoursDelayed, context: context)
        }

        if isClustered(candidate, reminder: reminder, allReminders: context.allReminders) {
            let shifted = candidate.addingTimeInterval(AdaptiveEngine.clusterGapSeconds)
            return scheduled(reminder: reminder, date: firstNonQuietDate(after: shifted, settings: settings), selected: selected, explanation: .notificationClusterPrevented, context: context)
        }

        let explanation: NudgeExplanationCode = context.triggeredBy == nil ? selected.explanation : .triggeredByEvent
        return scheduled(reminder: reminder, date: candidate, selected: selected, explanation: explanation, context: context)
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

    private static func planFromGrammarSchedule(reminder: Reminder, context: NudgeDecisionContext) -> NudgePlanResult? {
        guard let schedule = reminder.schedule, let policy = schedule.schedulingPolicy else { return nil }
        let confidence = schedule.confidence ?? 0.6
        if schedule.confidenceTier == .low {
            return notScheduled(.needsClarification, .needsClarification, schedule.grammarExplanation ?? "This reminder needs clarification before it can be scheduled.", confidence: confidence)
        }
        switch policy {
        case .exactDate, .relativeOffset:
            guard let date = schedule.exactDate else { return nil }
            guard date > context.now else {
                return notScheduled(.needsClarification, .needsClarification, "The parsed time has already passed.", confidence: confidence)
            }
            let window = NudgeTimeWindow.around(hour: Calendar.current.component(.hour, from: date), label: TimeWindowLabel.label(for: Calendar.current.component(.hour, from: date)))
            let text = schedule.grammarExplanation ?? "Scheduled from the parsed time."
            return scheduled(reminder: reminder, date: date, selected: (window: window, confidence: confidence, explanation: .parsedTimeHint), explanationText: text, context: context)
        case .approximateWindow:
            guard let window = schedule.preferredWindow ?? schedule.recurrenceRule?.preferredWindow else { return nil }
            let targetDay = schedule.approximateDate ?? context.now
            let widened = schedule.confidenceTier == .medium ? widen(window) : window
            let date = date(in: widened, on: targetDay, after: context.now)
            let text = schedule.grammarExplanation ?? "Scheduled in the parsed time window."
            return scheduled(reminder: reminder, date: date, selected: (window: widened, confidence: confidence, explanation: .parsedTimeHint), explanationText: text, context: context)
        case .recurring:
            guard let rule = schedule.recurrenceRule else { return nil }
            let window = schedule.preferredWindow ?? rule.preferredWindow ?? NudgeTimeWindow.around(hour: reminder.category.defaultHours.first ?? 10, label: .lateMorning)
            let widened = schedule.confidenceTier == .medium ? widen(window) : window
            let date = nextRecurrenceDate(rule: rule, window: widened, reminder: reminder, context: context)
            let text = schedule.grammarExplanation ?? "Scheduled from the parsed recurrence rule."
            return scheduled(reminder: reminder, date: date, selected: (window: widened, confidence: confidence, explanation: .parsedTimeHint), explanationText: text, context: context)
        case .pendingSetup:
            return notScheduled(.needsClarification, .needsClarification, schedule.grammarExplanation ?? "This reminder needs setup before it can run.", confidence: confidence)
        case .unsupported:
            return notScheduled(.unsupported, .unsupportedTrigger, schedule.grammarExplanation ?? "This trigger is not supported locally yet.", confidence: confidence)
        case .eventTrigger, .adaptive:
            return nil
        }
    }

    private static func date(in window: NudgeTimeWindow, on day: Date, after now: Date) -> Date {
        let calendar = Calendar.current
        let hour = (window.startHour + window.endHour) / 2
        let candidate = calendar.date(bySettingHour: hour, minute: 15, second: 0, of: day) ?? now.addingTimeInterval(300)
        if candidate > now { return candidate }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? now.addingTimeInterval(86400)
        return calendar.date(bySettingHour: hour, minute: 15, second: 0, of: tomorrow) ?? tomorrow
    }

    private static func nextRecurrenceDate(rule: ReminderRecurrenceRule, window: NudgeTimeWindow, reminder: Reminder, context: NudgeDecisionContext) -> Date {
        let calendar = Calendar.current
        let base = reminder.nextNudgeAt ?? context.now
        let candidateDay: Date
        switch rule.unit {
        case .day:
            candidateDay = calendar.date(byAdding: .day, value: reminder.nextNudgeAt == nil ? 0 : rule.interval, to: calendar.startOfDay(for: base)) ?? context.now
        case .week:
            let spacing = max(1, 7 / max(1, rule.timesPerUnit ?? 1))
            candidateDay = calendar.date(byAdding: .day, value: reminder.nextNudgeAt == nil ? 0 : spacing, to: calendar.startOfDay(for: base)) ?? context.now
        case .month:
            candidateDay = calendar.date(byAdding: .month, value: reminder.nextNudgeAt == nil ? 0 : rule.interval, to: calendar.startOfDay(for: base)) ?? context.now
        }
        return date(in: window, on: candidateDay, after: context.now)
    }

    private static func widen(_ window: NudgeTimeWindow) -> NudgeTimeWindow {
        NudgeTimeWindow(startHour: max(0, window.startHour - 1), endHour: min(23, window.endHour + 1), label: window.label)
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
        explanation: NudgeExplanationCode,
        context: NudgeDecisionContext? = nil
    ) -> NudgePlanResult {
        let text = explanationText(for: explanation)
        let resolved: ReminderConflictCoordinator.Resolution
        if let context {
            resolved = ReminderConflictCoordinator.resolve(
                reminder: reminder,
                candidateDate: date,
                context: context,
                explanationCode: explanation,
                explanationText: text
            )
        } else {
            resolved = ReminderConflictCoordinator.Resolution(date: date, status: .scheduled, explanationCode: explanation, explanationText: text, groupKey: nil, anchorReminderId: nil, rank: nil, resolvedAt: nil)
        }
        let plan = NudgePlan(
            reminderId: reminder.id,
            nextFireDate: resolved.date,
            window: selected.window,
            confidence: selected.confidence,
            explanation: NudgeExplanation(code: resolved.explanationCode, text: resolved.explanationText)
        )
        return NudgePlanResult(
            status: resolved.status,
            plan: plan,
            explanation: plan.explanation,
            confidence: selected.confidence,
            conflictGroupKey: resolved.groupKey,
            conflictAnchorReminderId: resolved.anchorReminderId,
            conflictResolvedRank: resolved.rank,
            conflictResolvedAt: resolved.resolvedAt
        )
    }

    private static func scheduled(
        reminder: Reminder,
        date: Date,
        selected: (window: NudgeTimeWindow, confidence: Double, explanation: NudgeExplanationCode),
        explanationText: String,
        context: NudgeDecisionContext? = nil
    ) -> NudgePlanResult {
        let resolved: ReminderConflictCoordinator.Resolution
        if let context {
            resolved = ReminderConflictCoordinator.resolve(
                reminder: reminder,
                candidateDate: date,
                context: context,
                explanationCode: selected.explanation,
                explanationText: explanationText
            )
        } else {
            resolved = ReminderConflictCoordinator.Resolution(date: date, status: .scheduled, explanationCode: selected.explanation, explanationText: explanationText, groupKey: nil, anchorReminderId: nil, rank: nil, resolvedAt: nil)
        }
        let explanation = NudgeExplanation(code: resolved.explanationCode, text: resolved.explanationText)
        let plan = NudgePlan(
            reminderId: reminder.id,
            nextFireDate: resolved.date,
            window: selected.window,
            confidence: selected.confidence,
            explanation: explanation
        )
        return NudgePlanResult(
            status: resolved.status,
            plan: plan,
            explanation: explanation,
            confidence: selected.confidence,
            conflictGroupKey: resolved.groupKey,
            conflictAnchorReminderId: resolved.anchorReminderId,
            conflictResolvedRank: resolved.rank,
            conflictResolvedAt: resolved.resolvedAt
        )
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
        case .delayedDueToAnotherReminder: return "Delayed because another reminder was more timely."
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

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}

import Foundation

enum TriggerParser {
    struct Result: Equatable {
        let condition: TriggerCondition
        let reminderText: String?
        let confidence: Double
        let needsClarification: Bool
        let clarifyingQuestion: String?
        let explanation: String
    }

    static func parse(_ rawText: String) -> Result {
        let text = ReminderInputValidator.sanitize(rawText)
        let lower = normalize(text)

        if containsAny(lower, ["eve varinca", "eve gelince", "eve ulasinca", "when i get home", "when i arrive home", "when i come home"]) {
            return place(.geofenceEnter, alias: "home", raw: text, confidence: 0.88)
        }
        if containsAny(lower, ["evden cikinca", "evden ayrilinca", "when i leave home"]) {
            return place(.geofenceExit, alias: "home", raw: text, confidence: 0.86)
        }
        if containsAny(lower, ["ise varinca", "ofise varinca", "when i arrive at work", "when i get to work"]) {
            return place(.geofenceEnter, alias: "work", raw: text, confidence: 0.85)
        }
        if containsAny(lower, ["isten cikinca", "ofisten ayrilinca", "when i leave work", "when i leave the office"]) {
            return place(.geofenceExit, alias: "work", raw: text, confidence: 0.84)
        }
        if containsAny(lower, ["spor salonuna varinca", "spora varinca", "gym e varinca", "when i get to the gym", "when i arrive at the gym"]) {
            return place(.geofenceEnter, alias: "gym", raw: text, confidence: 0.87)
        }
        if containsAny(lower, ["spor salonundan ayrilinca", "spor salonundan cikinca", "gymden ayrilinca", "gym den ayrilinca", "when i leave the gym"]) {
            return place(.geofenceExit, alias: "gym", raw: text, confidence: 0.89)
        }
        if containsAny(lower, ["markete varinca", "market gelince", "eczane gelince", "eczaneye varinca", "magazaya girince", "when i get to the store", "when i arrive at the pharmacy", "when i get to the market"]) {
            let alias = lower.contains("eczane") || lower.contains("pharmacy") ? "pharmacy" : lower.contains("market") ? "market" : "store"
            return place(.geofenceEnter, alias: alias, raw: text, confidence: 0.78)
        }
        if containsAny(lower, ["marketten cikinca", "eczaneden cikinca", "magazadan cikinca", "when i leave the store", "when i leave the pharmacy", "when i leave the market"]) {
            let alias = lower.contains("eczane") || lower.contains("pharmacy") ? "pharmacy" : lower.contains("market") ? "market" : "store"
            return place(.geofenceExit, alias: alias, raw: text, confidence: 0.76)
        }
        if containsAny(lower, ["sarja takinca", "telefonu sarja takinca", "when i plug in", "when charging starts"]) {
            return event(.chargingStarted, raw: text, confidence: 0.9, permissions: [.notifications])
        }
        if containsAny(lower, ["sabah telefonu acinca", "sabah ilk acinca", "unlock in the morning", "morning first unlock"]) {
            return event(.morningFirstUnlock, raw: text, confidence: 0.82, permissions: [.notifications])
        }
        if containsAny(lower, ["telefonu acinca", "unlock my phone", "device unlock"]) {
            return event(.deviceUnlock, raw: text, confidence: 0.58, permissions: [.notifications])
        }
        if containsAny(lower, ["arabaya binince", "arabama binince", "carplay baglaninca", "when carplay connects", "when i connect to car", "when i connect to my car", "when i get in my car"]) {
            return event(.carplayConnected, raw: text, confidence: 0.78, permissions: [.notifications, .bluetooth])
        }
        if containsAny(lower, ["arabadan inince", "arabadan cikinca", "carplay ayrilinca", "when carplay disconnects", "when i disconnect from car", "when i leave my car"]) {
            return event(.carplayDisconnected, raw: text, confidence: 0.78, permissions: [.notifications, .bluetooth])
        }
        if containsAny(lower, ["bluetooth baglaninca", "bluetooth connected"]) {
            return event(.bluetoothConnected, raw: text, confidence: 0.75, permissions: [.notifications, .bluetooth])
        }
        if containsAny(lower, ["bluetooth ayrilinca", "bluetooth disconnected"]) {
            return event(.bluetoothDisconnected, raw: text, confidence: 0.75, permissions: [.notifications, .bluetooth])
        }
        if containsAny(lower, ["toplantidan sonra", "toplanti bitince", "after my meeting", "after the meeting", "when my meeting ends"]) {
            return event(.calendarEventEnded, raw: text, confidence: 0.74, permissions: [.notifications, .calendar])
        }
        if containsAny(lower, ["antrenman bitince", "spor bitince", "workout ends", "after workout", "when my workout ends"]) {
            return event(.workoutEnded, raw: text, confidence: 0.76, permissions: [.notifications, .motionFitness])
        }
        if containsAny(lower, ["laptopu acinca", "laptopumu acinca", "bilgisayarimi acinca", "bilgisayarimin kapagini acinca", "open my laptop", "when i open my laptop"]) {
            let condition = TriggerCondition(
                type: .customContext,
                subject: "laptop_opened",
                metadata: ["fallback": "companion_app_bluetooth_wifi_manual", "actionable": "false"],
                requiresPermission: [.notifications, .bluetooth, .localNetwork],
                minimumConfidence: 0.75
            )
            return Result(
                condition: condition,
                reminderText: stripTriggerPhrase(from: text),
                confidence: 0.45,
                needsClarification: true,
                clarifyingQuestion: "I can save this, but I need a companion, Bluetooth, Wi-Fi, or manual signal to know when your laptop opens.",
                explanation: "Laptop open is not directly available on iOS, so this needs a companion or fallback signal."
            )
        }
        if containsAny(lower, ["benzin alinca", "yakit alinca", "gas alinca", "when i get gas", "when i buy fuel", "at the gas station"]) {
            let condition = TriggerCondition(
                type: .customContext,
                subject: "fuel_stop",
                metadata: ["fallback": "gas_station_location_car_bluetooth_confirmation", "actionable": "false"],
                requiresPermission: [.notifications, .location, .bluetooth],
                minimumConfidence: 0.8
            )
            return Result(
                condition: condition,
                reminderText: stripTriggerPhrase(from: text),
                confidence: 0.42,
                needsClarification: true,
                clarifyingQuestion: "I can watch for gas-station context, but I should confirm this setup first.",
                explanation: "Fuel stops need location category plus car/Bluetooth or confirmation fallback."
            )
        }

        return Result(
            condition: TriggerCondition(type: .unknownRequiresClarification, minimumConfidence: 1),
            reminderText: nil,
            confidence: 0,
            needsClarification: false,
            clarifyingQuestion: nil,
            explanation: "No event trigger detected."
        )
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .lowercased()
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }

    private static func place(_ type: TriggerType, alias: String, raw: String, confidence: Double) -> Result {
        let condition = TriggerCondition(
            type: type,
            subject: alias,
            locationAlias: alias,
            metadata: ["actionable": "true"],
            requiresPermission: [.notifications, .location],
            minimumConfidence: 0.7,
            cooldownSeconds: 3600
        )
        return Result(
            condition: condition,
            reminderText: stripTriggerPhrase(from: raw),
            confidence: confidence,
            needsClarification: true,
            clarifyingQuestion: "Where should I remember as \(alias)?",
            explanation: "This waits for \(alias) \(type == .geofenceEnter ? "arrival" : "exit")."
        )
    }

    private static func event(_ type: TriggerType, raw: String, confidence: Double, permissions: [PermissionKind]) -> Result {
        Result(
            condition: TriggerCondition(
                type: type,
                subject: type.rawValue,
                metadata: ["actionable": "true"],
                requiresPermission: permissions,
                minimumConfidence: 0.65,
                cooldownSeconds: type == .morningFirstUnlock ? 22 * 3600 : 3600
            ),
            reminderText: stripTriggerPhrase(from: raw),
            confidence: confidence,
            needsClarification: false,
            clarifyingQuestion: nil,
            explanation: "This waits for \(type.rawValue)."
        )
    }

    private static func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    private static func stripTriggerPhrase(from text: String) -> String {
        let normalized = normalize(text)
        let triggerPhrases = [
            "eve varinca", "eve gelince", "ise varinca", "ofise varinca",
            "evden cikinca", "evden ayrilinca", "spor salonuna varinca", "spora varinca",
            "isten cikinca", "ofisten ayrilinca", "spor salonundan ayrilinca",
            "spor salonundan cikinca", "gymden ayrilinca", "gym den ayrilinca",
            "markete varinca", "market gelince", "eczane gelince", "eczaneye varinca",
            "magazaya girince", "marketten cikinca", "eczaneden cikinca", "magazadan cikinca",
            "sarja takinca", "telefonu sarja takinca", "sabah telefonu acinca",
            "sabah ilk acinca", "telefonu acinca", "arabaya binince", "arabadan inince",
            "carplay baglaninca", "carplay ayrilinca", "bluetooth baglaninca",
            "bluetooth ayrilinca", "laptopu acinca", "laptopumu acinca", "bilgisayarimi acinca", "bilgisayarimin kapagini acinca",
            "toplantidan sonra", "toplanti bitince", "antrenman bitince", "spor bitince",
            "benzin alinca", "yakit alinca", "gas alinca",
            "when i get home", "when i arrive home", "when i arrive at work",
            "when i get to work", "when i leave work", "when i leave the office",
            "when i leave home", "when i get to the gym", "when i arrive at the gym",
            "when i leave the gym", "when i get to the store", "when i arrive at the pharmacy",
            "when i get to the market", "when i leave the store", "when i leave the pharmacy",
            "when i leave the market", "when i plug in", "when charging starts",
            "unlock in the morning", "morning first unlock", "unlock my phone",
            "when carplay connects", "when carplay disconnects", "when i connect to car",
            "when i connect to my car", "when i get in my car", "when i disconnect from car",
            "when i leave my car", "bluetooth connected", "bluetooth disconnected",
            "after my meeting", "after the meeting", "when my meeting ends",
            "workout ends", "after workout", "when my workout ends",
            "open my laptop", "when i open my laptop", "when i get gas", "when i buy fuel",
            "at the gas station"
        ]
        for phrase in triggerPhrases {
            if let range = normalized.range(of: phrase) {
                let offset = normalized.distance(from: normalized.startIndex, to: range.upperBound)
                let originalIndex = text.index(text.startIndex, offsetBy: min(offset, text.count))
                let after = text[originalIndex...]
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                if !after.isEmpty { return after }
            }
        }
        return text
    }
}

enum TriggerResolver {
    static func resolve(_ condition: TriggerCondition, aliases: [LocationAlias], permissions: [PermissionState]) -> TriggerResolution {
        if condition.type == .customContext || condition.type == .unknownRequiresClarification {
            return TriggerResolution(isReady: false, condition: condition, missingPermissions: [], fallback: FallbackStrategy.strategy(for: condition))
        }
        let missing = condition.requiresPermission.filter { needed in
            !permissions.contains { $0.permission == needed && $0.status == .granted }
        }
        if !missing.isEmpty {
            return TriggerResolution(isReady: false, condition: condition, missingPermissions: missing, fallback: FallbackStrategy.strategy(for: condition))
        }
        if let alias = condition.locationAlias, !aliases.contains(where: { $0.name == alias }) {
            return TriggerResolution(isReady: false, condition: condition, missingPermissions: [], fallback: .askToDefineLocation(alias))
        }
        return TriggerResolution(isReady: true, condition: condition, missingPermissions: [], fallback: nil)
    }
}

enum TriggerConfidenceScorer {
    static func score(event: TriggerEvent, condition: TriggerCondition) -> Double {
        var score = event.confidence
        if event.type == condition.type { score += 0.18 }
        if condition.subject == nil || condition.subject == event.subject || condition.subject == event.type.rawValue {
            score += 0.08
        }
        if event.createdAt.timeIntervalSinceNow > -300 { score += 0.04 }
        return min(1.0, score)
    }
}

enum TriggerExecutionPolicy {
    static let defaultCooldown: TimeInterval = 60 * 60

    static func matches(_ event: TriggerEvent, condition: TriggerCondition) -> Bool {
        guard event.type == condition.type else { return false }
        if let subject = condition.subject, subject != event.subject, subject != event.type.rawValue {
            return false
        }
        return TriggerConfidenceScorer.score(event: event, condition: condition) >= condition.minimumConfidence
    }

    static func shouldFire(condition: TriggerCondition, event: TriggerEvent, eventLog: [TriggerEventLog], now: Date = .now) -> Bool {
        guard matches(event, condition: condition) else { return false }
        let recent = eventLog.filter {
            $0.triggerType == condition.type &&
            $0.createdAt > now.addingTimeInterval(-(condition.cooldownSeconds ?? defaultCooldown))
        }
        return recent.isEmpty
    }
}

enum TriggerEventSimulator {
    static func morningFirstUnlock(now: Date = .now) -> TriggerEvent {
        TriggerEvent(type: .morningFirstUnlock, subject: TriggerType.morningFirstUnlock.rawValue, confidence: 0.95, createdAt: now)
    }

    static func chargingStarted(now: Date = .now) -> TriggerEvent {
        TriggerEvent(type: .chargingStarted, subject: TriggerType.chargingStarted.rawValue, confidence: 0.95, createdAt: now)
    }

    static func carPlayConnected(now: Date = .now) -> TriggerEvent {
        TriggerEvent(type: .carplayConnected, subject: TriggerType.carplayConnected.rawValue, confidence: 0.9, createdAt: now)
    }

    static func carPlayDisconnected(now: Date = .now) -> TriggerEvent {
        TriggerEvent(type: .carplayDisconnected, subject: TriggerType.carplayDisconnected.rawValue, confidence: 0.9, createdAt: now)
    }
}

enum PermissionManager {
    static func missingPermissions(for condition: TriggerCondition, states: [PermissionState]) -> [PermissionKind] {
        condition.requiresPermission.filter { permission in
            !states.contains { $0.permission == permission && $0.status == .granted }
        }
    }
}

enum FallbackStrategy: Codable, Hashable {
    case askToDefineLocation(String)
    case oneTapConfirmation
    case shortcutsAutomation
    case companionOrSignal
    case manualReminder

    static func strategy(for condition: TriggerCondition) -> FallbackStrategy {
        switch condition.type {
        case .geofenceEnter, .geofenceExit:
            return condition.locationAlias.map { .askToDefineLocation($0) } ?? .manualReminder
        case .customContext:
            if condition.subject == "laptop_opened" { return .companionOrSignal }
            if condition.subject == "fuel_stop" { return .oneTapConfirmation }
            return .manualReminder
        case .calendarEventEnded:
            return .manualReminder
        default:
            return .manualReminder
        }
    }

    var explanation: String {
        switch self {
        case .askToDefineLocation(let alias): return "Needs saved \(alias) location."
        case .oneTapConfirmation: return "Needs a confirmation or fallback setup before firing."
        case .shortcutsAutomation: return "Needs an automation signal."
        case .companionOrSignal: return "Needs companion app, Bluetooth, Wi-Fi, or manual fallback."
        case .manualReminder: return "Can fall back to a manual or time-based reminder."
        }
    }
}

struct TriggerResolution: Equatable {
    let isReady: Bool
    let condition: TriggerCondition
    let missingPermissions: [PermissionKind]
    let fallback: FallbackStrategy?
}

import Foundation
import NaturalLanguage

// MARK: - TextAnalyzer
// Understands what the user writes to infer category, frequency, and time preference.
// Supports both English and Turkish input.

enum TextAnalyzer {

    // MARK: - Public API

    static func analyze(_ text: String) -> TextAnalysis {
        let tokens   = lemmatize(text)
        let language = detectLanguage(text)

        let catScores  = scoreCategories(tokens: tokens, language: language)
        let category   = bestCategory(from: catScores)
        let confidence = catScores[category] ?? 0

        let freq  = suggestFrequency(text: text, tokens: tokens, category: category, language: language)
        let time  = suggestTime(tokens: tokens, language: language)
        let habit = isHabit(tokens: tokens, category: category, language: language)

        return TextAnalysis(
            category: category,
            suggestedFrequency: freq,
            suggestedTimePreference: time,
            isHabit: habit,
            confidence: min(confidence, 1.0)
        )
    }

    // MARK: - Language Detection

    private static func detectLanguage(_ text: String) -> NLLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage ?? .english
    }

    // MARK: - Lemmatization
    // Extracts word stems so "drinking" → "drink", "yürüyor" → "yürü".

    private static func lemmatize(_ text: String) -> [String] {
        var tokens: [String] = []
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word,
                             scheme: .lemma,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            let lemma = (tag?.rawValue ?? String(text[range])).lowercased()
            if lemma.count > 1 { tokens.append(lemma) }
            return true
        }
        // Also include original lowercased words in case lemmatizer misses something
        let originals = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .flatMap { $0.components(separatedBy: .punctuationCharacters) }
            .filter { $0.count > 1 }
        tokens.append(contentsOf: originals)
        return Array(Set(tokens))
    }

    // MARK: - Category Scoring

    // Each keyword maps to a confidence weight (0–1).
    // The more domain-specific the word, the higher the weight.

    private static let keywords: [ReminderCategory: [String: Double]] = [
        .body: [
            // English
            "water": 1.0, "drink": 0.9, "sip": 0.8, "hydrat": 0.9,
            "eat": 0.8, "meal": 0.8, "food": 0.7, "breakfast": 0.8, "lunch": 0.7, "dinner": 0.7,
            "sleep": 1.0, "nap": 0.9, "rest": 0.8, "relax": 0.6,
            "medicine": 1.0, "vitamin": 1.0, "pill": 1.0, "supplement": 0.9, "medication": 1.0,
            "stretch": 0.8, "break": 0.7, "snack": 0.7,
            // Turkish
            "su": 1.0, "iç": 0.8, "içmek": 0.9, "ye": 0.8, "yemek": 0.8, "kahvaltı": 0.9,
            "uyku": 1.0, "uyu": 0.9, "dinlen": 0.9, "mola": 0.8,
            "ilaç": 1.0, "hap": 1.0,
        ],
        .move: [
            // English
            "walk": 1.0, "run": 1.0, "jog": 1.0, "sprint": 0.9,
            "exercise": 1.0, "workout": 1.0, "gym": 1.0, "train": 0.8,
            "outside": 0.8, "outdoor": 0.8, "step": 0.7, "stand": 0.6,
            "yoga": 1.0, "swim": 1.0, "bike": 0.9, "cycle": 0.9, "hike": 0.9,
            "sport": 0.9, "move": 0.8, "active": 0.7,
            // Turkish
            "yürü": 1.0, "yürümek": 1.0, "koş": 1.0, "koşmak": 1.0,
            "egzersiz": 1.0, "spor": 1.0, "dışarı": 0.9, "adım": 0.7,
            "bisiklet": 0.9, "yüz": 0.9, "yüzmek": 0.9,
        ],
        .mind: [
            // English
            "read": 1.0, "book": 0.8, "article": 0.7,
            "meditat": 1.0, "mindful": 1.0, "breath": 1.0, "breathe": 1.0,
            "journal": 1.0, "write": 0.7, "reflect": 0.9, "gratitude": 1.0,
            "think": 0.6, "pause": 0.7, "still": 0.6, "calm": 0.7, "quiet": 0.7,
            "podcast": 0.6, "music": 0.5,
            // Turkish
            "oku": 1.0, "okumak": 1.0, "kitap": 1.0,
            "meditasyon": 1.0, "nefes": 1.0, "nefes al": 1.0,
            "günlük": 1.0, "yaz": 0.7, "düşün": 0.8,
            "sessiz": 0.7, "sakin": 0.7,
        ],
        .grow: [
            // English
            "learn": 1.0, "study": 1.0, "practice": 0.9, "skill": 0.9,
            "call": 0.8, "phone": 0.7, "email": 0.7, "message": 0.6, "text": 0.6,
            "connect": 0.8, "friend": 0.6, "family": 0.7,
            "plan": 0.8, "review": 0.7, "prepare": 0.7,
            "course": 0.9, "lesson": 0.9, "language": 0.9,
            "work": 0.6, "project": 0.7, "goal": 0.8,
            // Turkish
            "öğren": 1.0, "öğrenmek": 1.0, "çalış": 0.9, "pratik": 0.9,
            "ara": 0.8, "aramak": 0.8, "mesaj": 0.7,
            "hazırlan": 0.8,
            "ders": 0.9, "dil": 0.9,
        ],
    ]

    private static func scoreCategories(tokens: [String], language: NLLanguage) -> [ReminderCategory: Double] {
        var scores: [ReminderCategory: Double] = [.body: 0, .move: 0, .mind: 0, .grow: 0]

        for token in tokens {
            for (cat, kwMap) in keywords {
                // Exact match
                if let w = kwMap[token] {
                    scores[cat, default: 0] += w
                    continue
                }
                // Prefix match (handles Turkish verb stems)
                for (kw, w) in kwMap {
                    if token.hasPrefix(kw) || kw.hasPrefix(token) {
                        scores[cat, default: 0] += w * 0.7
                    }
                }
            }
        }

        // Normalize so max = 1.0 (roughly)
        let total = scores.values.reduce(0, +)
        if total > 0 {
            scores = scores.mapValues { $0 / total }
        }
        return scores
    }

    private static func bestCategory(from scores: [ReminderCategory: Double]) -> ReminderCategory {
        let best = scores.max { $0.value < $1.value }
        guard let best, best.value > 0.25 else { return .none }
        return best.key
    }

    // MARK: - Frequency Suggestion

    private static let dailySignals: [String] = [
        "every day", "daily", "each day", "every morning", "every evening",
        "her gün", "günlük", "her sabah", "her akşam",
    ]
    private static let weeklySignals: [String] = [
        "every week", "weekly", "once a week", "few times",
        "haftada", "her hafta",
    ]
    private static let occasionalSignals: [String] = [
        "sometimes", "occasionally", "now and then",
        "bazen", "ara sıra", "zaman zaman",
    ]

    private static func suggestFrequency(
        text: String, tokens: [String],
        category: ReminderCategory, language: NLLanguage
    ) -> FrequencyPreference {
        let lower = text.lowercased()

        for sig in dailySignals   { if lower.contains(sig) { return .daily      } }
        for sig in weeklySignals  { if lower.contains(sig) { return .weekly     } }
        for sig in occasionalSignals { if lower.contains(sig) { return .occasional } }

        return category.defaultFrequency
    }

    // MARK: - Time Preference

    private static let morningSignals: [String] = [
        "morning", "breakfast", "wake up", "wake", "early", "coffee", "start of day",
        "sabah", "kahvaltı", "uyandıktan", "güne başla",
    ]
    private static let eveningSignals: [String] = [
        "evening", "night", "before bed", "sleep", "dinner", "after work", "end of day",
        "akşam", "gece", "uyumadan", "yatmadan", "iş sonrası",
    ]

    private static func suggestTime(tokens: [String], language: NLLanguage) -> TimePreference {
        let joined = tokens.joined(separator: " ")
        for sig in morningSignals { if joined.contains(sig) { return .morning } }
        for sig in eveningSignals { if joined.contains(sig) { return .evening } }
        return .flexible
    }

    // MARK: - Habit Detection
    // A "habit" resets daily; a "task" is one-off.

    private static let habitVerbs: Set<String> = [
        "drink", "eat", "walk", "run", "read", "meditate", "breathe", "exercise", "stretch",
        "içmek", "yemek", "yürümek", "koşmak", "okumak",
    ]

    private static func isHabit(tokens: [String], category: ReminderCategory, language: NLLanguage) -> Bool {
        for token in tokens {
            if habitVerbs.contains(token) || habitVerbs.contains(where: { token.hasPrefix($0) }) {
                return true
            }
        }
        // Body and mind categories are almost always habits
        return category == .body || category == .mind
    }
}

import Foundation

// MARK: - BehaviorAnalytics
// All on-device. Reads the quiet record (interactions + reminder state) and
// derives observations the UI uses for the Behavior layer.
//
// Nothing here mutates state — these are pure functions consumed by AppState.

enum BehaviorAnalytics {

    // MARK: - Pattern observation
    //
    // Picks the most-completed reminder and, if its completions cluster on a
    // weekday + slot (morning / before noon / afternoon / evening), returns a
    // single observation line. Returns nil when there isn't enough signal.

    static func patternObservation(from reminders: [Reminder]) -> String? {
        // Need ≥3 completions on the same weekday across reminders for any signal.
        let cal = Calendar.current
        let candidates = reminders
            .filter { !$0.text.isEmpty }
            .map { r -> (Reminder, [Date]) in
                let comps = r.interactions
                    .filter { $0.type == .completed }
                    .map(\.timestamp)
                return (r, comps)
            }
            .filter { $0.1.count >= 3 }
            .sorted { $0.1.count > $1.1.count }

        guard let (top, dates) = candidates.first else { return nil }

        // Most frequent weekday
        var byWeekday: [Int: [Date]] = [:]
        for d in dates {
            byWeekday[cal.component(.weekday, from: d), default: []].append(d)
        }
        guard let (weekday, sameDay) = byWeekday.max(by: { $0.value.count < $1.value.count }),
              sameDay.count >= 2
        else { return nil }

        let avgHour = sameDay
            .map { cal.component(.hour, from: $0) }
            .reduce(0, +) / sameDay.count

        let dayName = cal.weekdaySymbols[weekday - 1]   // "Tuesday"
        let slot: String = {
            switch avgHour {
            case ..<11:  return "before noon"
            case ..<14:  return "around lunch"
            case ..<18:  return "in the afternoon"
            default:     return "in the evening"
            }
        }()

        let phrase = top.text.lowercased()
        return "\(dayName)s you usually \(phrase) \(slot) — we'll nudge then."
    }

    // MARK: - Receptivity dots
    //
    // For the last 7 calendar days (oldest..today), returns one dot per day.
    // Each dot has:
    //   - day:  one-letter weekday label (M, T, W, T, F, S, S — locale-independent)
    //   - size: 3..8 pt encoding engagement (completions vs ignores).

    struct Dot { let day: String; let size: CGFloat }

    static func receptivityDots(from reminders: [Reminder]) -> [Dot] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        // letters in Mon..Sun order; we'll align by weekday number
        let letters = ["M", "T", "W", "T", "F", "S", "S"]

        // Walk last 7 days oldest → today.
        return (0..<7).reversed().map { offset -> Dot in
            let day  = cal.date(byAdding: .day, value: -offset, to: today)!
            let next = cal.date(byAdding: .day, value: 1, to: day)!

            var completions = 0
            var ignores     = 0
            for r in reminders {
                for i in r.interactions where i.timestamp >= day && i.timestamp < next {
                    switch i.type {
                    case .completed: completions += 1
                    case .ignored:   ignores     += 1
                    case .skipped:   ignores     += 1   // soft penalty
                    }
                }
            }

            let total = max(completions + ignores, 1)
            let ratio = Double(completions) / Double(total)
            let size: CGFloat
            switch (completions + ignores, ratio) {
            case (0, _):           size = 3              // no signal
            case (_, ..<0.34):     size = 4              // mostly missed
            case (_, ..<0.67):     size = 6              // mixed
            default:               size = 8              // engaged
            }

            // Index into letters using ISO weekday (Mon=0)
            let wd = (cal.component(.weekday, from: day) + 5) % 7
            return Dot(day: letters[wd], size: size)
        }
    }

    // MARK: - Weekly category stack
    //
    // Returns 7 daily fractions (Mon..Sun this week so far), each a dictionary
    // body/move/mind/grow → 0..1 fraction of that day's load. The fractions
    // sum to ≤ 0.95 so the chart never quite touches the top — a quiet ceiling.

    static func weeklyCategoryStack(from reminders: [Reminder]) -> [[ReminderCategory: Double]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        // Find Monday of this week
        let weekday = (cal.component(.weekday, from: today) + 5) % 7   // Mon=0
        let monday  = cal.date(byAdding: .day, value: -weekday, to: today)!

        return (0..<7).map { off -> [ReminderCategory: Double] in
            let day  = cal.date(byAdding: .day, value: off, to: monday)!
            let next = cal.date(byAdding: .day, value: 1, to: day)!

            var counts: [ReminderCategory: Double] = [.body: 0, .move: 0, .mind: 0, .grow: 0]
            for r in reminders {
                for i in r.interactions where i.timestamp >= day && i.timestamp < next {
                    if i.type == .completed { counts[r.category, default: 0] += 1 }
                }
            }
            // Normalize to a quiet 0..0.95 envelope.
            let sum = counts.values.reduce(0, +)
            guard sum > 0 else { return counts }
            let scale = min(0.95, sum / 4.0)   // 4 completions ≈ full day
            return counts.mapValues { ($0 / sum) * scale }
        }
    }

    // MARK: - Quiet held-back
    //
    // True when yesterday had at least one open reminder but no interaction
    // landed (the day passed without nudges firing — phone was likely DND/silent).

    static func wasYesterdayHeldBack(reminders: [Reminder]) -> Bool {
        let cal = Calendar.current
        let yStart = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: .now))!
        let yEnd   = cal.startOfDay(for: .now)
        let hadOpenReminders = reminders.contains { !$0.isDone }
        guard hadOpenReminders else { return false }

        let anyInteraction = reminders.contains { r in
            r.interactions.contains { $0.timestamp >= yStart && $0.timestamp < yEnd }
        }
        return !anyInteraction
    }

    // MARK: - Eased-back trigger
    //
    // True when 3 or more reminders are currently in their pause window — that
    // is, the engine has flagged repeated ignores and backed off. We surface
    // the banner once; the user's "Okay" acknowledgement clears it.

    static func shouldShowEasedBack(reminders: [Reminder]) -> Bool {
        let now = Date.now
        let paused = reminders.filter { ($0.pausedUntil ?? .distantPast) > now }
        return paused.count >= 3
    }
}

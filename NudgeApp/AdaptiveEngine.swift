import Foundation

// MARK: - AdaptiveEngine
// The brain of the app.  Everything that decides *when* and *how often* to nudge
// lives here.  No UI code.  No notification code.  Pure logic.

enum AdaptiveEngine {

    // ── Constants ─────────────────────────────────────────────────────────────

    /// Interactions older than 7 days count half as much as fresh ones.
    static let halfLife: TimeInterval = 7 * 24 * 3600

    /// Never send more than this many notifications within 30 minutes across all reminders.
    static let clusterGapSeconds: TimeInterval = 30 * 60

    // ── MARK: Effectiveness Score ─────────────────────────────────────────────
    //
    // score = Σ weight_i × value_i
    //   weight_i = 2^(–age_i / halfLife)   [exponential decay]
    //   value_i  = +2 completed | –1 skipped | –2 ignored

    static func score(for interactions: [Interaction]) -> Double {
        let now = Date.now.timeIntervalSince1970
        return interactions.reduce(0.0) { sum, i in
            let age    = now - i.timestamp.timeIntervalSince1970
            let weight = pow(0.5, age / halfLife)
            let value: Double = switch i.type {
                case .completed: 2
                case .skipped:  -1
                case .ignored:  -2
            }
            return sum + weight * value
        }
    }

    // ── MARK: Learned Hour Weights ────────────────────────────────────────────
    //
    // Builds a [hour → weight] map from completed interactions.
    // Returns nil if fewer than 3 completions (not enough data yet).

    static func learnedHourWeights(from interactions: [Interaction]) -> [Int: Double]? {
        let completions = interactions.filter { $0.type == .completed }
        guard completions.count >= 3 else { return nil }

        let now = Date.now.timeIntervalSince1970
        var hourW = [Int: Double]()
        for i in completions {
            let h = Calendar.current.component(.hour, from: i.timestamp)
            let age = now - i.timestamp.timeIntervalSince1970
            hourW[h, default: 0] += pow(0.5, age / halfLife)
        }
        return hourW
    }

    // Learned best hours sorted descending by weight.
    static func rankedHours(from interactions: [Interaction]) -> [Int] {
        guard let w = learnedHourWeights(from: interactions) else { return [] }
        return w.sorted { $0.value > $1.value }.map(\.key)
    }

    // ── MARK: Day-of-Week Completion Rates ───────────────────────────────────
    //
    // Returns a map [weekday (1=Sun…7=Sat) → completion rate].
    // Used to decide which days to nudge for weekly-frequency reminders.

    static func weekdayCompletionRates(from interactions: [Interaction]) -> [Int: Double] {
        let completions = Set(interactions.filter { $0.type == .completed }
            .map { Calendar.current.component(.weekday, from: $0.timestamp) })
        let totals = Dictionary(grouping: interactions) {
            Calendar.current.component(.weekday, from: $0.timestamp)
        }.mapValues { Double($0.count) }

        var rates = [Int: Double]()
        for (day, total) in totals {
            rates[day] = completions.contains(day) ? (Double(completions.filter { $0 == day }.count)) / total : 0
        }
        return rates
    }

    // ── MARK: Anti-Annoyance State ────────────────────────────────────────────

    struct AnnoyanceState {
        let recentIgnores: Int    // in last 24 hours
        let recentSkips: Int      // in last 6 hours
        let shouldPause: Bool
        let pauseDuration: TimeInterval  // seconds
    }

    static func annoyanceState(for reminder: Reminder) -> AnnoyanceState {
        let now = Date.now
        let last24h = now.addingTimeInterval(-86400)
        let last6h  = now.addingTimeInterval(-21600)

        let recentIgnores = reminder.interactions.filter {
            $0.type == .ignored && $0.timestamp > last24h
        }.count

        let recentSkips = reminder.interactions.filter {
            $0.type == .skipped && $0.timestamp > last6h
        }.count

        // 3+ ignores in 24h → pause with exponential backoff (2h, 4h, 8h, …)
        let shouldPause = recentIgnores >= 3
        let pauseHours  = shouldPause ? min(pow(2.0, Double(recentIgnores - 2)), 24) : 0
        let pauseTime   = pauseHours * 3600

        return AnnoyanceState(
            recentIgnores: recentIgnores,
            recentSkips:   recentSkips,
            shouldPause:   shouldPause,
            pauseDuration: pauseTime
        )
    }

    // ── MARK: Should Nudge Now? ───────────────────────────────────────────────

    static func shouldNudge(
        _ reminder: Reminder,
        settings: AppSettings,
        dailyTotalSent: Int
    ) -> Bool {
        guard !reminder.isDone else { return false }

        // Global daily cap
        let cap = settings.notificationLevel.maxDailyNudgesGlobal
        guard dailyTotalSent < cap else { return false }

        // Per-reminder daily cap
        guard reminder.todayNudgeCount < reminder.frequency.maxDailyNudges else { return false }

        // Pause check
        if let pausedUntil = reminder.pausedUntil, pausedUntil > .now { return false }

        // Quiet hours
        let hour = Calendar.current.component(.hour, from: .now)
        if isQuiet(hour: hour, settings: settings) { return false }

        // Scheduled time check
        if let next = reminder.nextNudgeAt { return next <= .now }
        return true  // no schedule yet → eligible immediately
    }

    // ── MARK: Compute Next Nudge Date ────────────────────────────────────────

    static func nextNudgeDate(
        for reminder: Reminder,
        settings: AppSettings,
        dailyTotalSent: Int
    ) -> Date {
        let now  = Date.now
        let cap  = settings.notificationLevel.maxDailyNudgesGlobal
        let cal  = Calendar.current

        // If daily cap reached → tomorrow at a good time
        if dailyTotalSent >= cap {
            return tomorrow(hour: bestHour(for: reminder, settings: settings), calendar: cal)
        }

        // Pinned due date → morning of that day
        if let due = reminder.dueDate {
            let dueMorning = cal.date(bySettingHour: 9, minute: 0, second: 0, of: due) ?? due
            return dueMorning > now ? dueMorning : now.addingTimeInterval(300)
        }

        // Anti-annoyance pause
        let annoy = annoyanceState(for: reminder)
        if annoy.shouldPause {
            return now.addingTimeInterval(annoy.pauseDuration)
        }

        // Recent skip → delay 2–4 hours
        if annoy.recentSkips > 0 {
            let delay = TimeInterval(annoy.recentSkips * 2 * 3600)
            let candidate = now.addingTimeInterval(delay)
            if !isQuiet(hour: cal.component(.hour, from: candidate), settings: settings) {
                return candidate
            }
        }

        // Weekly reminder → schedule only on good weekdays
        if reminder.frequency == .weekly {
            return nextWeeklyDate(for: reminder, settings: settings, calendar: cal)
        }

        // Use learned schedule or category defaults
        return nextScheduledTime(for: reminder, settings: settings, calendar: cal)
    }

    // ── MARK: Today's Global Nudge Count ─────────────────────────────────────

    static func dailyNudgeCount(across reminders: [Reminder]) -> Int {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return reminders.reduce(0) { $0 + $1.interactions.filter { $0.timestamp >= startOfDay }.count }
    }

    // ── MARK: Next-nudge preview text for home screen ─────────────────────────

    static func nextNudgePreview(for reminders: [Reminder]) -> String? {
        let open = reminders.filter { !$0.isDone }
        guard !open.isEmpty else { return nil }

        let hour = Calendar.current.component(.hour, from: .now)
        if let earliest = open.compactMap(\.nextNudgeAt).min() {
            let mins = Int(earliest.timeIntervalSinceNow / 60)
            if mins < 5        { return "very soon" }
            if mins < 60       { return "in about \(mins) minutes" }
            if mins < 90       { return "in about an hour" }
        }
        // Slot description
        if      hour < 10 { return "late morning" }
        else if hour < 13 { return "after lunch"  }
        else if hour < 17 { return "this afternoon" }
        else if hour < 20 { return "this evening" }
        else              { return "tomorrow morning" }
    }

    // ── MARK: Gentle notification body text ───────────────────────────────────

    static func nudgeBody(for reminder: Reminder) -> String {
        let pool: [String]
        switch reminder.category {
        case .body:
            pool = [
                "A sip of water might feel good.",
                "A short break could help right now.",
                "If it feels right, step away for a moment.",
                "Maybe pause and rest a little?",
                "Your body might appreciate this.",
            ]
        case .move:
            pool = [
                "Perhaps step outside for a moment?",
                "A little movement might lift your mood.",
                "Your body might appreciate a gentle stretch.",
                "A short walk could feel nice.",
                "Maybe time to move a little?",
            ]
        case .mind:
            pool = [
                "A few slow breaths might help.",
                "A quiet moment could be nice.",
                "Perhaps a page or two?",
                "A little stillness might feel good.",
                "When the moment is right.",
            ]
        case .grow:
            pool = [
                "A small step today could feel good.",
                "Perhaps a moment for this?",
                "When you're ready — no rush.",
                "This might be a good time.",
                "No pressure, just a gentle nudge.",
            ]
        case .none:
            pool = [
                "A gentle reminder, just for you.",
                "When it feels right.",
                "No pressure — just a small reminder.",
                "A little reminder, softly.",
            ]
        }
        return pool[Int.random(in: 0..<pool.count)]
    }

    // ── MARK: Record interaction + update reminder ────────────────────────────

    static func recordInteraction(
        _ type: InteractionType,
        on reminder: inout Reminder,
        settings: AppSettings,
        dailyTotalSent: Int
    ) {
        reminder.interactions.append(Interaction(type: type))

        // Trim to last 90 days to keep storage bounded
        let cutoff = Date.now.addingTimeInterval(-90 * 86400)
        reminder.interactions.removeAll { $0.timestamp < cutoff }

        // Recompute next nudge
        reminder.nextNudgeAt = nextNudgeDate(
            for: reminder, settings: settings, dailyTotalSent: dailyTotalSent
        )

        // Apply pause if needed
        let annoy = annoyanceState(for: reminder)
        if annoy.shouldPause {
            reminder.pausedUntil = Date.now.addingTimeInterval(annoy.pauseDuration)
        }
    }

    // ── MARK: Private Helpers ─────────────────────────────────────────────────

    static func isQuiet(hour: Int, settings: AppSettings) -> Bool {
        let start = settings.quietHoursStart
        let end   = settings.quietHoursEnd
        if start > end {
            return hour >= start || hour < end  // e.g. 23–08 wraps midnight
        }
        return hour >= start && hour < end
    }

    private static func bestHour(for reminder: Reminder, settings: AppSettings) -> Int {
        // Use learned hours if available
        let learned = rankedHours(from: reminder.interactions).filter {
            !isQuiet(hour: $0, settings: settings)
        }
        if let h = learned.first { return h }

        // Fall back to time preference
        let preferred = reminder.timePreference.preferredHours.filter {
            !isQuiet(hour: $0, settings: settings)
        }
        if let h = preferred.first { return h }

        // Category defaults
        let catHours = reminder.category.defaultHours.filter {
            !isQuiet(hour: $0, settings: settings)
        }
        return catHours.first ?? 10
    }

    private static func nextScheduledTime(
        for reminder: Reminder,
        settings: AppSettings,
        calendar: Calendar
    ) -> Date {
        let now     = Date.now
        let curHour = calendar.component(.hour, from: now)
        let target  = bestHour(for: reminder, settings: settings)
        let minute  = Int.random(in: 5..<35)   // gentle randomness, not on the dot

        if target > curHour {
            return calendar.date(bySettingHour: target, minute: minute, second: 0, of: now) ?? now
        } else {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: target, minute: minute, second: 0, of: tomorrow) ?? tomorrow
        }
    }

    private static func tomorrow(hour: Int, calendar: Calendar) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        return calendar.date(bySettingHour: hour, minute: 10, second: 0, of: tomorrow) ?? tomorrow
    }

    private static func nextWeeklyDate(
        for reminder: Reminder,
        settings: AppSettings,
        calendar: Calendar
    ) -> Date {
        let rates = weekdayCompletionRates(from: reminder.interactions)
        let now   = Date.now

        // Find the best day in the next 7 days
        let today = calendar.component(.weekday, from: now)
        let sortedDays = (1...7).sorted { a, b in
            (rates[a] ?? 0.5) > (rates[b] ?? 0.5)
        }

        for offset in 1...7 {
            let candidate = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            let wd = calendar.component(.weekday, from: candidate)
            if sortedDays.prefix(3).contains(wd) {
                let h = bestHour(for: reminder, settings: settings)
                return calendar.date(bySettingHour: h, minute: 15, second: 0, of: candidate) ?? candidate
            }
        }

        // Fallback: 3 days from now
        return calendar.date(byAdding: .day, value: 3, to: now) ?? now
    }
}

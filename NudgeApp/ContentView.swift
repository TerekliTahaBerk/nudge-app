import SwiftUI
import Combine
import UIKit

// MARK: - Screen enum

enum Screen: Hashable {
    case splash, onboarding, home, settings
}

// MARK: - AppState
// Central store.  All mutation goes through here — views only read.

@MainActor
final class AppState: ObservableObject {

    // ── Published ──────────────────────────────────────────────────
    @Published var screen: Screen       = .splash
    @Published var reminders: [Reminder]
    @Published var settings: AppSettings
    @Published var activeNudge: ActiveNudge?
    @Published var showAddSheet: Bool   = false

    // ── Internal ───────────────────────────────────────────────────
    private var nudgeTimer: AnyCancellable?
    private var midnightTimer: AnyCancellable?
    private let scheduler = NotificationScheduler.shared

    // ── Init ───────────────────────────────────────────────────────

    init() {
        let savedSettings  = Store.loadSettings()
        let savedReminders = Store.loadReminders()

        self.settings  = savedSettings
        self.reminders = savedReminders.isEmpty ? Reminder.seedReminders() : savedReminders

        // Wire notification callbacks
        scheduler.onNudgeDone  = { [weak self] id in self?.markDone(id) }
        scheduler.onNudgeLater = { [weak self] id in
            self?.recordInteraction(.skipped, for: id)
        }

        // Start background services after init
        Task { await postInitSetup() }
    }

    private func postInitSetup() async {
        // Request notification permission if not yet decided
        if await !scheduler.isAuthorized {
            await scheduler.requestPermission()
        }
        startNudgeTimer()
        scheduleMidnightReset()
        // Schedule all pending notifications
        await scheduler.scheduleAll(reminders, settings: settings)
    }

    // ── MARK: Nudge Check Timer ────────────────────────────────────
    // Polls every 60 s to fire in-app banners when the app is foregrounded.

    private func startNudgeTimer() {
        nudgeTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.checkForDueNudges() }

        // Also check on app foreground
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.checkForDueNudges() }
    }

    func checkForDueNudges() {
        guard activeNudge == nil else { return }   // already showing one
        let total = AdaptiveEngine.dailyNudgeCount(across: reminders)

        for reminder in reminders {
            guard AdaptiveEngine.shouldNudge(reminder, settings: settings, dailyTotalSent: total) else { continue }
            let body = AdaptiveEngine.nudgeBody(for: reminder)
            activeNudge = ActiveNudge(reminderId: reminder.id, body: body, category: reminder.category)
            // Push next nudge time forward so this doesn't re-fire immediately
            updateReminder(reminder.id) { r in
                r.nextNudgeAt = AdaptiveEngine.nextNudgeDate(for: r, settings: self.settings, dailyTotalSent: total + 1)
            }
            break
        }
    }

    // ── MARK: Midnight Reset ───────────────────────────────────────

    private func scheduleMidnightReset() {
        let cal = Calendar.current
        guard let midnight = cal.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 0, second: 5), matchingPolicy: .nextTime) else { return }
        let delay = midnight.timeIntervalSince(.now)

        midnightTimer = Just(())
            .delay(for: .seconds(delay), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.reminders = Store.refreshDailyStatus(self?.reminders ?? [])
                self?.save()
                self?.scheduleMidnightReset()
            }
    }

    // ── MARK: Public Mutations ─────────────────────────────────────

    func completeSplash() {
        screen = settings.onboarded ? .home : .onboarding
    }

    func completeOnboarding(name: String) {
        settings.userName    = name
        settings.onboarded   = true
        screen               = .home
        save()
    }

    func toggleDone(_ id: UUID) {
        updateReminder(id) { r in
            let nowDone = !r.isDone
            r.isDone   = nowDone
            r.doneDate = nowDone ? todayISO() : nil
            if nowDone {
                let total = AdaptiveEngine.dailyNudgeCount(across: self.reminders)
                AdaptiveEngine.recordInteraction(.completed, on: &r, settings: self.settings, dailyTotalSent: total)
                self.scheduler.cancel(reminderId: id)
            }
        }
    }

    func removeReminder(_ id: UUID) {
        scheduler.cancel(reminderId: id)
        reminders.removeAll { $0.id == id }
        save()
    }

    func addReminder(
        text: String,
        analysis: TextAnalysis,
        frequency: FrequencyPreference,
        isRepeating: Bool,
        dueDate: Date?
    ) {
        var r = Reminder(
            text: text,
            category: analysis.category,
            frequency: frequency,
            timePreference: analysis.suggestedTimePreference,
            isRepeating: isRepeating || analysis.isHabit,
            dueDate: dueDate,
            hasGap: !reminders.isEmpty
        )
        let total = AdaptiveEngine.dailyNudgeCount(across: reminders)
        r.nextNudgeAt = AdaptiveEngine.nextNudgeDate(for: r, settings: settings, dailyTotalSent: total)

        reminders.append(r)
        save()

        Task { await scheduler.scheduleNudge(for: r, settings: settings) }
        showAddSheet = false
    }

    func recordInteraction(_ type: InteractionType, for id: UUID) {
        updateReminder(id) { r in
            let total = AdaptiveEngine.dailyNudgeCount(across: self.reminders)
            AdaptiveEngine.recordInteraction(type, on: &r, settings: self.settings, dailyTotalSent: total)
        }
    }

    func updateSettings(_ new: AppSettings) {
        settings = new
        save()
        Task {
            scheduler.cancelAll()
            await scheduler.scheduleAll(reminders, settings: settings)
        }
    }

    // ── MARK: Nudge Banner Responses ───────────────────────────────

    func nudgeDone() {
        if let nudge = activeNudge {
            markDone(nudge.reminderId)
        }
        activeNudge = nil
    }

    func nudgeLater() {
        if let nudge = activeNudge {
            recordInteraction(.skipped, for: nudge.reminderId)
        }
        activeNudge = nil
    }

    func nudgeDismiss() {
        if let nudge = activeNudge {
            recordInteraction(.ignored, for: nudge.reminderId)
        }
        activeNudge = nil
    }

    // ── MARK: Private Helpers ──────────────────────────────────────

    private func markDone(_ id: UUID) {
        toggleDone(id)
    }

    private func updateReminder(_ id: UUID, transform: (inout Reminder) -> Void) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        transform(&reminders[idx])
        save()
    }

    private func save() {
        Store.saveReminders(reminders)
        Store.saveSettings(settings)
    }

    private func todayISO() -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        return fmt.string(from: Calendar.current.startOfDay(for: .now))
    }
}

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @State private var deletingId: UUID?

    private var preview: String? {
        AdaptiveEngine.nextNudgePreview(for: state.reminders)
    }

    private var allDone: Bool {
        !state.reminders.isEmpty && state.reminders.allSatisfy(\.isDone)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Text("Hello, \(state.settings.userName)")
                                    .font(JGRFont.regular(22))
                                    .foregroundStyle(Color.jgrT1)
                                    .tracking(-0.4)
                                Text("👋").font(.system(size: 20))
                            }
                            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                                .font(JGRFont.regular(12.5))
                                .foregroundStyle(Color.jgrT3)
                                .tracking(0.1)
                        }
                        Spacer()
                        Button("Settings") { state.screen = .settings }
                            .font(JGRFont.regular(14))
                            .foregroundStyle(Color.jgrT3)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 28)

                    // Next nudge preview
                    HStack(spacing: 10) {
                        if let slot = preview {
                            PulsingDot()
                            Text("Next nudge")
                                .font(JGRFont.regular(13))
                                .foregroundStyle(Color.jgrT3)
                            Text("·").foregroundStyle(Color.jgrT4)
                            Text(slot)
                                .font(JGRFont.medium(13))
                                .foregroundStyle(Color.jgrT1)
                        } else {
                            Text("All quiet. Nothing pending.")
                                .font(JGRFont.regular(13))
                                .foregroundStyle(Color.jgrT3.opacity(0.65))
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 14)
                    .frame(minHeight: 28)

                    Spacer().frame(height: 52)
                    Eyebrow(text: "Today").padding(.horizontal, 32)
                    Spacer().frame(height: 24)

                    // Reminder list
                    LazyVStack(spacing: 0) {
                        ForEach(Array(state.reminders.enumerated()), id: \.element.id) { idx, r in
                            if r.hasGap && idx != 0 {
                                Spacer().frame(height: 24)
                            }
                            ReminderRowView(reminder: r) {
                                withAnimation(.easeInOut(duration: 0.45)) {
                                    state.toggleDone(r.id)
                                }
                            } onRemove: {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    state.removeReminder(r.id)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    if state.reminders.isEmpty {
                        Text("Nothing for today. That's perfectly fine.")
                            .font(JGRFont.regular(15))
                            .foregroundStyle(Color.jgrT3)
                            .padding(.horizontal, 32)
                            .padding(.top, 4)
                    }

                    Spacer().frame(height: 16)

                    // All-done message
                    if allDone {
                        Text("That's enough for today.")
                            .font(.system(size: 13.5, weight: .regular, design: .default))
                            .italic()
                            .foregroundStyle(Color.jgrT2)
                            .padding(.horizontal, 32)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // Spacer for bottom button
                    Spacer().frame(height: 100)
                }
            }
            .scrollIndicators(.hidden)

            // Add button
            HStack {
                Button {
                    state.showAddSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Text("+").font(.system(size: 17, weight: .light))
                        Text("Add a reminder").font(JGRFont.regular(15))
                    }
                    .foregroundStyle(Color.jgrT3)
                    .padding(.vertical, 6)
                }
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
        }
        .background(Color.jgrBg)
        .sheet(isPresented: $state.showAddSheet) {
            AddReminderView()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }
}

// MARK: - Reminder Row View

struct ReminderRowView: View {
    let reminder: Reminder
    let onToggle: () -> Void
    let onRemove: () -> Void

    @State private var offset: CGFloat    = 0
    @State private var revealed: Bool     = false
    @State private var dragActive: Bool   = false

    private var hasCat: Bool { reminder.category != .none }
    private var isSmart: Bool { reminder.frequency == .smart && reminder.dueDate == nil && !reminder.isDone }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Remove button revealed on swipe
            if revealed {
                Button("Remove") {
                    onRemove()
                }
                .font(JGRFont.regular(13))
                .foregroundStyle(Color.jgrT2)
                .padding(.trailing, 24)
                .transition(.opacity)
            }

            // Row button
            Button(action: {
                guard !dragActive else { return }
                if revealed { revealed = false; return }
                onToggle()
            }) {
                HStack(spacing: 18) {
                    JGRCheckbox(done: reminder.isDone)
                    Text(reminder.text)
                        .font(JGRFont.regular(17))
                        .foregroundStyle(reminder.isDone ? Color.jgrT3 : Color.jgrT1)
                        .strikethrough(reminder.isDone, color: Color.jgrT4)
                        .opacity(reminder.isDone ? 0.45 : 1)
                        .tracking(-0.2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    // Smart-timing dot
                    if isSmart {
                        Circle()
                            .fill(Color.jgrT3)
                            .frame(width: 4, height: 4)
                    }

                    // Repeat glyph or due-date badge
                    if let due = reminder.dueDate {
                        Text(formatShortDate(due))
                            .font(JGRFont.regular(11.5))
                            .foregroundStyle(Color.jgrT3)
                            .opacity(reminder.isDone ? 0.35 : 0.8)
                    } else if reminder.isRepeating {
                        Text("↻")
                            .font(JGRFont.regular(11.5))
                            .foregroundStyle(Color.jgrT3)
                            .opacity(reminder.isDone ? 0.35 : 0.8)
                    }
                }
                .padding(.vertical, 20)
                .padding(.leading, 16)
                .background(Color.jgrBg)
                .overlay(alignment: .leading) {
                    // Category capsule — 3px on left edge
                    if hasCat {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.categoryColor(reminder.category))
                            .frame(width: 3)
                            .opacity(reminder.isDone ? 0.25 : 0.75)
                            .padding(.vertical, 24)
                    }
                }
            }
            .buttonStyle(.plain)
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { g in
                        dragActive = true
                        let dx = g.translation.width
                        if dx < 0 {
                            offset = max(dx, -88)
                        } else if revealed {
                            offset = min(-88 + dx, 0)
                        }
                    }
                    .onEnded { g in
                        dragActive = false
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                            if offset < -44 { offset = -72; revealed = true }
                            else            { offset = 0;   revealed = false }
                        }
                    }
            )
            .animation(.easeInOut(duration: 0.45), value: reminder.isDone)
        }
        .clipped()
    }

    private func formatShortDate(_ date: Date) -> String {
        let cal    = Calendar.current
        let today  = cal.startOfDay(for: .now)
        let target = cal.startOfDay(for: date)
        let diff   = cal.dateComponents([.day], from: today, to: target).day ?? 0
        if diff == 0  { return "Today" }
        if diff == 1  { return "Tomorrow" }
        if diff == -1 { return "Yesterday" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE dd"
        return fmt.string(from: date)
    }
}

// MARK: - Nudge Banner View

struct NudgeBannerView: View {
    let nudge: ActiveNudge
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Category accent bar
                if nudge.category != .none {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.categoryColor(nudge.category))
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)
                        .opacity(0.75)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("A small nudge")
                        .font(JGRFont.eyebrow())
                        .tracking(1.0)
                        .foregroundStyle(Color.jgrT3)

                    Text(nudge.body)
                        .font(JGRFont.regular(15))
                        .foregroundStyle(Color.jgrT1)
                        .tracking(-0.1)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 20) {
                        Button("Done") { state.nudgeDone() }
                            .font(JGRFont.medium(14))
                            .foregroundStyle(Color.jgrT1)
                        Button("Later") { state.nudgeLater() }
                            .font(JGRFont.regular(14))
                            .foregroundStyle(Color.jgrT3)
                        Spacer()
                        Button("×") { state.nudgeDismiss() }
                            .font(JGRFont.light(18))
                            .foregroundStyle(Color.jgrT3)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color.jgrSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

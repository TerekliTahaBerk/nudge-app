import SwiftUI
import Combine
import UIKit

// MARK: - Screen enum

enum Screen: Hashable {
    case splash, onboarding, home, settings
}

// Which Behavior-layer card, if any, sits above the day's list.
// Only one banner shows at a time — they share the same slot above "Today".
enum BehaviorBanner: Equatable {
    case none
    case pattern(text: String)
    case quietHoldback
    case easedBack
    case maybeLater
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
    @Published var behaviorBanner: BehaviorBanner = .none

    // ── Internal ───────────────────────────────────────────────────
    private var nudgeTimer: AnyCancellable?
    private var midnightTimer: AnyCancellable?
    private var maybeLaterTimer: AnyCancellable?
    private let scheduler = NotificationScheduler.shared
    private var deviceContextAdapter: IOSDeviceContextAdapter?
    private var locationAdapter: IOSLocationTriggerAdapter?

    // ── Init ───────────────────────────────────────────────────────

    init() {
        let savedSettings  = Store.loadSettings()
        let savedReminders = Store.loadReminders()

        self.settings  = savedSettings
        self.reminders = savedReminders.isEmpty ? Reminder.seedReminders() : savedReminders
        reconcileLoadedReminderPlans()

        // Wire notification callbacks
        scheduler.onNudgeDone  = { [weak self] id in self?.markDone(id) }
        scheduler.onNudgeLater = { [weak self] id in
            self?.recordInteraction(.skipped, for: id)
        }
        scheduler.onNudgeOpened = { [weak self] id in
            self?.recordNotificationOpened(id)
        }

        // Start background services after init
        Task { await postInitSetup() }
    }

    private func postInitSetup() async {
        // ── Device context adapter (battery/charging) ──────────────
        let dca = IOSDeviceContextAdapter()
        dca.start { [weak self] event in
            Task { @MainActor in self?.recordTriggerEvent(event) }
        }
        deviceContextAdapter = dca

        // ── Location adapter (geofencing) ──────────────────────────
        let la = IOSLocationTriggerAdapter()
        la.onTriggerEvent = { [weak self] event in
            Task { @MainActor in self?.recordTriggerEvent(event) }
        }
        la.onPermissionChange = { [weak self] status in
            Task { @MainActor in
                self?.upsertPermission(.location, status: status)
                if let self {
                    self.locationAdapter?.reconcile(
                        aliases: self.settings.locationAliases,
                        reminders: self.reminders
                    )
                }
            }
        }
        locationAdapter = la
        la.requestPermission()
        upsertPermission(.location, status: la.currentAuthorizationStatus)

        // ── Notification permission ────────────────────────────────
        if await !scheduler.isAuthorized {
            _ = await scheduler.requestPermission()
        }
        await refreshNotificationPermissionState()

        // ── Reconcile everything on launch ─────────────────────────
        reconcileReminderSystemOnLaunch()
        startNudgeTimer()
        scheduleMidnightReset()
        await scheduler.scheduleAll(reminders, settings: settings)
        save()
        await MainActor.run { recomputeBehaviorBanner() }
    }

    // ── MARK: Behaviour banner resolution ──────────────────────────
    // Priority (highest first): eased-back > pattern > quiet held-back.
    // `.maybeLater` is set transiently by nudgeLater() and overrides
    // the others for ~12 seconds via a timer.

    func recomputeBehaviorBanner() {
        // maybeLater is transient — never overwrite it here.
        if case .maybeLater = behaviorBanner { return }

        if BehaviorAnalytics.shouldShowEasedBack(reminders: reminders),
           !settings.easedBackAcknowledged {
            behaviorBanner = .easedBack
            return
        }
        if let observation = BehaviorAnalytics.patternObservation(from: reminders) {
            behaviorBanner = .pattern(text: observation)
            return
        }
        if BehaviorAnalytics.wasYesterdayHeldBack(reminders: reminders) {
            behaviorBanner = .quietHoldback
            return
        }
        behaviorBanner = .none
    }

    func acknowledgeEasedBack() {
        settings.easedBackAcknowledged = true
        save()
        recomputeBehaviorBanner()
    }

    func undoEasedBack() {
        // Clear pause windows so nudges resume; engine can re-pause if needed.
        for idx in reminders.indices { reminders[idx].pausedUntil = nil }
        settings.easedBackAcknowledged = true
        save()
        Task {
            scheduler.cancelAll()
            await scheduler.scheduleAll(reminders, settings: settings)
        }
        recomputeBehaviorBanner()
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
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recordMorningFirstUnlockIfNeeded()
                self?.checkForDueNudges()
            }
        }
    }

    func checkForDueNudges() {
        guard activeNudge == nil else { return }   // already showing one

        for reminder in reminders {
            guard let due = reminder.nextNudgeAt, due <= .now else { continue }
            let result = NotificationPlanner.plan(
                for: reminder,
                context: NudgeDecisionContext(allReminders: reminders, settings: settings)
            )
            guard result.status == .scheduled else { continue }
            let body = NotificationPlanner.calmCopy(for: reminder)
            activeNudge = ActiveNudge(reminderId: reminder.id, body: body, category: reminder.category)
            // Push next nudge time forward so this doesn't re-fire immediately
            updateReminder(reminder.id) { r in
                self.applyPlanResult(result, to: &r)
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
        var becameDone = false
        updateReminder(id) { r in
            let nowDone = !r.isDone
            r.isDone   = nowDone
            r.doneDate = nowDone ? todayISO() : nil
            if nowDone {
                self.recordFeedback(.done, on: &r)
                self.scheduler.cancel(reminderId: id)
                becameDone = true
            } else {
                r.nextNudgeAt = nil
                let result = NotificationPlanner.plan(
                    for: r,
                    context: NudgeDecisionContext(allReminders: self.reminders, settings: self.settings)
                )
                self.applyPlanResult(result, to: &r)
            }
        }
        if becameDone {
            cascadeLinkedReminders(parentId: id)
        }
        recomputeBehaviorBanner()
    }

    // When a reminder is checked off, any reminder linked after it gets its
    // nextNudgeAt pushed to (now + delayMin). Notification is rescheduled so
    // the OS surfaces it even when the app is closed.
    private func cascadeLinkedReminders(parentId: UUID) {
        for idx in reminders.indices {
            let r = reminders[idx]
            guard r.type == .linked, r.link?.parentId == parentId, !r.isDone else { continue }
            let delay = TimeInterval((r.link?.delayMin ?? 10) * 60)
            reminders[idx].nextNudgeAt = Date.now.addingTimeInterval(delay)
        }
        save()
        Task {
            // Re-schedule any linked reminders whose time just changed.
            for r in reminders where r.type == .linked && r.link?.parentId == parentId && !r.isDone {
                scheduler.cancel(reminderId: r.id)
                await scheduler.scheduleNudge(for: r, settings: settings, allReminders: reminders)
            }
        }
    }

    func removeReminder(_ id: UUID) {
        scheduler.cancel(reminderId: id)
        reminders.removeAll { $0.id == id }
        settings.triggerEventLog.removeAll { $0.reminderId == id }
        settings.nudgeHistory.removeAll { $0.reminderId == id }
        settings.userFeedback.removeAll { $0.reminderId == id }
        save()
        locationAdapter?.reconcile(aliases: settings.locationAliases, reminders: reminders)
    }

    func addReminder(
        text: String,
        analysis: TextAnalysis,
        frequency: FrequencyPreference,
        isRepeating: Bool,
        dueDate: Date?,
        type: ReminderType = .standard,
        parsedIntent: ParsedReminderIntent,
        trigger: TriggerInfo? = nil,
        voice: VoiceInfo? = nil,
        link: LinkInfo? = nil
    ) {
        var r = Reminder(
            text: text,
            category: analysis.category,
            frequency: frequency,
            timePreference: analysis.suggestedTimePreference,
            isRepeating: isRepeating || (type == .standard && analysis.isHabit),
            dueDate: dueDate,
            hasGap: !reminders.isEmpty
        )
        r.type    = type
        r.trigger = trigger
        r.voice   = voice
        r.link    = link
        r.kind    = type == .standard ? parsedIntent.kind : ReminderKind(from: type)
        r.schedule = ReminderSchedule(
            cadence: parsedIntent.suggestedCadence,
            preferredWindow: parsedIntent.timeWindow,
            dailyCap: frequency.maxDailyNudges,
            lastPlannedAt: nil,
            confidence: parsedIntent.confidence,
            lastExplanation: parsedIntent.explanation,
            lastPlanStatus: nil,
            interpretationSummary: parsedIntent.interpretationSummary,
            fallbackSummary: parsedIntent.triggerReadiness?.fallbackStrategy?.explanation
        )
        if r.kind == .eventBased || type == .trigger {
            r.triggerDefinition = parsedIntent.trigger ?? trigger.map {
                ReminderTrigger(
                    condition: TriggerCondition(
                        type: $0.kind == .place ? .geofenceEnter : .customContext,
                        subject: $0.id,
                        locationAlias: $0.kind == .place ? $0.id : nil
                    ),
                    confidence: 0.6
                )
            }
        }

        let result = NotificationPlanner.plan(
            for: r,
            context: NudgeDecisionContext(allReminders: reminders, settings: settings)
        )
        applyPlanResult(result, to: &r)

        reminders.append(r)
        save()

        if type == .standard {
            Task { await scheduler.scheduleNudge(for: r, settings: settings, allReminders: reminders) }
        }
        if r.triggerDefinition?.condition.type == .geofenceEnter ||
           r.triggerDefinition?.condition.type == .geofenceExit {
            locationAdapter?.reconcile(aliases: settings.locationAliases, reminders: reminders)
        }
        showAddSheet = false
    }

    func recordInteraction(_ type: InteractionType, for id: UUID) {
        updateReminder(id) { r in
            let feedbackAction: UserFeedbackAction = switch type {
            case .completed: .done
            case .skipped: .maybeLater
            case .ignored: .ignored
            }
            self.recordFeedback(feedbackAction, on: &r)
        }
    }

    func recordNotificationOpened(_ id: UUID) {
        updateReminder(id) { r in
            self.recordFeedback(.opened, on: &r)
        }
    }

    func recordTriggerEvent(_ event: TriggerEvent) {
        var changedReminderIds: [UUID] = []
        for idx in reminders.indices {
            guard let trigger = reminders[idx].triggerDefinition else { continue }
            guard TriggerExecutionPolicy.shouldFire(
                condition: trigger.condition,
                event: event,
                eventLog: settings.triggerEventLog,
                now: event.createdAt
            ) else { continue }

            let result = NotificationPlanner.plan(
                for: reminders[idx],
                context: NudgeDecisionContext(allReminders: reminders, settings: settings, now: event.createdAt, triggeredBy: event)
            )
            applyPlanResult(result, to: &reminders[idx])
            reminders[idx].triggerDefinition?.lastFiredAt = event.createdAt
            settings.triggerEventLog.append(TriggerEventLog(
                triggerType: event.type,
                subject: event.subject,
                reminderId: reminders[idx].id,
                confidence: result.confidence,
                createdAt: event.createdAt,
                fired: result.isScheduled
            ))
            DebugLog.trigger("Event \(event.type.rawValue) for \(reminders[idx].id): \(result.status.rawValue)")
            changedReminderIds.append(reminders[idx].id)
        }
        guard !changedReminderIds.isEmpty else { return }
        save()
        Task {
            for id in changedReminderIds {
                guard let reminder = reminders.first(where: { $0.id == id }) else { continue }
                scheduler.cancel(reminderId: id)
                await scheduler.scheduleNudge(for: reminder, settings: settings, allReminders: reminders)
            }
            await MainActor.run { self.checkForDueNudges() }
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
        // Surface a brief receipt — same vocabulary as the design's
        // "Maybe later — receipt" card. Auto-dismisses after ~12 seconds.
        behaviorBanner = .maybeLater
        maybeLaterTimer?.cancel()
        maybeLaterTimer = Just(())
            .delay(for: .seconds(12), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                if case .maybeLater = self.behaviorBanner { self.behaviorBanner = .none }
                self.recomputeBehaviorBanner()
            }
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

    private func recordFeedback(_ action: UserFeedbackAction, on reminder: inout Reminder) {
        let feedback = FeedbackRecorder.record(action, reminder: &reminder, settings: settings)
        settings.userFeedback.append(feedback)
        settings.nudgeHistory.append(NudgeHistory(
            reminderId: reminder.id,
            plannedAt: reminder.nextNudgeAt ?? feedback.createdAt,
            deliveredAt: feedback.createdAt,
            action: action
        ))
        var rhythm = UserRhythmModel(profile: settings.userRhythmProfile)
        rhythm.record(feedback, category: reminder.category)
        settings.userRhythmProfile = rhythm.profile

        if action != .done {
            let result = NotificationPlanner.plan(
                for: reminder,
                context: NudgeDecisionContext(allReminders: reminders, settings: settings)
            )
            applyPlanResult(result, to: &reminder)
        }
    }

    private func applyPlanResult(_ result: NudgePlanResult, to reminder: inout Reminder, recordHistory: Bool = true) {
        reminder.schedule?.lastPlanStatus = result.status
        reminder.schedule?.lastExplanation = result.explanation
        reminder.schedule?.confidence = result.confidence
        DebugLog.plan("\(reminder.id): \(result.status.rawValue) - \(result.explanation.text)")
        guard let plan = result.plan else {
            reminder.nextNudgeAt = nil
            return
        }
        reminder.nextNudgeAt = plan.nextFireDate
        reminder.schedule?.preferredWindow = plan.window
        reminder.schedule?.lastPlannedAt = .now
        if recordHistory {
            settings.nudgeHistory.append(NudgeHistory(reminderId: reminder.id, plannedAt: plan.nextFireDate))
        }
    }

    private func reconcileLoadedReminderPlans() {
        for idx in reminders.indices where !reminders[idx].isDone {
            let isExpired = (reminders[idx].nextNudgeAt ?? .distantFuture) <= .now
            let missingReadiness = reminders[idx].schedule?.lastPlanStatus == nil
            guard reminders[idx].nextNudgeAt == nil || isExpired || missingReadiness else { continue }

            let result = NotificationPlanner.plan(
                for: reminders[idx],
                context: NudgeDecisionContext(allReminders: reminders, settings: settings)
            )
            applyPlanResult(result, to: &reminders[idx], recordHistory: false)
            DebugLog.plan("Reconciled loaded reminder \(reminders[idx].id)")
        }
    }

    private func reconcileReminderSystemOnLaunch() {
        reconcileLoadedReminderPlans()
        upsertPermission(.location, status: locationAdapter?.currentAuthorizationStatus ?? .unknown)
        locationAdapter?.reconcile(aliases: settings.locationAliases, reminders: reminders)
        save()
    }

    func reconcileLocationTriggers() {
        reconcileLoadedReminderPlans()
        locationAdapter?.reconcile(aliases: settings.locationAliases, reminders: reminders)
        save()
        Task { await scheduler.scheduleAll(reminders, settings: settings) }
    }

    private func recordMorningFirstUnlockIfNeeded(now: Date = .now) {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        guard hour >= settings.quietHoursEnd && hour <= 11 else { return }
        let day = todayISO()
        guard settings.lastMorningFirstUnlockDate != day else { return }
        settings.lastMorningFirstUnlockDate = day
        recordTriggerEvent(TriggerEventSimulator.morningFirstUnlock(now: now))
    }

    private func refreshNotificationPermissionState() async {
        let status: PermissionStatus = await scheduler.isAuthorized ? .granted : .denied
        upsertPermission(.notifications, status: status)
    }

    private func upsertPermission(_ permission: PermissionKind, status: PermissionStatus) {
        if let idx = settings.permissionStates.firstIndex(where: { $0.permission == permission }) {
            settings.permissionStates[idx].status = status
            settings.permissionStates[idx].updatedAt = .now
        } else {
            settings.permissionStates.append(PermissionState(permission: permission, status: status))
        }
    }

    #if DEBUG
    func auditReminderReadiness() -> [ReminderDebugSummary] {
        reminders.map { reminder in
            let result = NotificationPlanner.plan(
                for: reminder,
                context: NudgeDecisionContext(allReminders: reminders, settings: settings)
            )
            return ReminderDebugSummary(
                kind: reminder.kind,
                category: reminder.category,
                trigger: reminder.triggerDefinition?.condition,
                nextPlannedNudge: result.plan?.nextFireDate,
                confidence: result.confidence,
                status: result.status,
                explanation: result.explanation
            )
        }
    }

    func debugReminderSummary(for id: UUID) -> ReminderDebugSummary? {
        guard let reminder = reminders.first(where: { $0.id == id }) else { return nil }
        let result = NotificationPlanner.plan(
            for: reminder,
            context: NudgeDecisionContext(allReminders: reminders, settings: settings)
        )
        return ReminderDebugSummary(
            kind: reminder.kind,
            category: reminder.category,
            trigger: reminder.triggerDefinition?.condition,
            nextPlannedNudge: result.plan?.nextFireDate,
            confidence: result.confidence,
            status: result.status,
            explanation: result.explanation
        )
    }
    #endif

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

private extension ReminderKind {
    init(from type: ReminderType) {
        switch type {
        case .standard: self = .timeBased
        case .trigger: self = .eventBased
        case .voice: self = .voice
        case .linked: self = .followOn
        case .oneoff: self = .oneOff
        }
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

    private var behaviorHasContent: Bool {
        if case .none = state.behaviorBanner { return false }
        return true
    }

    @ViewBuilder
    private var behaviorBannerView: some View {
        switch state.behaviorBanner {
        case .none:
            EmptyView()
        case .pattern(let text):
            PatternCard(text: text)
        case .quietHoldback:
            QuietHoldback()
        case .easedBack:
            EasedBackBanner(
                onDismiss: { withAnimation(.easeOut(duration: 0.35)) { state.acknowledgeEasedBack() } },
                onUndo:    { withAnimation(.easeOut(duration: 0.35)) { state.undoEasedBack()        } }
            )
        case .maybeLater:
            MaybeLaterReceipt()
        }
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

                    Spacer().frame(height: 40)

                    // Behaviour banner — pattern / quiet / eased-back / maybeLater.
                    // One slot, one card. Renders nothing when there's no observation.
                    behaviorBannerView
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))

                    Spacer().frame(height: behaviorHasContent ? 16 : 0)
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

                    // Type glyph — only for non-standard kinds, hairline + etiketsiz
                    if reminder.type != .standard {
                        TypeGlyph(type: reminder.type)
                            .opacity(reminder.isDone ? 0.35 : 1)
                            .padding(.leading, 2)
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

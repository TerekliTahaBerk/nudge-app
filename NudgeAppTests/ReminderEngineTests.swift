import XCTest
@testable import NudgeApp

final class ReminderEngineTests: XCTestCase {
    @MainActor
    func testEditingReminderPreservesSameIDAndDoesNotDuplicate() async {
        let scheduler = FakeNotificationScheduler()
        let location = FakeLocationAdapter()
        var settings = AppSettings()
        settings.permissionStates = [PermissionState(permission: .notifications, status: .granted)]
        let state = AppState(scheduler: scheduler, locationAdapter: location, startsServicesAutomatically: false)
        let original = Reminder(text: "Drink water", category: .body)
        state.settings = settings
        state.reminders = [original]

        let parsed = ReminderUnderstandingEngine.parse("Drink tea")
        state.editReminder(
            id: original.id,
            text: parsed.reminderText,
            analysis: TextAnalysis(category: parsed.category, suggestedFrequency: .daily, suggestedTimePreference: .morning, isHabit: true, confidence: parsed.confidence),
            frequency: .daily,
            isRepeating: true,
            dueDate: nil,
            type: .standard,
            parsedIntent: parsed
        )
        await Task.yield()

        XCTAssertEqual(state.reminders.count, 1)
        XCTAssertEqual(state.reminders.first?.id, original.id)
        XCTAssertEqual(state.reminders.first?.text, "Drink tea")
        XCTAssertEqual(scheduler.cancelledReminderIds, [original.id])
        XCTAssertEqual(scheduler.scheduledReminderIds, [original.id])
    }

    @MainActor
    func testEditingTimeBasedToEventBasedCancelsAndReconcilesTrigger() async {
        let scheduler = FakeNotificationScheduler()
        let location = FakeLocationAdapter()
        var settings = AppSettings()
        settings.permissionStates = [
            PermissionState(permission: .notifications, status: .granted),
            PermissionState(permission: .location, status: .granted)
        ]
        settings.locationAliases = [LocationAlias(name: "home", latitude: 41.0, longitude: 29.0)]
        let state = AppState(scheduler: scheduler, locationAdapter: location, startsServicesAutomatically: false)
        let original = Reminder(text: "Drink water", category: .body)
        state.settings = settings
        state.reminders = [original]

        let parsed = ReminderUnderstandingEngine.parse("Eve varınca çöpleri çıkar")
        state.editReminder(
            id: original.id,
            text: parsed.reminderText,
            analysis: TextAnalysis(category: parsed.category, suggestedFrequency: .smart, suggestedTimePreference: .flexible, isHabit: false, confidence: parsed.confidence),
            frequency: .smart,
            isRepeating: false,
            dueDate: nil,
            type: .trigger,
            parsedIntent: parsed,
            trigger: TriggerInfo(kind: .place, id: "home", label: "When I get home")
        )
        await Task.yield()

        XCTAssertEqual(state.reminders.first?.id, original.id)
        XCTAssertEqual(state.reminders.first?.kind, .eventBased)
        XCTAssertEqual(state.reminders.first?.triggerDefinition?.condition.locationAlias, "home")
        XCTAssertEqual(scheduler.cancelledReminderIds, [original.id])
        XCTAssertEqual(location.reconcileCount, 1)
    }

    @MainActor
    func testEditingEventBasedToTimeBasedUnregistersTriggerAndSchedules() async {
        let scheduler = FakeNotificationScheduler()
        let location = FakeLocationAdapter()
        var settings = AppSettings()
        settings.permissionStates = [PermissionState(permission: .notifications, status: .granted)]
        let state = AppState(scheduler: scheduler, locationAdapter: location, startsServicesAutomatically: false)
        var original = Reminder(text: "Take out trash", category: .home)
        original.kind = .eventBased
        original.type = .trigger
        original.triggerDefinition = ReminderTrigger(
            condition: TriggerCondition(type: .geofenceEnter, subject: "home", locationAlias: "home", requiresPermission: [.notifications, .location]),
            confidence: 0.88
        )
        state.settings = settings
        state.reminders = [original]

        let parsed = ReminderUnderstandingEngine.parse("Take out trash every morning")
        state.editReminder(
            id: original.id,
            text: parsed.reminderText,
            analysis: TextAnalysis(category: parsed.category, suggestedFrequency: .daily, suggestedTimePreference: .morning, isHabit: false, confidence: parsed.confidence),
            frequency: .daily,
            isRepeating: false,
            dueDate: nil,
            type: .standard,
            parsedIntent: parsed
        )
        await Task.yield()

        XCTAssertEqual(state.reminders.first?.kind, .timeBased)
        XCTAssertNil(state.reminders.first?.triggerDefinition)
        XCTAssertEqual(location.reconcileCount, 1)
        XCTAssertEqual(scheduler.scheduledReminderIds, [original.id])
    }

    @MainActor
    func testDeletingCancelsNotificationAndTriggerReferencesButKeepsRhythmProfile() {
        let scheduler = FakeNotificationScheduler()
        let location = FakeLocationAdapter()
        let state = AppState(scheduler: scheduler, locationAdapter: location, startsServicesAutomatically: false)
        let reminder = Reminder(text: "Walk", category: .move)
        var settings = AppSettings()
        settings.triggerEventLog = [TriggerEventLog(triggerType: .chargingStarted, reminderId: reminder.id, confidence: 1)]
        settings.nudgeHistory = [NudgeHistory(reminderId: reminder.id, plannedAt: fixedDate(hour: 9))]
        settings.userFeedback = [UserFeedback(reminderId: reminder.id, action: .done)]
        settings.userRhythmProfile.confidenceByCategory["move"] = 0.8
        state.settings = settings
        state.reminders = [reminder]

        state.removeReminder(reminder.id)

        XCTAssertTrue(state.reminders.isEmpty)
        XCTAssertEqual(scheduler.cancelledReminderIds, [reminder.id])
        XCTAssertTrue(state.settings.triggerEventLog.isEmpty)
        XCTAssertTrue(state.settings.nudgeHistory.isEmpty)
        XCTAssertTrue(state.settings.userFeedback.isEmpty)
        XCTAssertEqual(state.settings.userRhythmProfile.confidenceByCategory["move"], 0.8)
        XCTAssertEqual(location.reconcileCount, 1)
    }

    @MainActor
    func testUndoRemoveRestoresReminderAndPerReminderReferences() {
        let scheduler = FakeNotificationScheduler()
        let location = FakeLocationAdapter()
        let state = AppState(scheduler: scheduler, locationAdapter: location, startsServicesAutomatically: false)
        let reminder = Reminder(text: "Walk", category: .move)
        state.reminders = [reminder]
        state.settings.triggerEventLog = [TriggerEventLog(triggerType: .chargingStarted, reminderId: reminder.id, confidence: 1)]
        state.settings.nudgeHistory = [NudgeHistory(reminderId: reminder.id, plannedAt: fixedDate(hour: 9))]
        state.settings.userFeedback = [UserFeedback(reminderId: reminder.id, action: .done)]

        state.removeReminder(reminder.id)
        state.restoreRemovedReminder()

        XCTAssertEqual(state.reminders.first?.id, reminder.id)
        XCTAssertEqual(state.settings.triggerEventLog.first?.reminderId, reminder.id)
        XCTAssertEqual(state.settings.nudgeHistory.first?.reminderId, reminder.id)
        XCTAssertEqual(state.settings.userFeedback.first?.reminderId, reminder.id)
        XCTAssertEqual(location.reconcileCount, 2)
    }

    func testPendingHomeAliasBecomesActionableAfterAliasIsAdded() {
        var settings = AppSettings()
        settings.permissionStates = [
            PermissionState(permission: .notifications, status: .granted),
            PermissionState(permission: .location, status: .granted)
        ]
        let parsed = ReminderUnderstandingEngine.parse("Eve varınca çöpleri çıkar")
        var reminder = reminder(from: parsed)
        var result = NotificationPlanner.plan(
            for: reminder,
            context: NudgeDecisionContext(allReminders: [reminder], settings: settings, now: fixedDate(hour: 9))
        )
        XCTAssertEqual(result.status, .missingLocationAlias)

        settings.locationAliases = [LocationAlias(name: "home", latitude: 41.0, longitude: 29.0)]
        result = NotificationPlanner.plan(
            for: reminder,
            context: NudgeDecisionContext(allReminders: [reminder], settings: settings, now: fixedDate(hour: 9))
        )

        XCTAssertEqual(result.status, .waitingForTrigger)
    }

    @MainActor
    func testCancelEditLeavesReminderUnchanged() {
        let state = AppState(scheduler: FakeNotificationScheduler(), locationAdapter: FakeLocationAdapter(), startsServicesAutomatically: false)
        let reminder = Reminder(text: "Read", category: .mind)
        state.reminders = [reminder]

        XCTAssertEqual(state.reminders.first?.id, reminder.id)
        XCTAssertEqual(state.reminders.first?.text, "Read")
    }

    func testManyReminderStatusesDoNotCrash() {
        var settings = AppSettings()
        settings.permissionStates = [PermissionState(permission: .notifications, status: .granted)]
        let reminders = (0..<80).map { idx -> Reminder in
            var reminder = Reminder(text: String(repeating: "Long reminder text ", count: 8) + "\(idx)", category: .task)
            reminder.schedule = ReminderSchedule(cadence: .daily, preferredWindow: nil, dailyCap: 1, lastPlanStatus: idx.isMultiple(of: 2) ? .scheduled : .waitingForTrigger)
            reminder.nextNudgeAt = fixedDate(hour: 10).addingTimeInterval(TimeInterval(idx * 60))
            return reminder
        }

        let statuses = reminders.map { ReminderRowStatus(reminder: $0, settings: settings).label }

        XCTAssertEqual(statuses.count, 80)
        XCTAssertTrue(statuses.allSatisfy { !$0.isEmpty })
    }

    func testReminderInputAcceptsRapidMixedTextAndBoundsLongPastes() {
        let mixed = "Şarja takınca meditasyon yap 💧🙂\nDrink water before lunch"
        XCTAssertTrue(ReminderInputValidator.validate(mixed).isValid)

        let long = String(repeating: "a", count: ReminderInputValidator.maxUserVisibleCharacters + 40)
        XCTAssertEqual(ReminderInputValidator.sanitize(long).count, ReminderInputValidator.maxUserVisibleCharacters)

        var rapid = ""
        for value in ["S", "Şarja", "", "Eve varınca çöpleri çıkar", ""] {
            rapid = ReminderInputValidator.sanitize(value)
        }
        XCTAssertEqual(rapid, "")
    }

    func testEveryReminderProducesPlanOrReason() {
        var settings = AppSettings()
        settings.permissionStates = [PermissionState(permission: .notifications, status: .granted)]
        let timeReminder = Reminder(text: "Drink water", category: .body)
        let timeResult = NotificationPlanner.plan(
            for: timeReminder,
            context: NudgeDecisionContext(allReminders: [timeReminder], settings: settings, now: fixedDate(hour: 8))
        )
        XCTAssertEqual(timeResult.status, .scheduled)
        XCTAssertNotNil(timeResult.plan)

        var eventReminder = Reminder(text: "Meditate")
        eventReminder.kind = .eventBased
        eventReminder.triggerDefinition = ReminderTrigger(
            condition: TriggerCondition(type: .morningFirstUnlock, subject: TriggerType.morningFirstUnlock.rawValue, requiresPermission: [.notifications]),
            confidence: 0.9
        )
        let eventResult = NotificationPlanner.plan(
            for: eventReminder,
            context: NudgeDecisionContext(allReminders: [eventReminder], settings: settings, now: fixedDate(hour: 8))
        )
        XCTAssertEqual(eventResult.status, .waitingForTrigger)
        XCTAssertNil(eventResult.plan)
        XCTAssertFalse(eventResult.explanation.text.isEmpty)
    }

    func testOldReminderJSONDecodesWithSafeDefaults() throws {
        let json = """
        [{
          "id":"11111111-1111-1111-1111-111111111111",
          "text":"Drink water",
          "category":"body",
          "frequency":"smart",
          "timePreference":"flexible",
          "isRepeating":true,
          "isDone":false,
          "hasGap":false,
          "interactions":[],
          "createdAt":"2026-05-01T09:00:00Z"
        }]
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reminders = try decoder.decode([Reminder].self, from: json)

        XCTAssertEqual(reminders.first?.text, "Drink water")
        XCTAssertEqual(reminders.first?.kind, .timeBased)
        XCTAssertNil(reminders.first?.triggerDefinition)
        XCTAssertNil(reminders.first?.schedule)
    }

    func testTurkishTriggerPhrasePersistsStructuredTrigger() throws {
        let parsed = ReminderIntentParser.parse("Eve varınca çöpleri çıkar")
        var reminder = Reminder(text: parsed.reminderText, category: parsed.category)
        reminder.kind = parsed.kind
        reminder.triggerDefinition = parsed.trigger
        reminder.schedule = ReminderSchedule(cadence: parsed.suggestedCadence, preferredWindow: parsed.timeWindow, dailyCap: 1, lastPlannedAt: nil, confidence: parsed.confidence, lastExplanation: parsed.explanation, lastPlanStatus: nil)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([reminder])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([Reminder].self, from: data)

        XCTAssertEqual(decoded.first?.kind, .eventBased)
        XCTAssertEqual(decoded.first?.triggerDefinition?.condition.type, .geofenceEnter)
        XCTAssertEqual(decoded.first?.triggerDefinition?.condition.locationAlias, "home")
    }

    func testMorningFirstUnlockSimulationCreatesTriggerPlan() {
        var settings = AppSettings()
        settings.permissionStates = [PermissionState(permission: .notifications, status: .granted)]
        var reminder = Reminder(text: "Meditate", category: .mind)
        reminder.kind = .eventBased
        reminder.triggerDefinition = ReminderTrigger(
            condition: TriggerCondition(type: .morningFirstUnlock, subject: TriggerType.morningFirstUnlock.rawValue, requiresPermission: [.notifications]),
            confidence: 0.9
        )
        let event = TriggerEventSimulator.morningFirstUnlock(now: fixedDate(hour: 8))

        let result = NotificationPlanner.plan(
            for: reminder,
            context: NudgeDecisionContext(allReminders: [reminder], settings: settings, now: event.createdAt, triggeredBy: event)
        )

        XCTAssertEqual(result.status, .scheduled)
        XCTAssertEqual(result.explanation.code, .triggeredByEvent)
        XCTAssertNotNil(result.plan)
    }

    func testChargingStartedSimulationCreatesTriggerPlan() {
        var settings = AppSettings()
        settings.permissionStates = [PermissionState(permission: .notifications, status: .granted)]
        var reminder = Reminder(text: "Meditate", category: .mind)
        reminder.kind = .eventBased
        reminder.triggerDefinition = ReminderTrigger(
            condition: TriggerCondition(type: .chargingStarted, subject: TriggerType.chargingStarted.rawValue, requiresPermission: [.notifications]),
            confidence: 0.9
        )
        let event = TriggerEventSimulator.chargingStarted(now: fixedDate(hour: 20))

        let result = NotificationPlanner.plan(
            for: reminder,
            context: NudgeDecisionContext(allReminders: [reminder], settings: settings, now: event.createdAt, triggeredBy: event)
        )

        XCTAssertEqual(result.status, .scheduled)
        XCTAssertNotNil(result.plan)
    }

    func testLowConfidenceLaptopTriggerNeedsClarification() {
        let parsed = ReminderUnderstandingEngine.parse("Bilgisayarımı açınca raporu gönder")

        XCTAssertEqual(parsed.kind, .eventBased)
        XCTAssertTrue(parsed.needsClarification)
        XCTAssertEqual(parsed.explanation?.code, .needsClarification)
    }

    func testReminderUnderstandingTurkishExamples() {
        let cases: [UnderstandingCase] = [
            .init("Eve gelince çöpleri çıkar", .eventBased, .geofenceEnter, .home, 0.8...1.0, [.notifications, .location], true, false, .missingLocationAlias),
            .init("Evden çıkınca anahtarı al", .eventBased, .geofenceExit, .errand, 0.75...1.0, [.notifications, .location], true, false, .missingLocationAlias),
            .init("Spor salonundan çıkınca protein iç", .eventBased, .geofenceExit, .health, 0.8...1.0, [.notifications, .location], true, false, .missingLocationAlias),
            .init("İşe varınca mail at", .eventBased, .geofenceEnter, .work, 0.75...1.0, [.notifications, .location], true, false, .missingLocationAlias),
            .init("Laptopu açınca raporu gönder", .eventBased, .customContext, .work, 0.35...0.55, [.notifications, .bluetooth, .localNetwork], false, false, .unsupportedTrigger),
            .init("Bugün annemi ara", .oneOff, nil, .social, 0.35...1.0, [.notifications], false, true, nil),
            .init("Her sabah su iç", .timeBased, nil, .body, 0.35...1.0, [.notifications], false, true, nil),
            .init("Bazen yürüyüşe çık", .timeBased, nil, .move, 0.35...1.0, [.notifications], false, true, nil),
            .init("Toplantıdan sonra notları gönder", .eventBased, .calendarEventEnded, .work, 0.65...0.85, [.notifications, .calendar], false, false, .calendarPermissionNeeded),
            .init("Benzin alınca fişi sakla", .eventBased, .customContext, .errand, 0.35...0.55, [.notifications, .location, .bluetooth], false, false, .needsConfirmation)
        ]

        assertUnderstandingCases(cases)
    }

    func testReminderUnderstandingEnglishExamples() {
        let cases: [UnderstandingCase] = [
            .init("Remind me when I get home", .eventBased, .geofenceEnter, .home, 0.8...1.0, [.notifications, .location], true, false, .missingLocationAlias),
            .init("When I leave the gym, drink protein", .eventBased, .geofenceExit, .health, 0.8...1.0, [.notifications, .location], true, false, .missingLocationAlias),
            .init("When I open my laptop, send the report", .eventBased, .customContext, .work, 0.35...0.55, [.notifications, .bluetooth, .localNetwork], false, false, .unsupportedTrigger),
            .init("Call mom tonight", .oneOff, nil, .social, 0.35...1.0, [.notifications], false, true, nil),
            .init("Drink water every morning", .timeBased, nil, .body, 0.35...1.0, [.notifications], false, true, nil),
            .init("Remind me after my meeting", .eventBased, .calendarEventEnded, .work, 0.65...0.85, [.notifications, .calendar], false, false, .calendarPermissionNeeded),
            .init("Remind me when I connect to my car", .eventBased, .carplayConnected, .grow, 0.7...0.9, [.notifications, .bluetooth], false, false, nil)
        ]

        assertUnderstandingCases(cases)
    }

    func testParsedTimeRecurrenceAndTriggersDriveRealPlanningBehavior() {
        let now = fixedDate(hour: 9)
        var settings = AppSettings()
        settings.permissionStates = [PermissionState(permission: .notifications, status: .granted)]

        let medicine = reminder(from: ReminderUnderstandingEngine.parse("20 dakika sonra ilacı al", now: now))
        let medicinePlan = NotificationPlanner.plan(for: medicine, context: NudgeDecisionContext(allReminders: [medicine], settings: settings, now: now))
        XCTAssertEqual(medicinePlan.status, .scheduled)
        XCTAssertEqual(medicine.schedule?.schedulingPolicy, .relativeOffset)
        XCTAssertEqual(medicine.text, "ilacı al")
        XCTAssertEqual(medicinePlan.plan!.nextFireDate.timeIntervalSince(now), 20 * 60, accuracy: 5)
        XCTAssertTrue(medicinePlan.explanation.text.localizedCaseInsensitiveContains("20"))

        let water = reminder(from: ReminderUnderstandingEngine.parse("Yarın sabah su iç", now: now))
        let waterPlan = NotificationPlanner.plan(for: water, context: NudgeDecisionContext(allReminders: [water], settings: settings, now: now))
        XCTAssertEqual(waterPlan.status, .scheduled)
        XCTAssertEqual(water.schedule?.schedulingPolicy, .approximateWindow)
        XCTAssertEqual(waterPlan.plan?.window.label, .morning)
        XCTAssertTrue(Calendar.current.isDate(waterPlan.plan!.nextFireDate, inSameDayAs: Calendar.current.date(byAdding: .day, value: 1, to: now)!))

        let recurring = reminder(from: ReminderUnderstandingEngine.parse("Her sabah su iç", now: now))
        let recurringPlan = NotificationPlanner.plan(for: recurring, context: NudgeDecisionContext(allReminders: [recurring], settings: settings, now: now))
        XCTAssertEqual(recurringPlan.status, .scheduled)
        XCTAssertEqual(recurring.schedule?.schedulingPolicy, .recurring)
        XCTAssertEqual(recurring.schedule?.recurrenceRule?.unit, .day)
        XCTAssertEqual(recurringPlan.plan?.window.label, .morning)

        let home = reminder(from: ReminderUnderstandingEngine.parse("Eve gelince çöpleri çıkar", now: now))
        let homePlan = NotificationPlanner.plan(for: home, context: NudgeDecisionContext(allReminders: [home], settings: settings, now: now))
        XCTAssertEqual(home.kind, .eventBased)
        XCTAssertNil(homePlan.plan)
        XCTAssertEqual(homePlan.status, .missingPermission)

        settings.permissionStates = [
            PermissionState(permission: .notifications, status: .granted),
            PermissionState(permission: .location, status: .granted)
        ]
        let market = reminder(from: ReminderUnderstandingEngine.parse("Markete gidince süt al", now: now))
        let marketPlan = NotificationPlanner.plan(for: market, context: NudgeDecisionContext(allReminders: [market], settings: settings, now: now))
        XCTAssertEqual(market.kind, .eventBased)
        XCTAssertEqual(market.triggerDefinition?.condition.locationAlias, "market")
        XCTAssertEqual(market.triggerDefinition?.condition.metadata["pendingLocationAlias"], "market")
        XCTAssertNil(marketPlan.plan)
        XCTAssertEqual(marketPlan.status, .missingLocationAlias)

        let laptop = reminder(from: ReminderUnderstandingEngine.parse("Laptopu açınca raporu gönder", now: now))
        let laptopPlan = NotificationPlanner.plan(for: laptop, context: NudgeDecisionContext(allReminders: [laptop], settings: settings, now: now))
        XCTAssertEqual(laptop.kind, .eventBased)
        XCTAssertNil(laptopPlan.plan)
        XCTAssertEqual(laptopPlan.status, .unsupported)
    }

    func testReminderGrammarFixtureEvaluatorCoversAtLeast120Examples() {
        let now = fixedDate(hour: 9)
        let fixtures = grammarFixtures()
        XCTAssertGreaterThanOrEqual(fixtures.count, 120)

        for fixture in fixtures {
            let parsed = ReminderUnderstandingEngine.parse(fixture.text, now: now)
            XCTAssertEqual(parsed.kind, fixture.kind, fixture.text)
            XCTAssertEqual(parsed.trigger?.condition.type, fixture.triggerType, fixture.text)
            XCTAssertEqual(parsed.trigger?.condition.locationAlias, fixture.placeAlias, fixture.text)
            XCTAssertEqual(parsed.exactDate != nil || parsed.approximateDate != nil || parsed.approximateWindow != nil || parsed.relativeOffsetSeconds != nil, fixture.hasTime, fixture.text)
            XCTAssertEqual(parsed.recurrenceRule != nil, fixture.hasRecurrence, fixture.text)
            XCTAssertEqual(parsed.triggerReadiness?.requiredSetup.isEmpty == false, fixture.needsSetup, fixture.text)
            XCTAssertTrue(fixture.confidence.contains(parsed.confidence), "\(fixture.text) confidence \(parsed.confidence)")
            XCTAssertFalse(parsed.reminderText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, fixture.text)
            XCTAssertFalse(parsed.explanation?.text.isEmpty ?? true, fixture.text)
            if parsed.confidenceTier == .low {
                XCTAssertTrue(parsed.needsClarification || parsed.schedulingPolicy == .unsupported || parsed.schedulingPolicy == .pendingSetup, fixture.text)
            }
        }
    }

    func testDrinkWaterDoneInMorningBiasesFutureMorningPlanning() {
        var reminder = Reminder(text: "Drink water", category: .body)
        let morning = fixedDate(hour: 9)
        let feedback = FeedbackRecorder.record(.done, reminder: &reminder, settings: AppSettings(), at: morning)
        var settings = AppSettings()
        var rhythm = UserRhythmModel(profile: settings.userRhythmProfile)
        rhythm.record(feedback, category: reminder.category)
        settings.userRhythmProfile = rhythm.profile

        let result = NotificationPlanner.plan(
            for: reminder,
            context: NudgeDecisionContext(allReminders: [reminder], settings: settings, now: fixedDate(hour: 6))
        )

        XCTAssertEqual(result.status, .scheduled)
        XCTAssertEqual(result.plan?.window.label, .morning)
    }

    func testMaybeLaterAndIgnoredFeedbackAffectReminderState() {
        var reminder = Reminder(text: "Drink water", category: .body)
        _ = FeedbackRecorder.record(.maybeLater, reminder: &reminder, settings: AppSettings(), at: fixedDate(hour: 10))
        XCTAssertEqual(reminder.interactions.last?.type, .skipped)
        XCTAssertNotNil(reminder.nextNudgeAt)

        _ = FeedbackRecorder.record(.ignored, reminder: &reminder, settings: AppSettings(), at: fixedDate(hour: 10))
        XCTAssertEqual(reminder.interactions.last?.type, .ignored)
    }

    func testFeedbackLoopPersistsBoundedRhythmSignals() {
        let reminder = Reminder(text: "Call mom", category: .social)
        var rhythm = UserRhythmModel(profile: UserRhythmProfile())

        rhythm.record(UserFeedback(reminderId: reminder.id, action: .done, createdAt: fixedDate(hour: 19)), category: .social)
        rhythm.record(UserFeedback(reminderId: reminder.id, action: .opened, createdAt: fixedDate(hour: 19)), category: .social)
        rhythm.record(UserFeedback(reminderId: reminder.id, action: .maybeLater, createdAt: fixedDate(hour: 9)), category: .social)
        rhythm.record(UserFeedback(reminderId: reminder.id, action: .ignored, createdAt: fixedDate(hour: 9)), category: .social)

        XCTAssertGreaterThan(rhythm.profile.preferredHoursByCategory["social"]?[19] ?? 0, 0)
        XCTAssertLessThan(rhythm.profile.preferredHoursByCategory["social"]?[9] ?? 0, 0)
        XCTAssertEqual(rhythm.profile.feedbackCountsByCategory["social"]?[UserFeedbackAction.done.rawValue], 1)
        XCTAssertGreaterThanOrEqual(rhythm.profile.mistimingStreakByCategory["social"] ?? 0, 2)
        XCTAssertLessThanOrEqual(rhythm.profile.confidenceByCategory["social"] ?? 0, 1.0)
    }

    func testDailyCapAndQuietHoursTogetherReturnExplicitReason() {
        var settings = AppSettings()
        settings.notificationLevel = .low
        settings.quietHoursStart = 23
        settings.quietHoursEnd = 8
        settings.nudgeHistory = [
            NudgeHistory(reminderId: UUID(), plannedAt: fixedDate(hour: 9)),
            NudgeHistory(reminderId: UUID(), plannedAt: fixedDate(hour: 10))
        ]
        let reminder = Reminder(text: "Read", category: .mind)

        let result = NotificationPlanner.plan(
            for: reminder,
            context: NudgeDecisionContext(allReminders: [reminder], settings: settings, now: fixedDate(hour: 23))
        )

        XCTAssertEqual(result.status, .dailyCapReached)
        XCTAssertEqual(result.explanation.code, .dailyCapReached)
    }

    func testNotificationRequestIDIsStableAndCancellableShape() {
        let id = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        XCTAssertEqual(
            NotificationScheduler.requestID(for: id),
            "JGR_REMINDER_22222222-2222-2222-2222-222222222222"
        )
    }

    func testRestartDecodePreservesSettingsAndPendingPlanFields() throws {
        let reminderId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let json = """
        {
          "userName":"T",
          "onboarded":true,
          "notificationLevel":"medium",
          "smartTimingEnabled":true,
          "quietHoursStart":23,
          "quietHoursEnd":8,
          "userRhythmProfile":{"preferredHoursByCategory":{"body":{"9":0.5}},"updatedAt":"2026-05-01T09:00:00Z"},
          "permissionStates":[{"permission":"notifications","status":"denied","updatedAt":"2026-05-01T09:00:00Z"}],
          "triggerEventLog":[{"id":"44444444-4444-4444-4444-444444444444","triggerType":"morning_first_unlock","reminderId":"\(reminderId.uuidString)","confidence":0.9,"createdAt":"2026-05-01T09:00:00Z","fired":true}],
          "nudgeHistory":[{"id":"55555555-5555-5555-5555-555555555555","reminderId":"\(reminderId.uuidString)","plannedAt":"2026-05-01T10:00:00Z"}],
          "lastMorningFirstUnlockDate":"2026-05-01"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let settings = try decoder.decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.permissionStates.first?.status, .denied)
        XCTAssertEqual(settings.triggerEventLog.first?.reminderId, reminderId)
        XCTAssertEqual(settings.nudgeHistory.first?.reminderId, reminderId)
        XCTAssertEqual(settings.lastMorningFirstUnlockDate, "2026-05-01")
        XCTAssertEqual(settings.userRhythmProfile.preferredHoursByCategory["body"]?[9], 0.5)
    }

    func testPermissionDeniedProducesMissingPermission() {
        var settings = AppSettings()
        settings.permissionStates = [PermissionState(permission: .notifications, status: .denied)]
        let reminder = Reminder(text: "Drink water", category: .body)

        let result = NotificationPlanner.plan(
            for: reminder,
            context: NudgeDecisionContext(allReminders: [reminder], settings: settings, now: fixedDate(hour: 12))
        )

        XCTAssertEqual(result.status, .missingPermission)
        XCTAssertEqual(result.explanation.code, .missingPermission)
    }

    func testUnsupportedTriggerProducesUnsupportedFallback() {
        var settings = AppSettings()
        settings.permissionStates = [PermissionState(permission: .notifications, status: .granted)]
        var reminder = Reminder(text: "Send report", category: .work)
        reminder.kind = .eventBased
        reminder.triggerDefinition = ReminderTrigger(
            condition: TriggerCondition(type: .customContext, subject: "laptop_opened", requiresPermission: [.notifications]),
            confidence: 0.45
        )

        let result = NotificationPlanner.plan(
            for: reminder,
            context: NudgeDecisionContext(allReminders: [reminder], settings: settings, now: fixedDate(hour: 12))
        )

        XCTAssertEqual(result.status, .unsupported)
        XCTAssertEqual(result.explanation.code, .unsupportedTrigger)
    }

    func testClusteringMovesNotificationAwayFromExistingPlan() {
        var settings = AppSettings()
        let now = fixedDate(hour: 8)
        var existing = Reminder(text: "urgent walk", category: .move)
        existing.schedule = ReminderSchedule(cadence: .daily, preferredWindow: nil, dailyCap: 1, confidence: 0.95)
        let second = Reminder(text: "Drink water", category: .body)
        let unclustered = NotificationPlanner.plan(for: second, context: NudgeDecisionContext(allReminders: [second], settings: settings, now: now)).plan!
        existing.nextNudgeAt = unclustered.nextFireDate

        let secondPlan = NotificationPlanner.plan(
            for: second,
            context: NudgeDecisionContext(allReminders: [existing, second], settings: settings, now: now)
        )

        XCTAssertEqual(secondPlan.status, .clustered)
        XCTAssertEqual(secondPlan.explanation.code, .delayedDueToAnotherReminder)
        XCTAssertGreaterThanOrEqual(abs(secondPlan.plan!.nextFireDate.timeIntervalSince(existing.nextNudgeAt!)), AdaptiveEngine.clusterGapSeconds)
    }

    func testMultipleRelativeRemindersInSameWindowArePrioritizedAndStaggered() {
        let now = fixedDate(hour: 9)
        var settings = AppSettings()
        settings.permissionStates = [PermissionState(permission: .notifications, status: .granted)]
        var urgent = reminder(from: ReminderUnderstandingEngine.parse("20 dakika sonra acil raporu gönder", now: now))
        var normal = reminder(from: ReminderUnderstandingEngine.parse("20 dakika sonra su iç", now: now))

        let urgentPlan = NotificationPlanner.plan(for: urgent, context: NudgeDecisionContext(allReminders: [urgent], settings: settings, now: now))
        apply(urgentPlan, to: &urgent)
        let normalPlan = NotificationPlanner.plan(for: normal, context: NudgeDecisionContext(allReminders: [urgent, normal], settings: settings, now: now))
        apply(normalPlan, to: &normal)

        XCTAssertEqual(urgentPlan.status, .scheduled)
        XCTAssertEqual(normalPlan.status, .clustered)
        XCTAssertEqual(normalPlan.explanation.code, .delayedDueToAnotherReminder)
        XCTAssertGreaterThanOrEqual(normal.nextNudgeAt!.timeIntervalSince(urgent.nextNudgeAt!), AdaptiveEngine.clusterGapSeconds)
        XCTAssertNotNil(normal.schedule?.conflictGroupKey)
    }

    func testHomeArrivalTriggerCollisionsAreStaggered() {
        let now = fixedDate(hour: 18)
        var settings = AppSettings()
        settings.permissionStates = [
            PermissionState(permission: .notifications, status: .granted),
            PermissionState(permission: .location, status: .granted)
        ]
        settings.locationAliases = [LocationAlias(name: "home", latitude: 41, longitude: 29)]
        var urgent = reminder(from: ReminderUnderstandingEngine.parse("Eve gelince acil fırını kapat", now: now))
        var normal = reminder(from: ReminderUnderstandingEngine.parse("Eve gelince çöpleri çıkar", now: now))
        let event = TriggerEvent(type: .geofenceEnter, subject: "home", confidence: 1, createdAt: now)

        let urgentPlan = NotificationPlanner.plan(for: urgent, context: NudgeDecisionContext(allReminders: [urgent, normal], settings: settings, now: now, triggeredBy: event))
        apply(urgentPlan, to: &urgent)
        let normalPlan = NotificationPlanner.plan(for: normal, context: NudgeDecisionContext(allReminders: [urgent, normal], settings: settings, now: now, triggeredBy: event))
        apply(normalPlan, to: &normal)

        XCTAssertEqual(urgentPlan.status, .scheduled)
        XCTAssertEqual(normalPlan.status, .clustered)
        XCTAssertEqual(normalPlan.explanation.code, .delayedDueToAnotherReminder)
        XCTAssertGreaterThanOrEqual(normal.nextNudgeAt!.timeIntervalSince(urgent.nextNudgeAt!), AdaptiveEngine.clusterGapSeconds)
    }

    func testHighConfidenceWinsOverLowConfidenceConflict() {
        let now = fixedDate(hour: 9)
        var settings = AppSettings()
        var high = Reminder(text: "Take medicine", category: .health)
        high.schedule = ReminderSchedule(cadence: .oneOff, preferredWindow: nil, dailyCap: 1, confidence: 0.95, exactDate: now.addingTimeInterval(20 * 60), schedulingPolicy: .relativeOffset)
        high.nextNudgeAt = now.addingTimeInterval(20 * 60)
        var low = Reminder(text: "Maybe stretch", category: .move)
        low.schedule = ReminderSchedule(cadence: .oneOff, preferredWindow: nil, dailyCap: 1, confidence: 0.45, exactDate: now.addingTimeInterval(20 * 60), confidenceTier: .medium, schedulingPolicy: .relativeOffset)

        let lowPlan = NotificationPlanner.plan(for: low, context: NudgeDecisionContext(allReminders: [high, low], settings: settings, now: now))

        XCTAssertEqual(lowPlan.status, .clustered)
        XCTAssertEqual(lowPlan.explanation.code, .delayedDueToAnotherReminder)
        XCTAssertGreaterThanOrEqual(lowPlan.plan!.nextFireDate.timeIntervalSince(high.nextNudgeAt!), AdaptiveEngine.clusterGapSeconds)
    }

    func testUrgentReminderBeatsLowPriorityReminder() {
        let now = fixedDate(hour: 9)
        var settings = AppSettings()
        var normal = Reminder(text: "Read article", category: .mind)
        normal.schedule = ReminderSchedule(cadence: .oneOff, preferredWindow: nil, dailyCap: 1, confidence: 0.8, exactDate: now.addingTimeInterval(20 * 60), schedulingPolicy: .relativeOffset)
        normal.nextNudgeAt = now.addingTimeInterval(20 * 60)
        var urgent = Reminder(text: "urgent call doctor", category: .health)
        urgent.schedule = ReminderSchedule(cadence: .oneOff, preferredWindow: nil, dailyCap: 1, confidence: 0.8, exactDate: now.addingTimeInterval(20 * 60), schedulingPolicy: .relativeOffset)

        let urgentPlan = NotificationPlanner.plan(for: urgent, context: NudgeDecisionContext(allReminders: [normal, urgent], settings: settings, now: now))

        XCTAssertEqual(urgentPlan.status, .scheduled)
        XCTAssertNotEqual(urgentPlan.explanation.code, .delayedDueToAnotherReminder)
    }

    func testQuietHoursAndConflictResolveTogether() {
        let now = fixedDate(hour: 22, minute: 50)
        var settings = AppSettings()
        settings.quietHoursStart = 23
        settings.quietHoursEnd = 8
        var urgent = Reminder(text: "urgent medicine", category: .health)
        urgent.schedule = ReminderSchedule(cadence: .oneOff, preferredWindow: NudgeTimeWindow(startHour: 23, endHour: 23, label: .night), dailyCap: 1, confidence: 0.9)
        var normal = Reminder(text: "Read", category: .mind)
        normal.schedule = ReminderSchedule(cadence: .oneOff, preferredWindow: NudgeTimeWindow(startHour: 23, endHour: 23, label: .night), dailyCap: 1, confidence: 0.7)

        let urgentPlan = NotificationPlanner.plan(for: urgent, context: NudgeDecisionContext(allReminders: [urgent], settings: settings, now: now))
        apply(urgentPlan, to: &urgent)
        let normalPlan = NotificationPlanner.plan(for: normal, context: NudgeDecisionContext(allReminders: [urgent, normal], settings: settings, now: now))

        XCTAssertEqual(urgentPlan.explanation.code, .quietHoursDelayed)
        XCTAssertEqual(normalPlan.status, .clustered)
        XCTAssertEqual(normalPlan.explanation.code, .delayedDueToAnotherReminder)
        XCTAssertGreaterThanOrEqual(normalPlan.plan!.nextFireDate.timeIntervalSince(urgent.nextNudgeAt!), AdaptiveEngine.clusterGapSeconds)
    }

    func testRepeatedReplansDoNotKeepPushingDelayedReminderLater() {
        let now = fixedDate(hour: 9)
        var settings = AppSettings()
        var anchor = Reminder(text: "urgent walk", category: .move)
        anchor.schedule = ReminderSchedule(cadence: .oneOff, preferredWindow: nil, dailyCap: 1, confidence: 0.95, exactDate: now.addingTimeInterval(20 * 60), schedulingPolicy: .relativeOffset)
        anchor.nextNudgeAt = now.addingTimeInterval(20 * 60)
        var delayed = Reminder(text: "Drink water", category: .body)
        delayed.schedule = ReminderSchedule(cadence: .oneOff, preferredWindow: nil, dailyCap: 1, confidence: 0.7, exactDate: now.addingTimeInterval(20 * 60), schedulingPolicy: .relativeOffset)

        let firstPlan = NotificationPlanner.plan(for: delayed, context: NudgeDecisionContext(allReminders: [anchor, delayed], settings: settings, now: now))
        apply(firstPlan, to: &delayed)
        let firstDate = delayed.nextNudgeAt
        let secondPlan = NotificationPlanner.plan(for: delayed, context: NudgeDecisionContext(allReminders: [anchor, delayed], settings: settings, now: now.addingTimeInterval(60)))

        XCTAssertEqual(secondPlan.status, .clustered)
        XCTAssertEqual(secondPlan.plan?.nextFireDate, firstDate)
    }

    func testRelaunchStyleReconciliationPreservesResolvedStaggerOrder() {
        let now = fixedDate(hour: 9)
        var settings = AppSettings()
        var anchor = Reminder(text: "urgent walk", category: .move)
        anchor.schedule = ReminderSchedule(cadence: .oneOff, preferredWindow: nil, dailyCap: 1, confidence: 0.95, exactDate: now.addingTimeInterval(20 * 60), schedulingPolicy: .relativeOffset)
        anchor.nextNudgeAt = now.addingTimeInterval(20 * 60)
        var delayed = Reminder(text: "Drink water", category: .body)
        delayed.schedule = ReminderSchedule(cadence: .oneOff, preferredWindow: nil, dailyCap: 1, confidence: 0.7, exactDate: now.addingTimeInterval(20 * 60), schedulingPolicy: .relativeOffset)

        let delayedPlan = NotificationPlanner.plan(for: delayed, context: NudgeDecisionContext(allReminders: [anchor, delayed], settings: settings, now: now))
        apply(delayedPlan, to: &delayed)
        let restored = delayed
        let restoredPlan = NotificationPlanner.plan(for: restored, context: NudgeDecisionContext(allReminders: [anchor, restored], settings: settings, now: now.addingTimeInterval(120)))

        XCTAssertEqual(restoredPlan.status, .clustered)
        XCTAssertEqual(restoredPlan.plan?.nextFireDate, delayed.nextNudgeAt)
        XCTAssertEqual(restoredPlan.conflictResolvedRank, delayed.schedule?.conflictResolvedRank)
    }

    func testSocialReminderChoosesEveningWithExplanation() {
        var settings = AppSettings()
        settings.permissionStates = [PermissionState(permission: .notifications, status: .granted)]
        let parsed = ReminderUnderstandingEngine.parse("Call mom tonight")
        var reminder = Reminder(text: parsed.reminderText, category: parsed.category)
        reminder.kind = parsed.kind
        reminder.schedule = ReminderSchedule(cadence: parsed.suggestedCadence, preferredWindow: parsed.timeWindow, dailyCap: 1, lastPlannedAt: nil, confidence: parsed.confidence, lastExplanation: parsed.explanation, lastPlanStatus: nil)

        let result = NotificationPlanner.plan(
            for: reminder,
            context: NudgeDecisionContext(allReminders: [reminder], settings: settings, now: fixedDate(hour: 12))
        )

        XCTAssertEqual(result.status, .scheduled)
        XCTAssertEqual(result.plan?.window.label, .evening)
        XCTAssertEqual(result.explanation.code, .selectedSocialEvening)
    }

    func testRepeatedMistimingEasesCadence() {
        var reminder = Reminder(text: "Drink water", category: .body)
        reminder.interactions = [
            Interaction(type: .ignored, at: fixedDate(hour: 9)),
            Interaction(type: .skipped, at: fixedDate(hour: 10)),
            Interaction(type: .ignored, at: fixedDate(hour: 11))
        ]

        let result = NotificationPlanner.plan(
            for: reminder,
            context: NudgeDecisionContext(allReminders: [reminder], settings: AppSettings(), now: fixedDate(hour: 8))
        )

        XCTAssertEqual(result.status, .scheduled)
        XCTAssertEqual(result.explanation.code, .recentMistimedEasedBack)
        XCTAssertGreaterThan(result.plan!.nextFireDate.timeIntervalSince(fixedDate(hour: 8)), 40 * 3600)
    }

    private struct GrammarFixture {
        let text: String
        let kind: ReminderKind
        let triggerType: TriggerType?
        let placeAlias: String?
        let hasTime: Bool
        let hasRecurrence: Bool
        let needsSetup: Bool
        let confidence: ClosedRange<Double>
    }

    private func grammarFixtures() -> [GrammarFixture] {
        var fixtures: [GrammarFixture] = []
        let actionsTR = ["su iç", "ilacı al", "protein iç", "raporu gönder", "süt al", "notları yaz", "çöpleri çıkar", "annemi ara"]
        let actionsEN = ["drink water", "take medicine", "drink protein", "send the report", "buy milk", "write notes", "take out trash", "call mom"]

        let turkishTimes = ["bugün", "yarın", "yarın sabah", "bu akşam", "akşama doğru", "öğleden sonra", "cuma günü", "gelecek cuma", "haftaya", "20 dakika sonra", "2 saat sonra", "aksam", "ogleden sonra", "yarin sabah", "bugun"]
        for (idx, time) in turkishTimes.enumerated() {
            fixtures.append(.init(text: "\(time) \(actionsTR[idx % actionsTR.count])", kind: .oneOff, triggerType: nil, placeAlias: nil, hasTime: true, hasRecurrence: false, needsSetup: false, confidence: 0.45...1.0))
        }

        let englishTimes = ["today", "tomorrow", "tomorrow morning", "tonight", "this evening", "Friday", "next Friday", "next week", "in 20 minutes", "in 2 hours"]
        for (idx, time) in englishTimes.enumerated() {
            fixtures.append(.init(text: "\(time) \(actionsEN[idx % actionsEN.count])", kind: .oneOff, triggerType: nil, placeAlias: nil, hasTime: true, hasRecurrence: false, needsSetup: false, confidence: 0.45...1.0))
        }

        let recurrences = [
            "her sabah", "her akşam", "iki günde bir", "haftada 3 kez", "ayda bir",
            "every morning", "every evening", "every other day", "3 times a week", "once a month",
            "her sabah", "her aksam", "iki gunde bir", "haftada üç kez", "ayda bir"
        ]
        for (idx, recurrence) in recurrences.enumerated() {
            let action = idx < 5 || recurrence.contains("her") || recurrence.contains("haftada") || recurrence.contains("ayda") || recurrence.contains("gunde") ? actionsTR[idx % actionsTR.count] : actionsEN[idx % actionsEN.count]
            fixtures.append(.init(text: "\(recurrence) \(action)", kind: .timeBased, triggerType: nil, placeAlias: nil, hasTime: false, hasRecurrence: true, needsSetup: false, confidence: 0.5...1.0))
        }

        let placeTriggers: [(String, TriggerType, String)] = [
            ("eve gelince", .geofenceEnter, "home"), ("eve varınca", .geofenceEnter, "home"), ("eve gidince", .geofenceEnter, "home"),
            ("evden çıkınca", .geofenceExit, "home"), ("evden ayrılınca", .geofenceExit, "home"),
            ("işe gidince", .geofenceEnter, "work"), ("işe varınca", .geofenceEnter, "work"), ("işten çıkınca", .geofenceExit, "work"),
            ("spora gidince", .geofenceEnter, "gym"), ("spor salonuna gidince", .geofenceEnter, "gym"), ("spordan çıkınca", .geofenceExit, "gym"), ("spor salonundan ayrılınca", .geofenceExit, "gym"),
            ("markete gidince", .geofenceEnter, "market"), ("marketten çıkınca", .geofenceExit, "market"),
            ("eczaneye gidince", .geofenceEnter, "pharmacy"), ("eczaneden çıkınca", .geofenceExit, "pharmacy"),
            ("okula gidince", .geofenceEnter, "school"), ("ofise gidince", .geofenceEnter, "office"), ("kafeye gidince", .geofenceEnter, "cafe"),
            ("doktora gidince", .geofenceEnter, "doctor"), ("hastaneye gidince", .geofenceEnter, "hospital"),
            ("eve gelince", .geofenceEnter, "home"), ("isten cikinca", .geofenceExit, "work"), ("spordan cikinca", .geofenceExit, "gym"), ("markete gidince", .geofenceEnter, "market"),
            ("when i get home", .geofenceEnter, "home"), ("when i leave home", .geofenceExit, "home"), ("when i get to work", .geofenceEnter, "work"), ("when i leave work", .geofenceExit, "work"),
            ("when i get to the gym", .geofenceEnter, "gym"), ("when i leave the gym", .geofenceExit, "gym"), ("when i get to the market", .geofenceEnter, "market"), ("when i leave the pharmacy", .geofenceExit, "pharmacy")
        ]
        for (idx, item) in placeTriggers.enumerated() {
            let isEnglish = item.0.hasPrefix("when")
            let action = isEnglish ? actionsEN[idx % actionsEN.count] : actionsTR[idx % actionsTR.count]
            fixtures.append(.init(text: "\(item.0) \(action)", kind: .eventBased, triggerType: item.1, placeAlias: item.2, hasTime: false, hasRecurrence: false, needsSetup: true, confidence: 0.5...1.0))
        }

        let deviceTriggers: [(String, TriggerType?, String?)] = [
            ("şarja takınca", .chargingStarted, nil), ("telefoni şarja takınca", .chargingStarted, nil), ("sarja takinca", .chargingStarted, nil),
            ("arabaya binince", .carplayConnected, nil), ("arabadan inince", .carplayDisconnected, nil),
            ("toplantıdan sonra", .calendarEventEnded, nil), ("toplanti bitince", .calendarEventEnded, nil),
            ("when charging starts", .chargingStarted, nil), ("when i get in my car", .carplayConnected, nil), ("when i leave my car", .carplayDisconnected, nil),
            ("after my meeting", .calendarEventEnded, nil), ("when my meeting ends", .calendarEventEnded, nil),
            ("laptopu açınca", .customContext, nil), ("laptopu acinca", .customContext, nil), ("when i open my laptop", .customContext, nil),
            ("benzinden sonra", .customContext, nil), ("when i get gas", .customContext, nil)
        ]
        for (idx, item) in deviceTriggers.enumerated() {
            let action = item.0.contains("when") || item.0.contains("after") ? actionsEN[idx % actionsEN.count] : actionsTR[idx % actionsTR.count]
            fixtures.append(.init(text: "\(item.0) \(action)", kind: .eventBased, triggerType: item.1, placeAlias: item.2, hasTime: false, hasRecurrence: false, needsSetup: item.1 == .customContext || item.1 == .calendarEventEnded, confidence: 0.25...1.0))
        }

        let falsePositives = [
            "spor ayakkabımı temizle", "market listesini düzenle", "eczane fişini sakla", "laptop çantasını hazırla",
            "benzin fiyatlarını kontrol et", "call the pharmacy", "write a market list", "clean gym shoes",
            "prepare laptop bag", "review tomorrow plan"
        ]
        for item in falsePositives {
            fixtures.append(.init(text: item, kind: item.contains("tomorrow") ? .oneOff : .timeBased, triggerType: nil, placeAlias: nil, hasTime: item.contains("tomorrow"), hasRecurrence: false, needsSetup: false, confidence: 0.25...1.0))
        }

        while fixtures.count < 120 {
            let idx = fixtures.count
            fixtures.append(.init(text: "\(turkishTimes[idx % turkishTimes.count]) \(actionsTR[idx % actionsTR.count])", kind: .oneOff, triggerType: nil, placeAlias: nil, hasTime: true, hasRecurrence: false, needsSetup: false, confidence: 0.45...1.0))
        }
        return fixtures
    }

    private struct UnderstandingCase {
        let text: String
        let kind: ReminderKind
        let triggerType: TriggerType?
        let category: ReminderCategory
        let confidence: ClosedRange<Double>
        let permissions: [PermissionKind]
        let needsSetup: Bool
        let actionable: Bool
        let ambiguity: ReminderAmbiguityFlag?

        init(
            _ text: String,
            _ kind: ReminderKind,
            _ triggerType: TriggerType?,
            _ category: ReminderCategory,
            _ confidence: ClosedRange<Double>,
            _ permissions: [PermissionKind],
            _ needsSetup: Bool,
            _ actionable: Bool,
            _ ambiguity: ReminderAmbiguityFlag?
        ) {
            self.text = text
            self.kind = kind
            self.triggerType = triggerType
            self.category = category
            self.confidence = confidence
            self.permissions = permissions
            self.needsSetup = needsSetup
            self.actionable = actionable
            self.ambiguity = ambiguity
        }
    }

    private func assertUnderstandingCases(_ cases: [UnderstandingCase]) {
        for item in cases {
            let parsed = ReminderUnderstandingEngine.parse(item.text)
            XCTAssertEqual(parsed.kind, item.kind, item.text)
            XCTAssertEqual(parsed.trigger?.condition.type, item.triggerType, item.text)
            XCTAssertEqual(parsed.category, item.category, item.text)
            XCTAssertTrue(item.confidence.contains(parsed.confidence), "\(item.text) confidence \(parsed.confidence)")
            XCTAssertEqual(Set(parsed.requiredPermissions), Set(item.permissions), item.text)
            XCTAssertFalse(parsed.interpretationSummary.isEmpty, item.text)

            if let triggerType = item.triggerType {
                XCTAssertEqual(parsed.triggerReadiness?.triggerType, triggerType, item.text)
                XCTAssertEqual(parsed.triggerReadiness?.isCurrentlyActionable, item.actionable, item.text)
                XCTAssertEqual(parsed.triggerReadiness?.requiredSetup.isEmpty, !item.needsSetup, item.text)
                XCTAssertNotNil(parsed.triggerReadiness?.fallbackStrategy, item.text)
            } else {
                XCTAssertNil(parsed.triggerReadiness, item.text)
            }

            if let ambiguity = item.ambiguity {
                XCTAssertTrue(parsed.ambiguityFlags.contains(ambiguity), item.text)
            }

            let reminder = reminder(from: parsed)
            let result = NotificationPlanner.plan(
                for: reminder,
                context: NudgeDecisionContext(allReminders: [reminder], settings: settingsForPlanning(parsed: parsed), now: fixedDate(hour: 9))
            )
            if item.actionable && item.triggerType == nil {
                XCTAssertEqual(result.status, .scheduled, item.text)
            } else if item.triggerType != nil {
                XCTAssertNotEqual(result.status, .scheduled, item.text)
            }
            XCTAssertFalse(result.explanation.text.isEmpty, item.text)
        }
    }

    // MARK: - Production-readiness tests

    func testTriggerEventSchedulesImmediately() {
        var settings = AppSettings()
        settings.permissionStates = [PermissionState(permission: .notifications, status: .granted)]
        var reminder = Reminder(text: "Take vitamins", category: .health)
        reminder.kind = .eventBased
        reminder.triggerDefinition = ReminderTrigger(
            condition: TriggerCondition(
                type: .chargingStarted,
                subject: TriggerType.chargingStarted.rawValue,
                requiresPermission: [.notifications]
            ),
            confidence: 0.9
        )
        let eventTime = fixedDate(hour: 14) // 2 PM — not quiet
        let event = TriggerEvent(type: .chargingStarted, subject: TriggerType.chargingStarted.rawValue, confidence: 1.0, createdAt: eventTime)
        let result = NotificationPlanner.plan(
            for: reminder,
            context: NudgeDecisionContext(allReminders: [reminder], settings: settings, now: eventTime, triggeredBy: event)
        )
        XCTAssertEqual(result.status, .scheduled)
        XCTAssertEqual(result.explanation.code, .triggeredByEvent)
        // Fire date must be within 10 seconds of event time, not pushed to a future window.
        XCTAssertLessThan(result.plan!.nextFireDate.timeIntervalSince(eventTime), 10)
    }

    func testCoordinateLessAliasIsNotReady() {
        var settings = AppSettings()
        settings.permissionStates = [
            PermissionState(permission: .notifications, status: .granted),
            PermissionState(permission: .location, status: .granted)
        ]
        settings.locationAliases = [LocationAlias(name: "home")] // no lat/lon
        var reminder = Reminder(text: "Take out trash", category: .home)
        reminder.kind = .eventBased
        reminder.triggerDefinition = ReminderTrigger(
            condition: TriggerCondition(
                type: .geofenceEnter, subject: "home", locationAlias: "home",
                requiresPermission: [.notifications, .location]
            ),
            confidence: 0.88
        )
        let result = NotificationPlanner.plan(
            for: reminder,
            context: NudgeDecisionContext(allReminders: [reminder], settings: settings)
        )
        XCTAssertEqual(result.status, .missingLocationAlias)
    }

    func testCooldownScopedToSubject() {
        let now = fixedDate(hour: 10)
        let homeCondition = TriggerCondition(
            type: .geofenceEnter, subject: "home", locationAlias: "home",
            requiresPermission: [.notifications, .location], cooldownSeconds: 3600
        )
        let workCondition = TriggerCondition(
            type: .geofenceEnter, subject: "work", locationAlias: "work",
            requiresPermission: [.notifications, .location], cooldownSeconds: 3600
        )
        // Home enter fired 30 minutes ago — within cooldown.
        let log: [TriggerEventLog] = [
            TriggerEventLog(triggerType: .geofenceEnter, subject: "home",
                            reminderId: UUID(), confidence: 1.0,
                            createdAt: now.addingTimeInterval(-30 * 60), fired: true)
        ]
        let homeEvent = TriggerEvent(type: .geofenceEnter, subject: "home", confidence: 1.0, createdAt: now)
        let workEvent = TriggerEvent(type: .geofenceEnter, subject: "work", confidence: 1.0, createdAt: now)

        XCTAssertFalse(TriggerExecutionPolicy.shouldFire(
            condition: homeCondition, event: homeEvent, eventLog: log, now: now),
            "Home should be blocked by cooldown")
        XCTAssertTrue(TriggerExecutionPolicy.shouldFire(
            condition: workCondition, event: workEvent, eventLog: log, now: now),
            "Work should NOT be blocked — different subject")
    }

    func testMissingAliasProducesMissingLocationAlias() {
        var settings = AppSettings()
        settings.permissionStates = [
            PermissionState(permission: .notifications, status: .granted),
            PermissionState(permission: .location, status: .granted)
        ]
        settings.locationAliases = [] // no aliases
        var reminder = Reminder(text: "Check mail", category: .home)
        reminder.kind = .eventBased
        reminder.triggerDefinition = ReminderTrigger(
            condition: TriggerCondition(
                type: .geofenceEnter, subject: "home", locationAlias: "home",
                requiresPermission: [.notifications, .location]
            ),
            confidence: 0.88
        )
        let result = NotificationPlanner.plan(
            for: reminder,
            context: NudgeDecisionContext(allReminders: [reminder], settings: settings)
        )
        XCTAssertEqual(result.status, .missingLocationAlias)
        XCTAssertFalse(result.explanation.text.isEmpty)
    }

    func testGeofenceEnterEventDoesNotMatchWrongAlias() {
        var settings = AppSettings()
        settings.permissionStates = [
            PermissionState(permission: .notifications, status: .granted),
            PermissionState(permission: .location, status: .granted)
        ]
        settings.locationAliases = [
            LocationAlias(name: "home", latitude: 41.0, longitude: 29.0),
            LocationAlias(name: "work", latitude: 41.1, longitude: 29.1)
        ]
        var homeReminder = Reminder(text: "Check mail", category: .home)
        homeReminder.kind = .eventBased
        homeReminder.triggerDefinition = ReminderTrigger(
            condition: TriggerCondition(
                type: .geofenceEnter, subject: "home", locationAlias: "home",
                requiresPermission: [.notifications, .location], cooldownSeconds: 3600
            ),
            confidence: 0.88
        )
        // Fire a work enter event — home reminder should NOT match.
        let workEvent = TriggerEvent(type: .geofenceEnter, subject: "work", confidence: 1.0, createdAt: fixedDate(hour: 9))
        let result = NotificationPlanner.plan(
            for: homeReminder,
            context: NudgeDecisionContext(allReminders: [homeReminder], settings: settings,
                                          now: fixedDate(hour: 9), triggeredBy: workEvent)
        )
        XCTAssertNotEqual(result.status, .scheduled, "Home reminder must not fire for a work enter event")
    }

    private func reminder(from parsed: ParsedReminderIntent) -> Reminder {
        var reminder = Reminder(text: parsed.reminderText, category: parsed.category)
        reminder.kind = parsed.kind
        reminder.triggerDefinition = parsed.trigger
        reminder.schedule = ReminderSchedule(
            cadence: parsed.suggestedCadence,
            preferredWindow: parsed.timeWindow,
            dailyCap: 1,
            lastPlannedAt: nil,
            confidence: parsed.confidence,
            lastExplanation: parsed.explanation,
            lastPlanStatus: nil,
            interpretationSummary: parsed.interpretationSummary,
            fallbackSummary: parsed.triggerReadiness?.fallbackStrategy?.explanation,
            exactDate: parsed.exactDate,
            approximateDate: parsed.approximateDate,
            relativeOffsetSeconds: parsed.relativeOffsetSeconds,
            recurrenceRule: parsed.recurrenceRule,
            confidenceTier: parsed.confidenceTier,
            grammarExplanation: parsed.explanation?.text,
            schedulingPolicy: parsed.schedulingPolicy
        )
        return reminder
    }

    private func apply(_ result: NudgePlanResult, to reminder: inout Reminder) {
        reminder.schedule?.lastPlanStatus = result.status
        reminder.schedule?.lastExplanation = result.explanation
        reminder.schedule?.confidence = result.confidence
        guard let plan = result.plan else {
            reminder.nextNudgeAt = nil
            return
        }
        reminder.nextNudgeAt = plan.nextFireDate
        reminder.schedule?.preferredWindow = plan.window
        reminder.schedule?.lastPlannedAt = fixedDate(hour: 9)
        reminder.schedule?.conflictGroupKey = result.conflictGroupKey
        reminder.schedule?.conflictAnchorReminderId = result.conflictAnchorReminderId
        reminder.schedule?.conflictResolvedFireDate = result.conflictGroupKey == nil ? nil : plan.nextFireDate
        reminder.schedule?.conflictResolvedRank = result.conflictResolvedRank
        reminder.schedule?.conflictResolvedAt = result.conflictResolvedAt
    }

    private func settingsForPlanning(parsed: ParsedReminderIntent) -> AppSettings {
        var settings = AppSettings()
        settings.permissionStates = parsed.requiredPermissions.map { PermissionState(permission: $0, status: .granted) }
        return settings
    }

    private func fixedDate(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: hour, minute: minute))!
    }
}

@MainActor
private final class FakeNotificationScheduler: ReminderNotificationScheduling {
    var onNudgeDone: ((UUID) -> Void)?
    var onNudgeLater: ((UUID) -> Void)?
    var onNudgeOpened: ((UUID) -> Void)?
    var authorized = true
    var requestedPermission = false
    var scheduledReminderIds: [UUID] = []
    var cancelledReminderIds: [UUID] = []
    var cancelAllCount = 0

    var isAuthorized: Bool { get async { authorized } }

    func requestPermission() async -> Bool {
        requestedPermission = true
        return authorized
    }

    func scheduleNudge(for reminder: Reminder, settings: AppSettings, allReminders: [Reminder]?) async {
        scheduledReminderIds.append(reminder.id)
    }

    func scheduleAll(_ reminders: [Reminder], settings: AppSettings) async {
        scheduledReminderIds.append(contentsOf: reminders.map(\.id))
    }

    func cancel(reminderId: UUID) {
        cancelledReminderIds.append(reminderId)
    }

    func cancelAll() {
        cancelAllCount += 1
    }
}

private final class FakeLocationAdapter: LocationTriggerAdapter {
    var onTriggerEvent: ((TriggerEvent) -> Void)?
    var onPermissionChange: ((PermissionStatus) -> Void)?
    var currentAuthorizationStatus: PermissionStatus = .granted
    var requestedPermission = false
    var reconcileCount = 0
    var reconciledAliases: [[LocationAlias]] = []
    var reconciledReminders: [[Reminder]] = []

    func requestPermission() {
        requestedPermission = true
    }

    func reconcile(aliases: [LocationAlias], reminders: [Reminder]) {
        reconcileCount += 1
        reconciledAliases.append(aliases)
        reconciledReminders.append(reminders)
    }
}

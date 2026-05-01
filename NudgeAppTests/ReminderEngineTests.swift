import XCTest
@testable import NudgeApp

final class ReminderEngineTests: XCTestCase {
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
        var existing = Reminder(text: "Walk", category: .move)
        let second = Reminder(text: "Drink water", category: .body)
        let unclustered = NotificationPlanner.plan(for: second, context: NudgeDecisionContext(allReminders: [second], settings: settings, now: now)).plan!
        existing.nextNudgeAt = unclustered.nextFireDate

        let secondPlan = NotificationPlanner.plan(
            for: second,
            context: NudgeDecisionContext(allReminders: [existing, second], settings: settings, now: now)
        )

        XCTAssertEqual(secondPlan.status, .scheduled)
        XCTAssertEqual(secondPlan.explanation.code, .notificationClusterPrevented)
        XCTAssertGreaterThanOrEqual(abs(secondPlan.plan!.nextFireDate.timeIntervalSince(existing.nextNudgeAt!)), AdaptiveEngine.clusterGapSeconds)
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

    private func reminder(from parsed: ParsedReminderIntent) -> Reminder {
        var reminder = Reminder(text: parsed.reminderText, category: parsed.category)
        reminder.kind = parsed.kind
        reminder.triggerDefinition = parsed.trigger
        reminder.schedule = ReminderSchedule(cadence: parsed.suggestedCadence, preferredWindow: parsed.timeWindow, dailyCap: 1, lastPlannedAt: nil, confidence: parsed.confidence, lastExplanation: parsed.explanation, lastPlanStatus: nil, interpretationSummary: parsed.interpretationSummary, fallbackSummary: parsed.triggerReadiness?.fallbackStrategy?.explanation)
        return reminder
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

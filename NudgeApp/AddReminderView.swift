import SwiftUI

struct AddReminderView: View {
    let editingReminder: Reminder?

    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var textFocused: Bool

    @State private var text         = ""
    @State private var frequency    = FrequencyPreference.smart
    @State private var isRepeating  = false
    @State private var dueDate: Date?
    @State private var showCalendar = false
    @State private var analysisTask: Task<Void, Never>?
    @State private var userPickedFrequency = false
    @State private var parsedIntent: ParsedReminderIntent?

    // Reminder kind + payloads
    @State private var kind: ReminderType = .standard
    @State private var trigger: TriggerInfo?
    @State private var voice: VoiceInfo?
    @State private var link: LinkInfo?

    // Live text analysis — updates as the user types
    @State private var analysis     = TextAnalysis(
        category: .none, suggestedFrequency: .smart,
        suggestedTimePreference: .flexible, isHabit: false, confidence: 0
    )

    private var catColor: Color { Color.categoryColor(analysis.category) }
    private var hasCat: Bool    { analysis.category != .none }
    private var isEditing: Bool { editingReminder != nil }
    private var reminderHistory: [Reminder] {
        guard let editingID = editingReminder?.id else { return state.reminders }
        return state.reminders.filter { $0.id != editingID }
    }
    private var inputValidation: ReminderInputValidator.Result {
        ReminderInputValidator.validate(text, allowsEmpty: kind == .voice)
    }
    private var hasText: Bool   { ReminderInputValidator.validate(text).isValid }

    // Saveability rules differ by kind. Voice doesn't need text; trigger needs both.
    private var ready: Bool {
        switch kind {
        case .standard: return hasText
        case .trigger:  return hasText && trigger != nil
        case .voice:    return voice != nil
        case .linked:   return hasText && link?.parentId != nil
        case .oneoff:   return hasText
        }
    }

    private var showFreqAndDate: Bool { kind == .standard }

    init(editingReminder: Reminder? = nil) {
        self.editingReminder = editingReminder
        let initialText = editingReminder?.text ?? ""
        let initialAnalysis = initialText.isEmpty
            ? TextAnalysis(category: .none, suggestedFrequency: .smart, suggestedTimePreference: .flexible, isHabit: false, confidence: 0)
            : TextAnalyzer.analyze(initialText)
        _text = State(initialValue: initialText)
        _frequency = State(initialValue: editingReminder?.frequency ?? initialAnalysis.suggestedFrequency)
        _isRepeating = State(initialValue: editingReminder?.isRepeating ?? false)
        _dueDate = State(initialValue: editingReminder?.dueDate)
        _analysis = State(initialValue: initialAnalysis)
        _kind = State(initialValue: editingReminder?.type ?? .standard)
        _trigger = State(initialValue: editingReminder?.trigger ?? editingReminder?.triggerDefinition.map(Self.triggerInfo))
        _voice = State(initialValue: editingReminder?.voice)
        _link = State(initialValue: editingReminder?.link)
        _parsedIntent = State(initialValue: nil)
        _userPickedFrequency = State(initialValue: editingReminder != nil)
    }

    private var placeholder: String {
        switch kind {
        case .standard: return "What would you like to be reminded of?"
        case .trigger:  return "What should this remind you of?"
        case .voice:    return "A short label (optional)"
        case .linked:   return "And then…"
        case .oneoff:   return "Just for today, remind me to…"
        }
    }

    private var parents: [(UUID, String)] {
        state.reminders
            .filter { !$0.isDone && $0.type != .voice }
            .prefix(4)
            .map { ($0.id, $0.text) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.jgrSurface.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Handle bar
                        HStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: 999)
                                .fill(Color.jgrT4.opacity(0.5))
                                .frame(width: 36, height: 4)
                            Spacer()
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 28)

                        // Text input with live category underline + dot
                        VStack(spacing: 0) {
                            HStack(alignment: .center) {
                                TextField(placeholder, text: $text, axis: .vertical)
                                    .font(JGRFont.regular(17))
                                    .foregroundStyle(Color.jgrT1)
                                    .tracking(-0.2)
                                    .lineLimit(1...4)
                                    .focused($textFocused)
                                    .onChange(of: text) { _, newValue in
                                        handleTextChange(newValue)
                                    }

                                // Inferred-category dot
                                Circle()
                                    .fill(catColor)
                                    .frame(width: 8, height: 8)
                                    .opacity(hasCat ? 1 : 0)
                                    .scaleEffect(hasCat ? 1 : 0.4)
                                    .animation(.spring(response: 0.35), value: analysis.category)
                            }

                            // Category-tinted underline
                            Rectangle()
                                .fill(hasCat ? catColor : Color.jgrT4)
                                .frame(height: 0.75)
                                .animation(.easeInOut(duration: 0.3), value: analysis.category)
                        }
                        .padding(.horizontal, 32)

                        // Inference preview — shows what the app inferred
                        if hasCat {
                            HStack(spacing: 6) {
                                Text(analysis.category.displayName)
                                    .font(JGRFont.regular(12))
                                    .foregroundStyle(catColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(catColor.opacity(0.12))
                                    .clipShape(Capsule())

                                if analysis.isHabit {
                                    Text("habit")
                                        .font(JGRFont.regular(12))
                                        .foregroundStyle(Color.jgrT3)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .overlay(Capsule().stroke(Color.jgrT4, lineWidth: 0.75))
                                }
                            }
                            .padding(.horizontal, 32)
                            .padding(.top, 10)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        if let editingReminder {
                            Spacer().frame(height: 18)
                            EditStatusView(
                                status: ReminderRowStatus(reminder: editingReminder, settings: state.settings),
                                onOpenSettings: {
                                    dismiss()
                                    state.screen = .settings
                                }
                            )
                            .padding(.horizontal, 32)
                        }

                        Spacer().frame(height: 28)

                        // ── Kind ─────────────────────────────────────────────
                        Eyebrow(text: "Kind").padding(.horizontal, 32)
                        Spacer().frame(height: 18)
                        ReminderKindSelector(value: $kind)
                            .padding(.horizontal, 32)

                        // Kind-specific accessory
                        Group {
                            switch kind {
                            case .standard:
                                EmptyView()
                            case .trigger:
                                Spacer().frame(height: 28)
                                TriggerPicker(value: $trigger)
                                    .padding(.horizontal, 32)
                            case .voice:
                                Spacer().frame(height: 22)
                                VoiceRecorderView(value: $voice)
                                    .padding(.horizontal, 32)
                            case .linked:
                                Spacer().frame(height: 28)
                                LinkedPicker(parents: parents, value: $link)
                                    .padding(.horizontal, 32)
                            case .oneoff:
                                Spacer().frame(height: 22)
                                OneoffNote().padding(.horizontal, 32)
                            }
                        }

                        if showFreqAndDate {
                            Spacer().frame(height: 28)

                            // ── How often ────────────────────────────────────
                            Eyebrow(text: "How often").padding(.horizontal, 32)
                            Spacer().frame(height: 18)

                            VStack(alignment: .leading, spacing: 18) {
                                ForEach(FrequencyPreference.allCases, id: \.self) { opt in
                                    Button {
                                        userPickedFrequency = true
                                        withAnimation(.easeInOut(duration: 0.25)) { frequency = opt }
                                    } label: {
                                        HStack(spacing: 0) {
                                            Text(opt.label)
                                                .font(frequency == opt ? JGRFont.medium(16) : JGRFont.regular(16))
                                                .foregroundStyle(frequency == opt ? Color.jgrT1 : Color.jgrT3)
                                                .tracking(-0.2)
                                            if let hint = opt.hint {
                                                Text(" · \(hint)")
                                                    .font(JGRFont.regular(16))
                                                    .foregroundStyle(frequency == opt ? Color.jgrT3 : Color.jgrT4)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 32)

                            Spacer().frame(height: 28)

                            // ── Every day toggle ─────────────────────────────
                            HStack {
                                Text("Every day")
                                    .font(JGRFont.regular(15))
                                    .foregroundStyle(Color.jgrT1)
                                    .tracking(-0.1)
                                Spacer()
                                JGRToggle(isOn: $isRepeating)
                            }
                            .padding(.horizontal, 32)

                            Spacer().frame(height: 24)

                            // ── Due date picker ──────────────────────────────
                            DueDatePickerView(selected: $dueDate, showCalendar: $showCalendar)
                                .padding(.horizontal, 32)
                        }

                        // Bottom padding for button
                        Spacer().frame(height: 120)
                    }
                }

                // ── Cancel / Save bar ─────────────────────────────────────────
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(JGRFont.regular(15))
                        .foregroundStyle(Color.jgrT3)
                        .tracking(-0.1)
                        .accessibilityLabel("Cancel")

                    if let editingReminder {
                        Button("Remove") {
                            state.removeReminder(editingReminder.id)
                            dismiss()
                        }
                        .font(JGRFont.regular(15))
                        .foregroundStyle(Color.jgrT3)
                        .tracking(-0.1)
                        .padding(.leading, 18)
                        .accessibilityLabel("Remove reminder")
                    }

                    Spacer()

                    Button("Save") { save() }
                        .font(ready ? JGRFont.medium(15) : JGRFont.regular(15))
                        .foregroundStyle(ready ? Color.jgrT1 : Color.jgrT4)
                        .tracking(-0.1)
                        .disabled(!ready)
                        .animation(.easeInOut(duration: 0.25), value: ready)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
                .background(
                    Color.jgrSurface
                        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: -4)
                )
            }
        }
        .onAppear { textFocused = true }
        .onDisappear { analysisTask?.cancel() }
    }

    private func save() {
        guard ready else { return }
        let validated = ReminderInputValidator.validate(text, allowsEmpty: kind == .voice)
        let trimmed = validated.sanitizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        // For voice with no label, use a soft fallback so it's identifiable in the list.
        let finalText = trimmed.isEmpty ? "Voice note" : trimmed
        var parsedIntent = self.parsedIntent ?? ReminderUnderstandingEngine.parse(finalText, history: reminderHistory)
        if kind == .trigger, parsedIntent.trigger == nil, let existingTrigger = editingReminder?.triggerDefinition {
            parsedIntent.kind = .eventBased
            parsedIntent.trigger = existingTrigger
            parsedIntent.timeWindow = nil
            parsedIntent.explanation = NudgeExplanation(code: .waitingForTrigger, text: "Waiting for \(existingTrigger.condition.type.rawValue).")
        }
        let storedText = parsedIntent.reminderText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? finalText
            : parsedIntent.reminderText
        let finalAnalysis = TextAnalysis(
            category: parsedIntent.category,
            suggestedFrequency: frequency,
            suggestedTimePreference: parsedIntent.timeWindow?.label.timePreference ?? TextAnalyzer.analyze(finalText).suggestedTimePreference,
            isHabit: parsedIntent.suggestedCadence == .daily || parsedIntent.suggestedCadence == .smartGentle,
            confidence: parsedIntent.confidence
        )

        // For non-standard kinds, frequency/date are not user-driven —
        // pin them to sensible defaults so the model and engine stay coherent.
        let resolvedFrequency: FrequencyPreference = kind == .standard ? frequency : .smart
        let resolvedRepeating: Bool                = kind == .standard ? isRepeating : false
        let resolvedDate: Date?                    = kind == .standard ? dueDate : nil

        if let editingReminder {
            state.editReminder(
                id: editingReminder.id,
                text: storedText,
                analysis: finalAnalysis,
                frequency: resolvedFrequency,
                isRepeating: resolvedRepeating,
                dueDate: resolvedDate,
                type: kind,
                parsedIntent: parsedIntent,
                trigger: trigger,
                voice: voice,
                link: link
            )
        } else {
            state.addReminder(
                text: storedText,
                analysis: finalAnalysis,
                frequency: resolvedFrequency,
                isRepeating: resolvedRepeating,
                dueDate: resolvedDate,
                type: kind,
                parsedIntent: parsedIntent,
                trigger: trigger,
                voice: voice,
                link: link
            )
        }
        dismiss()
    }

    private func handleTextChange(_ newValue: String) {
        let sanitized = ReminderInputValidator.sanitize(newValue)
        if sanitized != newValue {
            text = sanitized
            return
        }

        analysisTask?.cancel()
        analysisTask = Task {
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }

            let result = TextAnalyzer.analyze(sanitized)
            let parsed = ReminderUnderstandingEngine.parse(sanitized, history: reminderHistory)
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.2)) {
                analysis = result
                parsedIntent = parsed
            }

            if !userPickedFrequency && frequency == .smart {
                frequency = result.suggestedFrequency
            }
            if result.isHabit && !isRepeating && kind == .standard {
                isRepeating = true
            }
            if parsed.kind == .eventBased && kind == .standard, let parsedTrigger = parsed.trigger {
                kind = .trigger
                trigger = TriggerInfo(
                    kind: parsedTrigger.condition.type.isGeofence ? .place : .moment,
                    id: parsedTrigger.condition.subject,
                    label: parsedTrigger.condition.subject ?? parsedTrigger.condition.type.rawValue
                )
            }
        }
    }

    private static func triggerInfo(from definition: ReminderTrigger) -> TriggerInfo {
        let condition = definition.condition
        if let alias = condition.locationAlias {
            return TriggerInfo(kind: .place, id: alias, label: "When I get to \(alias)")
        }
        return TriggerInfo(kind: .moment, id: condition.subject, label: condition.subject ?? condition.type.rawValue)
    }
}

private extension TriggerType {
    var isGeofence: Bool {
        self == .geofenceEnter || self == .geofenceExit
    }
}

private extension TimeWindowLabel {
    var timePreference: TimePreference {
        switch self {
        case .earlyMorning, .morning, .lateMorning: return .morning
        case .evening, .night: return .evening
        case .afternoon: return .flexible
        }
    }
}

// MARK: - Edit Status

private struct EditStatusView: View {
    let status: ReminderRowStatus
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(status.label)
                .font(JGRFont.regular(13))
                .foregroundStyle(Color.jgrT3)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if status.isActionable {
                Button("Open settings") { onOpenSettings() }
                    .font(JGRFont.regular(13))
                    .foregroundStyle(Color.jgrT2)
                    .frame(minHeight: 36, alignment: .leading)
                    .accessibilityLabel("Open settings")
            }
        }
    }
}

// MARK: - Due Date Picker

struct DueDatePickerView: View {
    @Binding var selected: Date?
    @Binding var showCalendar: Bool

    private var today: Date    { Calendar.current.startOfDay(for: .now) }
    private var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: today)! }
    private var weekend: Date  {
        let dow = Calendar.current.component(.weekday, from: today)
        let daysUntilSat = ((7 - dow) + 7) % 7
        let offset = daysUntilSat == 0 ? 7 : daysUntilSat
        return Calendar.current.date(byAdding: .day, value: offset, to: today)!
    }

    struct Chip: Identifiable {
        let id: String; let label: String; let date: Date
    }

    private var chips: [Chip] {
        [Chip(id: "today", label: "Today", date: today),
         Chip(id: "tmrw",  label: "Tomorrow", date: tomorrow),
         Chip(id: "wknd",  label: "Weekend", date: weekend)]
    }

    private func same(_ a: Date?, _ b: Date) -> Bool {
        guard let a else { return false }
        return Calendar.current.isDate(a, inSameDayAs: b)
    }

    private var isCustom: Bool {
        guard let sel = selected else { return false }
        return !chips.contains { same(sel, $0.date) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("On a date")
                    .font(JGRFont.regular(15))
                    .foregroundStyle(Color.jgrT1)
                    .tracking(-0.1)
                Spacer()
                if selected != nil {
                    Button("Clear") { selected = nil; showCalendar = false }
                        .font(JGRFont.regular(12))
                        .foregroundStyle(Color.jgrT3)
                        .tracking(0.1)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips) { chip in
                        let active = same(selected, chip.date)
                        Button(chip.label) {
                            selected = active ? nil : chip.date
                            showCalendar = false
                        }
                        .font(JGRFont.regular(13.5))
                        .foregroundStyle(active ? Color.jgrT1 : Color.jgrT2)
                        .tracking(-0.1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(active ? Color.jgrSand : .clear)
                        .overlay(
                            Capsule().stroke(active ? Color.jgrT2 : Color.jgrT4, lineWidth: 0.75)
                        )
                        .clipShape(Capsule())
                        .animation(.easeInOut(duration: 0.25), value: active)
                    }

                    // "Pick a day" chip
                    Button(isCustom ? formatDate(selected!) : "Pick a day") {
                        showCalendar.toggle()
                    }
                    .font(JGRFont.regular(13.5))
                    .foregroundStyle(isCustom ? Color.jgrT1 : Color.jgrT2)
                    .tracking(-0.1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(isCustom ? Color.jgrSand : .clear)
                    .overlay(
                        Capsule().stroke(isCustom ? Color.jgrT2 : Color.jgrT4, lineWidth: 0.75)
                    )
                    .clipShape(Capsule())
                }
            }

            if showCalendar {
                MiniCalendarView(selected: $selected, onPick: { showCalendar = false })
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showCalendar)
    }

    private func formatDate(_ d: Date) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "EEE dd"; return fmt.string(from: d)
    }
}

// MARK: - Mini Calendar

struct MiniCalendarView: View {
    @Binding var selected: Date?
    let onPick: () -> Void

    @State private var viewMonth: Date

    init(selected: Binding<Date?>, onPick: @escaping () -> Void) {
        self._selected = selected
        self.onPick    = onPick
        let ref = selected.wrappedValue ?? .now
        self._viewMonth = State(initialValue: Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: ref))!)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private let weekdays = ["M","T","W","T","F","S","S"]

    private var cells: [Date?] {
        let cal   = Calendar.current
        let first = cal.date(from: cal.dateComponents([.year, .month], from: viewMonth))!
        let dow   = (cal.component(.weekday, from: first) + 5) % 7  // Mon=0
        let days  = cal.range(of: .day, in: .month, for: first)!.count
        var result: [Date?] = Array(repeating: nil, count: dow)
        for d in 1...days {
            result.append(cal.date(bySetting: .day, value: d, of: first))
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    var body: some View {
        VStack(spacing: 10) {
            Divider().background(Color.jgrT4)

            // Month nav
            HStack {
                Button { shiftMonth(-1) } label: {
                    Text("‹").font(.system(size: 18, weight: .light)).foregroundStyle(Color.jgrT2)
                        .frame(width: 36, height: 36)
                }
                Spacer()
                Text(viewMonth.formatted(.dateTime.month(.wide).year()))
                    .font(JGRFont.medium(13.5))
                    .foregroundStyle(Color.jgrT1)
                    .tracking(-0.1)
                Spacer()
                Button { shiftMonth(1) } label: {
                    Text("›").font(.system(size: 18, weight: .light)).foregroundStyle(Color.jgrT2)
                        .frame(width: 36, height: 36)
                }
            }

            // Weekday headers
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(weekdays, id: \.self) { d in
                    Text(d)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.jgrT3)
                        .tracking(1)
                        .frame(height: 28)
                }
            }

            // Day cells
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        DayCell(date: date, selected: selected) {
                            selected = date
                            onPick()
                        }
                    } else {
                        Color.clear.frame(height: 32)
                    }
                }
            }
        }
        .padding(.top, 10)
    }

    private func shiftMonth(_ delta: Int) {
        viewMonth = Calendar.current.date(byAdding: .month, value: delta, to: viewMonth) ?? viewMonth
    }
}

private struct DayCell: View {
    let date: Date
    let selected: Date?
    let onTap: () -> Void

    private var isToday: Bool    { Calendar.current.isDateInToday(date) }
    private var isSelected: Bool {
        guard let s = selected else { return false }
        return Calendar.current.isDate(date, inSameDayAs: s)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.jgrT1 : .clear)
                    .frame(width: 32, height: 32)

                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular,
                                  design: .default).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.jgrSurface : Color.jgrT1)

                if isToday && !isSelected {
                    Circle()
                        .fill(Color.jgrT2)
                        .frame(width: 3, height: 3)
                        .offset(y: 12)
                }
            }
            .frame(height: 32)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}

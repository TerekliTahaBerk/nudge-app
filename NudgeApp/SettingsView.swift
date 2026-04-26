import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var draft: AppSettings

    init() {
        // Will be overwritten in body via .onAppear; placeholder init.
        _draft = State(initialValue: AppSettings())
    }

    var body: some View {
        ZStack {
            Color.jgrBg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack(alignment: .firstTextBaseline) {
                        Button("Back") {
                            state.updateSettings(draft)
                            state.screen = .home
                        }
                        .font(JGRFont.regular(15))
                        .foregroundStyle(Color.jgrT2)
                        .tracking(-0.1)

                        Spacer()

                        Eyebrow(text: "Settings")

                        Spacer()
                        Color.clear.frame(width: 36)   // balance back button
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 28)

                    Spacer().frame(height: 52)

                    // ── Notification level ──────────────────────────────────
                    Eyebrow(text: "Notifications").padding(.horizontal, 32)
                    Spacer().frame(height: 22)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(NotificationLevel.allCases, id: \.self) { level in
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    draft.notificationLevel = level
                                }
                            } label: {
                                Text(level.label)
                                    .font(draft.notificationLevel == level
                                          ? JGRFont.medium(17) : JGRFont.regular(17))
                                    .foregroundStyle(draft.notificationLevel == level
                                                     ? Color.jgrT1 : Color.jgrT3)
                                    .tracking(-0.2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 32)

                    Spacer().frame(height: 44)

                    // ── Smart timing ────────────────────────────────────────
                    Eyebrow(text: "Smart timing").padding(.horizontal, 32)
                    Spacer().frame(height: 22)

                    HStack {
                        Text("Let the app choose moments")
                            .font(JGRFont.regular(17))
                            .foregroundStyle(Color.jgrT1)
                            .tracking(-0.2)
                        Spacer()
                        JGRToggle(isOn: $draft.smartTimingEnabled)
                    }
                    .padding(.horizontal, 32)

                    Spacer().frame(height: 8)
                    Text("Nudges arrive when you're likely receptive — never during quiet hours.")
                        .font(JGRFont.regular(12.5))
                        .foregroundStyle(Color.jgrT3)
                        .lineSpacing(3)
                        .padding(.horizontal, 32)

                    Spacer().frame(height: 44)

                    // ── Quiet hours ─────────────────────────────────────────
                    Eyebrow(text: "Quiet hours").padding(.horizontal, 32)
                    Spacer().frame(height: 22)

                    HStack(spacing: 16) {
                        HourPicker(hour: $draft.quietHoursStart)
                        Text("–")
                            .font(JGRFont.regular(17))
                            .foregroundStyle(Color.jgrT3)
                        HourPicker(hour: $draft.quietHoursEnd)
                    }
                    .padding(.horizontal, 32)

                    Spacer().frame(height: 44)

                    // ── Notification permission ──────────────────────────────
                    NotifPermissionRow()

                    Spacer().frame(height: 60)
                }
            }
        }
        .onAppear { draft = state.settings }
        .onDisappear { state.updateSettings(draft) }
    }
}

// MARK: - Hour Picker

struct HourPicker: View {
    @Binding var hour: Int

    var body: some View {
        Picker("", selection: $hour) {
            ForEach(0..<24) { h in
                Text(String(format: "%02d:00", h))
                    .font(JGRFont.regular(17).monospacedDigit())
                    .tag(h)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(Color.jgrT1)
        .font(JGRFont.regular(17).monospacedDigit())
    }
}

// MARK: - Notification Permission Row

struct NotifPermissionRow: View {
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Group {
            if status != .authorized {
                VStack(alignment: .leading, spacing: 8) {
                    Button("Allow notifications →") {
                        Task {
                            await NotificationScheduler.shared.requestPermission()
                            await refresh()
                        }
                    }
                    .font(JGRFont.regular(15))
                    .foregroundStyle(Color.jgrT2)
                    .tracking(-0.1)

                    Text("So nudges can reach you even when the app isn't open.")
                        .font(JGRFont.regular(12.5))
                        .foregroundStyle(Color.jgrT3)
                        .lineSpacing(3)
                }
                .padding(.horizontal, 32)
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        status = s.authorizationStatus
    }
}

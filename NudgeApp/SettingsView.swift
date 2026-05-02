import SwiftUI
import UserNotifications
import CoreLocation

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var draft: AppSettings

    init() {
        // Initial draft is replaced with current app settings on appear.
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

                    // ── Receptivity (Behaviour layer) ───────────────────────
                    Eyebrow(text: "Behaviour").padding(.horizontal, 32)
                    Spacer().frame(height: 22)

                    ReceptivityRow(
                        isOn: $draft.receptivityEnabled,
                        days: BehaviorAnalytics
                            .receptivityDots(from: state.reminders)
                            .map { (day: $0.day, size: $0.size) }
                    )
                    .padding(.horizontal, 32)

                    Spacer().frame(height: 44)

                    // ── This week (etiketsiz alan grafiği) ──────────────────
                    ThisWeekArea(
                        data: BehaviorAnalytics.weeklyCategoryStack(from: state.reminders),
                        observation: weeklyObservation()
                    )
                    .padding(.horizontal, 32)

                    Spacer().frame(height: 44)

                    // ── Places ──────────────────────────────────────────────
                    Eyebrow(text: "Places").padding(.horizontal, 32)
                    Spacer().frame(height: 22)
                    PlacesSection(aliases: $draft.locationAliases, onSaved: {
                        state.updateSettings(draft)
                        state.reconcileLocationTriggers()
                    })
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

    /// One quiet sentence above the weekly stack — picks up which categories
    /// dominated and which fell off. Always observation, never goal.
    private func weeklyObservation() -> String {
        let week = BehaviorAnalytics.weeklyCategoryStack(from: state.reminders)
        var totals: [ReminderCategory: Double] = Dictionary(uniqueKeysWithValues: ReminderCategory.allCases.map { ($0, 0) })
        for d in week { for (k, v) in d { totals[k, default: 0] += v } }
        let nonZero = totals.filter { $0.value > 0.01 }
        guard !nonZero.isEmpty else { return "A quiet week. Nothing to read into." }

        let sorted  = nonZero.sorted { $0.value > $1.value }
        let leading = sorted.prefix(2).map { $0.key.displayName }.filter { !$0.isEmpty }
        let absent  = totals.filter { $0.value < 0.01 }.map { $0.key.displayName }.filter { !$0.isEmpty }

        switch (leading.count, absent.first) {
        case (2, let a?): return "Mostly \(leading[0]) and \(leading[1]) — \(a) less this week."
        case (2, _):      return "Mostly \(leading[0]) and \(leading[1]) this week."
        case (1, let a?): return "Mostly \(leading[0]) — \(a) less this week."
        case (1, _):      return "Mostly \(leading[0]) this week."
        default:          return "A quiet week."
        }
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
                            _ = await NotificationScheduler.shared.requestPermission()
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

// MARK: - Places Section

struct PlacesSection: View {
    @Binding var aliases: [LocationAlias]
    let onSaved: () -> Void

    private let canonicalNames = ["home", "work", "gym"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(canonicalNames, id: \.self) { name in
                PlaceRow(name: name, alias: aliasBinding(for: name), onSaved: onSaved)
            }
        }
    }

    private func aliasBinding(for name: String) -> Binding<LocationAlias> {
        if let idx = aliases.firstIndex(where: { $0.name == name }) {
            return $aliases[idx]
        }
        aliases.append(LocationAlias(name: name))
        let idx = aliases.count - 1
        return $aliases[idx]
    }
}

struct PlaceRow: View {
    let name: String
    @Binding var alias: LocationAlias
    let onSaved: () -> Void

    @State private var locating = false
    @State private var fetchError: String?
    @State private var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private var hasCoords: Bool { alias.latitude != nil && alias.longitude != nil }
    private var permissionDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name.capitalized)
                    .font(JGRFont.regular(17))
                    .foregroundStyle(Color.jgrT1)
                    .tracking(-0.2)
                if permissionDenied {
                    Text("Location permission denied")
                        .font(JGRFont.regular(12.5))
                        .foregroundStyle(Color.jgrT3)
                } else if hasCoords {
                    Text("Saved")
                        .font(JGRFont.regular(12.5))
                        .foregroundStyle(Color.jgrT3)
                } else {
                    Text("Not set")
                        .font(JGRFont.regular(12.5))
                        .foregroundStyle(Color.jgrT4)
                }
                if let fetchError {
                    Text(fetchError)
                        .font(JGRFont.regular(12))
                        .foregroundStyle(.red.opacity(0.7))
                }
            }
            Spacer()
            Button(locating ? "Locating..." : (hasCoords ? "Update current location" : "Set current location")) {
                setCurrentLocation()
            }
            .font(JGRFont.regular(14))
            .foregroundStyle(locating || permissionDenied ? Color.jgrT4 : Color.jgrT2)
            .disabled(locating || permissionDenied)
            .buttonStyle(.plain)
            .frame(minHeight: 44, alignment: .trailing)
            .multilineTextAlignment(.trailing)
            .accessibilityLabel(hasCoords ? "Update current location for \(name)" : "Set current location for \(name)")
        }
        .onAppear { authorizationStatus = currentLocationAuthorizationStatus() }
    }

    private func setCurrentLocation() {
        locating = true
        fetchError = nil
        authorizationStatus = currentLocationAuthorizationStatus()
        OneTimeLocationFetcher.fetchCurrentLocation { result in
            DispatchQueue.main.async {
                locating = false
                authorizationStatus = currentLocationAuthorizationStatus()
                switch result {
                case .success(let coord):
                    alias.latitude = coord.latitude
                    alias.longitude = coord.longitude
                    onSaved()
                case .failure(let error):
                    fetchError = error.localizedDescription
                }
            }
        }
    }

    private func currentLocationAuthorizationStatus() -> CLAuthorizationStatus {
        CLLocationManager().authorizationStatus
    }
}

// MARK: - One-Shot Location Fetcher

final class OneTimeLocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((Result<CLLocationCoordinate2D, Error>) -> Void)?
    private static var retainKey: UInt8 = 0

    static func fetchCurrentLocation(completion: @escaping (Result<CLLocationCoordinate2D, Error>) -> Void) {
        let fetcher = OneTimeLocationFetcher()
        fetcher.completion = completion
        fetcher.manager.delegate = fetcher
        fetcher.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        switch fetcher.manager.authorizationStatus {
        case .notDetermined:
            fetcher.manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            completion(.failure(LocationFetchError.permissionDenied))
            return
        default:
            fetcher.manager.requestLocation()
        }
        // Retain fetcher until callback fires.
        objc_setAssociatedObject(fetcher.manager, &OneTimeLocationFetcher.retainKey, fetcher, .OBJC_ASSOCIATION_RETAIN)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            completion?(.failure(LocationFetchError.permissionDenied))
            cleanup(manager: manager)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        completion?(.success(loc.coordinate))
        cleanup(manager: manager)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion?(.failure(error))
        cleanup(manager: manager)
    }

    private func cleanup(manager: CLLocationManager) {
        completion = nil
        objc_setAssociatedObject(manager, &OneTimeLocationFetcher.retainKey, nil, .OBJC_ASSOCIATION_RETAIN)
    }
}

enum LocationFetchError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location permission is off."
        }
    }
}

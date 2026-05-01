import SwiftUI
import UserNotifications

@main
struct NudgeApp: App {

    @StateObject private var appState = AppState()

    init() {
        // Wire notification action callbacks before any view appears.
        _ = NotificationScheduler.shared
        // Callbacks are set in AppState.init after @StateObject is ready.
        // The delegate is registered on NotificationScheduler.shared init.
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.light)          // always light — warm paper design
                .tint(Color.jgrT1)
        }
    }
}

// MARK: - Root View (screen router)

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            Color.jgrBg.ignoresSafeArea()

            switch state.screen {
            case .splash:
                SplashView()
                    .transition(.opacity)
            case .onboarding:
                OnboardingView()
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            case .home:
                HomeView()
                    .transition(.opacity)
            case .settings:
                SettingsView()
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: state.screen)
        .overlay(alignment: .top) {
            if let nudge = state.activeNudge {
                NudgeBannerView(nudge: nudge)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: state.activeNudge?.id)
    }
}

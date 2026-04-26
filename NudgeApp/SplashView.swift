import SwiftUI

struct SplashView: View {
    @EnvironmentObject var state: AppState

    @State private var logoVisible   = false
    @State private var mottoVisible  = false
    @State private var fadeOut       = false

    var body: some View {
        ZStack {
            Color.jgrBg.ignoresSafeArea()

            VStack(spacing: 28) {
                LogoMark(size: 56, animate: true)
                    .opacity(logoVisible ? (fadeOut ? 0 : 1) : 0)

                VStack(spacing: 0) {
                    Text("Small nudges,")
                    Text("when you need them.")
                }
                .font(JGRFont.light(15))
                .foregroundStyle(Color.jgrT2)
                .tracking(-0.1)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .opacity(mottoVisible ? (fadeOut ? 0 : 1) : 0)
                .offset(y: mottoVisible ? 0 : 8)
            }
        }
        .onAppear { animate() }
    }

    private func animate() {
        // Logo appears immediately
        withAnimation(.easeOut(duration: 0.9)) {
            logoVisible = true
        }
        // Motto fades up after 800ms
        withAnimation(.easeOut(duration: 0.7).delay(0.8)) {
            mottoVisible = true
        }
        // Everything fades out at 1.8s, then transition
        withAnimation(.easeIn(duration: 0.4).delay(1.8)) {
            fadeOut = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
            state.completeSplash()
        }
    }
}

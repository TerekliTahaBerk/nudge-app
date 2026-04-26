import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @State private var name: String = ""
    @FocusState private var focused: Bool

    private var ready: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            Color.jgrBg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 80)

                LogoMark(size: 32)

                Spacer().frame(height: 40)

                Text("What should we call you?")
                    .font(JGRFont.regular(28))
                    .foregroundStyle(Color.jgrT1)
                    .tracking(-0.6)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer().frame(height: 10)

                Text("Just so we can greet you. Stays on this device.")
                    .font(JGRFont.regular(13))
                    .foregroundStyle(Color.jgrT3)
                    .tracking(-0.05)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer().frame(height: 52)

                VStack(spacing: 0) {
                    TextField("Your name", text: $name)
                        .font(JGRFont.light(19))
                        .foregroundStyle(Color.jgrT1)
                        .tracking(-0.2)
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .submitLabel(.continue)
                        .onSubmit { trySubmit() }
                        .padding(.vertical, 6)

                    Rectangle()
                        .fill(Color.jgrT4)
                        .frame(height: 0.75)
                }
                .padding(.horizontal, 32)

                Spacer()

                Button(action: trySubmit) {
                    Text("Continue")
                        .font(JGRFont.regular(16))
                        .foregroundStyle(ready ? Color.jgrT1 : Color.jgrT3)
                        .tracking(-0.2)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .disabled(!ready)
                .animation(.easeInOut(duration: 0.3), value: ready)
                .padding(.bottom, 56)
            }
        }
        .onAppear { focused = true }
    }

    private func trySubmit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        focused = false
        state.completeOnboarding(name: trimmed)
    }
}

import SwiftUI

// MARK: - Color Tokens
// Approximated from the oklch design values.

extension Color {
    // Background & surface
    static let jgrBg      = Color(red: 0.980, green: 0.969, blue: 0.952)  // warm paper
    static let jgrSurface = Color(red: 0.999, green: 0.997, blue: 0.994)  // near-white

    // Text scale
    static let jgrT1 = Color(red: 0.140, green: 0.130, blue: 0.115)  // primary — warm ink
    static let jgrT2 = Color(red: 0.380, green: 0.360, blue: 0.330)  // secondary
    static let jgrT3 = Color(red: 0.580, green: 0.560, blue: 0.520)  // tertiary
    static let jgrT4 = Color(red: 0.740, green: 0.720, blue: 0.690)  // quaternary

    // Accent
    static let jgrSand = Color(red: 0.960, green: 0.930, blue: 0.895)

    // Category hues — ultra-muted pastels
    static let catBody = Color(red: 0.944, green: 0.880, blue: 0.780)  // sand-amber
    static let catMove = Color(red: 0.800, green: 0.908, blue: 0.820)  // sage-green
    static let catMind = Color(red: 0.820, green: 0.840, blue: 0.960)  // soft mist
    static let catGrow = Color(red: 0.950, green: 0.855, blue: 0.790)  // warm clay

    static func categoryColor(_ cat: ReminderCategory) -> Color {
        switch cat {
        case .body: return .catBody
        case .move: return .catMove
        case .mind: return .catMind
        case .grow: return .catGrow
        case .social: return .catMind
        case .task: return .jgrT3.opacity(0.65)
        case .errand: return .catMove
        case .health: return .catBody
        case .home: return .catGrow
        case .work: return .catMind.opacity(0.85)
        case .none: return .clear
        }
    }
}

// MARK: - Typography helpers

struct JGRFont {
    static func regular(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .default) }
    static func light(_ size: CGFloat)   -> Font { .system(size: size, weight: .light,   design: .default) }
    static func medium(_ size: CGFloat)  -> Font { .system(size: size, weight: .medium,  design: .default) }
    static func eyebrow()                -> Font { .system(size: 11,   weight: .medium,  design: .default) }
}

// MARK: - Eyebrow label

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(JGRFont.eyebrow())
            .tracking(1.8)
            .foregroundStyle(Color.jgrT3)
    }
}

// MARK: - Logo mark

struct LogoMark: View {
    var size: CGFloat = 36
    var animate: Bool = false

    @State private var dotScale: CGFloat  = 0
    @State private var ringScale: CGFloat = 0.5
    @State private var ringOpacity: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.jgrT4, lineWidth: 0.75)
                .frame(width: size, height: size)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)
            Circle()
                .fill(Color.jgrT1)
                .frame(width: size * 0.22, height: size * 0.22)
                .scaleEffect(dotScale)
        }
        .frame(width: size, height: size)
        .onAppear {
            if animate {
                withAnimation(.easeOut(duration: 0.9)) { dotScale = 1 }
                withAnimation(.easeOut(duration: 1.1).delay(0.2)) {
                    ringScale   = 1
                    ringOpacity = 1
                }
            } else {
                dotScale    = 1
                ringScale   = 1
                ringOpacity = 1
            }
        }
    }
}

// MARK: - Checkbox

struct JGRCheckbox: View {
    let done: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(done ? Color.jgrT4 : Color.jgrT3, lineWidth: 0.75)
                .frame(width: 16, height: 16)
            Circle()
                .fill(Color.jgrT1)
                .frame(width: 5, height: 5)
                .opacity(done ? 0.7 : 0)
                .scaleEffect(done ? 1 : 0.4)
        }
        .frame(width: 24, height: 24)
        .animation(.easeInOut(duration: 0.45), value: done)
    }
}

// MARK: - Toggle switch (styled)

struct JGRToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.jgrT1 : Color.jgrT4)
                .frame(width: 34, height: 20)
            Circle()
                .fill(Color.jgrSurface)
                .shadow(color: .black.opacity(0.12), radius: 1, x: 0, y: 1)
                .frame(width: 14, height: 14)
                .padding(.horizontal, 3)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isOn)
        .onTapGesture { isOn.toggle() }
    }
}

// MARK: - Pulsing dot for "next nudge" preview

struct PulsingDot: View {
    @State private var scale: CGFloat  = 0.82
    @State private var opacity: Double = 0.35

    var body: some View {
        Circle()
            .fill(Color.jgrT2)
            .frame(width: 6, height: 6)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    scale   = 1.0
                    opacity = 1.0
                }
            }
    }
}

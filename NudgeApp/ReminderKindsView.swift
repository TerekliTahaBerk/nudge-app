import SwiftUI

// MARK: - TypeGlyph
// Tiny hairline glyph that lives at the right of a reminder row.
// Same vocabulary across all kinds — 0.85pt stroke, 14×14 box.

struct TypeGlyph: View {
    let type: ReminderType
    var color: Color = .jgrT3
    var opacity: Double = 0.85

    var body: some View {
        Canvas { ctx, size in
            let w  = size.width
            let h  = size.height
            let c  = CGPoint(x: w / 2, y: h / 2)
            let sw = 0.85

            switch type {
            case .trigger:
                // event: small ring + two short hairlines through it
                let ring = Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8))
                ctx.stroke(ring, with: .color(color), lineWidth: sw)
                ctx.stroke(Path { p in p.move(to: .init(x: c.x, y: 1.5)); p.addLine(to: .init(x: c.x, y: 3)) },
                           with: .color(color), lineWidth: sw)
                ctx.stroke(Path { p in p.move(to: .init(x: c.x, y: 11)); p.addLine(to: .init(x: c.x, y: 12.5)) },
                           with: .color(color), lineWidth: sw)

            case .voice:
                // four bars — a tiny waveform
                let bars: [(CGFloat, CGFloat, CGFloat)] = [
                    (3, 5, 9), (6, 3, 11), (9, 4, 10), (12, 6, 8)
                ]
                for (x, y1, y2) in bars {
                    ctx.stroke(Path { p in
                        p.move(to: .init(x: x, y: y1)); p.addLine(to: .init(x: x, y: y2))
                    }, with: .color(color), lineWidth: sw)
                }

            case .linked:
                // two dots connected by an arc
                ctx.fill(Path(ellipseIn: CGRect(x: 3.5 - 1.2, y: c.y - 1.2, width: 2.4, height: 2.4)),
                         with: .color(color))
                ctx.fill(Path(ellipseIn: CGRect(x: 10.5 - 1.2, y: c.y - 1.2, width: 2.4, height: 2.4)),
                         with: .color(color))
                ctx.stroke(Path { p in
                    p.move(to: .init(x: 4.5, y: 7))
                    p.addQuadCurve(to: .init(x: 9.5, y: 7), control: .init(x: 7, y: 4.5))
                }, with: .color(color), lineWidth: sw)

            case .oneoff:
                // a soft sun — a small circle + a tiny ray on top
                let r: CGFloat = 2.4
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y + 0.5 - r, width: r * 2, height: r * 2)),
                           with: .color(color), lineWidth: sw)
                ctx.stroke(Path { p in
                    p.move(to: .init(x: c.x, y: 1.5)); p.addLine(to: .init(x: c.x, y: 3))
                }, with: .color(color), lineWidth: sw)

            case .standard:
                // just a single small dot
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 1.4, y: c.y - 1.4, width: 2.8, height: 2.8)),
                         with: .color(color))
            }
        }
        .frame(width: 14, height: 14)
        .opacity(opacity)
    }
}

// MARK: - ReminderKindSelector
// "Kind" rows in the new-reminder sheet. Selecting changes the accessory below.

struct ReminderKindSelector: View {
    @Binding var value: ReminderType

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(ReminderType.allCases, id: \.self) { kind in
                kindButton(for: kind)
            }
        }
    }

    private func kindButton(for kind: ReminderType) -> some View {
        let active = value == kind
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { value = kind }
        } label: {
            HStack(spacing: 14) {
                TypeGlyph(
                    type: kind,
                    color: active ? Color.jgrT1 : Color.jgrT3,
                    opacity: active ? 1 : 0.6
                )
                .frame(width: 22)

                Text(kind.label)
                    .font(active ? JGRFont.medium(16) : JGRFont.regular(16))
                    .foregroundStyle(active ? Color.jgrT1 : Color.jgrT3)
                    .tracking(-0.2)

                Text("· \(kind.hint)")
                    .font(JGRFont.regular(13))
                    .foregroundStyle(active ? Color.jgrT3 : Color.jgrT4)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ChipRow (a small radio row used by Trigger/Linked pickers)

private struct ChipRow: View {
    let active: Bool
    let label: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(active ? Color.jgrT1 : Color.jgrT4, lineWidth: 0.75)
                        .frame(width: 14, height: 14)
                    Circle()
                        .fill(Color.jgrT1)
                        .frame(width: 5, height: 5)
                        .opacity(active ? 1 : 0)
                        .scaleEffect(active ? 1 : 0.4)
                }
                Text(label)
                    .font(active ? JGRFont.medium(15) : JGRFont.regular(15))
                    .foregroundStyle(active ? Color.jgrT1 : Color.jgrT2)
                    .tracking(-0.15)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: active)
    }
}

// MARK: - TriggerPicker
// A moment, a place, or a custom one — all on-device.

struct TriggerPicker: View {
    @Binding var value: TriggerInfo?

    private struct Option: Identifiable {
        let id: String; let label: String
    }

    private let moments: [Option] = [
        .init(id: "morning_phone",   label: "When I unlock in the morning"),
        .init(id: "open_laptop",     label: "When I open my laptop"),
        .init(id: "connect_charger", label: "When I plug in to charge"),
    ]
    private let places: [Option] = [
        .init(id: "home", label: "When I get home"),
        .init(id: "work", label: "When I arrive at work"),
        .init(id: "gym",  label: "When I leave the gym"),
    ]

    @State private var customText: String = ""

    private func isActive(_ kind: TriggerInfo.Kind, _ id: String?) -> Bool {
        value?.kind == kind && value?.id == id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "A moment")
            Spacer().frame(height: 14)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(moments) { m in
                    ChipRow(active: isActive(.moment, m.id), label: m.label) {
                        value = TriggerInfo(kind: .moment, id: m.id, label: m.label)
                    }
                }
            }

            Spacer().frame(height: 26)
            Eyebrow(text: "A place")
            Spacer().frame(height: 14)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(places) { p in
                    ChipRow(active: isActive(.place, p.id), label: p.label) {
                        value = TriggerInfo(kind: .place, id: p.id, label: p.label)
                    }
                }
            }

            Spacer().frame(height: 26)
            Eyebrow(text: "Custom")
            Spacer().frame(height: 12)

            VStack(spacing: 0) {
                TextField("When I…", text: $customText)
                    .font(JGRFont.regular(16))
                    .foregroundStyle(Color.jgrT1)
                    .tracking(-0.2)
                    .onChange(of: customText) { _, new in
                        if !new.isEmpty {
                            value = TriggerInfo(kind: .custom, id: nil, label: new)
                        }
                    }
                    .padding(.vertical, 6)
                Rectangle().fill(Color.jgrT4).frame(height: 0.75)
            }

            Spacer().frame(height: 8)
            Text("Picked up by your phone, never sent off the device.")
                .font(JGRFont.regular(12))
                .foregroundStyle(Color.jgrT3)
                .lineSpacing(2)
        }
        .onAppear {
            if value?.kind == .custom { customText = value?.label ?? "" }
        }
    }
}

// MARK: - VoiceRecorder (mock)
// Quietly mocks a 5-second recording — taps generate a waveform.

struct VoiceRecorderView: View {
    @Binding var value: VoiceInfo?

    enum State { case idle, recording, recorded, playing }
    @SwiftUI.State private var state: State = .idle
    @SwiftUI.State private var elapsed: Double = 0
    @SwiftUI.State private var samples: [Double] = []
    @SwiftUI.State private var ticker: Timer?

    private let maxSeconds: Double = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Spacer().frame(height: 14)

            waveform

            Spacer().frame(height: 14)

            controls
        }
        .padding(18)
        .background(Color.jgrSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .onAppear {
            if let v = value {
                samples = v.samples
                elapsed = v.duration
                state = .recorded
            }
        }
        .onDisappear { ticker?.invalidate() }
    }

    private var header: some View {
        HStack {
            Eyebrow(text: stateLabel)
            Spacer()
            Text(state == .idle ? "up to 5s" : String(format: "%.1fs", elapsed))
                .font(JGRFont.regular(12).monospacedDigit())
                .foregroundStyle(Color.jgrT3)
                .tracking(0.2)
        }
    }

    @ViewBuilder
    private var waveform: some View {
        HStack(alignment: .center, spacing: 2) {
            if state == .idle && samples.isEmpty {
                Text("Tap record to leave a 5-second voice note. It plays back as the nudge.")
                    .font(JGRFont.regular(13))
                    .foregroundStyle(Color.jgrT3)
                    .tracking(-0.05)
                    .lineSpacing(2)
            } else {
                ForEach(Array(displaySamples.enumerated()), id: \.offset) { sample in
                    Capsule()
                        .fill(state == .recording ? Color.jgrT1 : Color.jgrT2)
                        .frame(width: 2, height: max(2, CGFloat(sample.element) * 38))
                        .opacity(0.85)
                }
            }
        }
        .frame(height: 44, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 22) {
            switch state {
            case .idle:
                Button("● Record") { startRecording() }
                    .font(JGRFont.medium(14))
                    .foregroundStyle(Color.jgrT1)
            case .recording:
                Button("Stop") { stopRecording() }
                    .font(JGRFont.medium(14))
                    .foregroundStyle(Color.jgrT1)
            case .recorded:
                Button("▷ Play") { playBack() }
                    .font(JGRFont.medium(14))
                    .foregroundStyle(Color.jgrT1)
                Button("Re-record") { reset() }
                    .font(JGRFont.regular(14))
                    .foregroundStyle(Color.jgrT3)
            case .playing:
                Text("Playing…")
                    .font(JGRFont.regular(14))
                    .foregroundStyle(Color.jgrT3)
            }
            Spacer()
        }
    }

    private var stateLabel: String {
        switch state {
        case .recording: return "Recording"
        case .playing:   return "Playing"
        default:         return "Voice note"
        }
    }

    private var displaySamples: [Double] {
        if !samples.isEmpty { return samples }
        // seed pattern when nothing recorded yet (only used after recorded state)
        return (0..<38).map { i in
            0.35 + 0.55 * abs(sin(Double(i) * 0.6 + 0.4)) * (1 - Double(i) / 80)
        }
    }

    private func startRecording() {
        samples = []
        elapsed = 0
        state = .recording
        let start = Date()
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { t in
            let dt = Date().timeIntervalSince(start)
            if dt >= maxSeconds {
                t.invalidate()
                Task { @MainActor in stopRecording(at: maxSeconds) }
                return
            }
            Task { @MainActor in
                elapsed = dt
                samples.append(0.3 + Double.random(in: 0...0.7))
            }
        }
    }

    private func stopRecording(at finalT: Double? = nil) {
        ticker?.invalidate()
        let t = finalT ?? elapsed
        elapsed = t
        if samples.isEmpty { samples = displaySamples }
        state = .recorded
        value = VoiceInfo(duration: t, samples: samples)
    }

    private func playBack() {
        state = .playing
        let dur = max(elapsed, 0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + dur) {
            if state == .playing { state = .recorded }
        }
    }

    private func reset() {
        state = .idle
        samples = []
        elapsed = 0
        value = nil
    }
}

// MARK: - LinkedPicker
// Pick a parent reminder + delay after it.

struct LinkedPicker: View {
    let parents: [(UUID, String)]
    @Binding var value: LinkInfo?

    private let delays: [(Int, String)] = [
        (5, "5 min"), (10, "10 min"), (30, "Half an hour"), (120, "2 hours")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "After which")
            Spacer().frame(height: 14)
            VStack(alignment: .leading, spacing: 14) {
                if parents.isEmpty {
                    Text("Add another reminder first, then you can chain this one to it.")
                        .font(JGRFont.regular(13))
                        .foregroundStyle(Color.jgrT3)
                        .lineSpacing(2)
                } else {
                    ForEach(parents, id: \.0) { parent in
                        parentRow(parent)
                    }
                }
            }

            Spacer().frame(height: 26)
            Eyebrow(text: "And then, after")
            Spacer().frame(height: 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(delays, id: \.0) { delay in
                        delayButton(delay)
                    }
                }
            }
        }
    }

    private func parentRow(_ parent: (UUID, String)) -> some View {
        ChipRow(active: value?.parentId == parent.0, label: parent.1) {
            value = LinkInfo(parentId: parent.0, delayMin: value?.delayMin ?? 10)
        }
    }

    private func delayButton(_ delay: (Int, String)) -> some View {
        let minutes = delay.0
        let label = delay.1
        let active = value?.delayMin == minutes

        return Button(label) {
            let parent = value?.parentId ?? parents.first?.0
            if let parent {
                value = LinkInfo(parentId: parent, delayMin: minutes)
            }
        }
        .font(JGRFont.regular(13.5))
        .foregroundStyle(active ? Color.jgrT1 : Color.jgrT2)
        .tracking(-0.1)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(active ? Color.jgrSand : .clear)
        .overlay(Capsule().stroke(active ? Color.jgrT2 : Color.jgrT4, lineWidth: 0.75))
        .clipShape(Capsule())
    }
}

// MARK: - OneoffNote
// A short copy block reminding the user this won't repeat.

struct OneoffNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Just for today")
            Text("We'll bring it up sometime today, then let it go. No tomorrow, no next week.")
                .font(JGRFont.regular(14.5))
                .foregroundStyle(Color.jgrT1)
                .tracking(-0.1)
                .lineSpacing(3)
        }
    }
}

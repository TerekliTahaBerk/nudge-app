import SwiftUI

// MARK: - PatternCard
// "Pattern noticed" — observation, not celebration. No streaks.

struct PatternCard: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Hairline left mark — same vocabulary as a category capsule but ink-tinted
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.jgrT2.opacity(0.35))
                .frame(width: 3)
                .padding(.vertical, 18)

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Pattern noticed")
                Text(text)
                    .font(JGRFont.regular(16))
                    .foregroundStyle(Color.jgrT1)
                    .tracking(-0.2)
                    .lineSpacing(4)
            }
            .padding(.leading, 13)
            .padding(.vertical, 14)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - QuietHoldback
// "Yesterday was quiet. We held back." — single italic line above today.

struct QuietHoldback: View {
    var message: String = "Yesterday was quiet. We held back."

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.jgrT4).frame(width: 6, height: 6)
            Text(message)
                .font(JGRFont.regular(13))
                .italic()
                .foregroundStyle(Color.jgrT2)
                .tracking(-0.05)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - EasedBackBanner
// Surface-coloured card after the app reduces cadence.

struct EasedBackBanner: View {
    var onDismiss: () -> Void = {}
    var onUndo: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "We've eased back")
            Text("Last few nudges felt mistimed, so we've moved to once a day for a while. We'll listen and adjust again.")
                .font(JGRFont.regular(15.5))
                .foregroundStyle(Color.jgrT1)
                .tracking(-0.2)
                .lineSpacing(3)
            Spacer().frame(height: 8)
            HStack(spacing: 22) {
                Button("Okay", action: onDismiss)
                    .font(JGRFont.medium(14))
                    .foregroundStyle(Color.jgrT1)
                Button("Undo", action: onUndo)
                    .font(JGRFont.regular(14))
                    .foregroundStyle(Color.jgrT3)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.jgrSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

// MARK: - MaybeLaterReceipt
// Subtle one-line receipt after dismissing a nudge as "later".

struct MaybeLaterReceipt: View {
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.jgrT3.opacity(0.4)).frame(width: 6, height: 6)
            Text("We'll bring it back later. No need to think about when.")
                .font(JGRFont.regular(13))
                .foregroundStyle(Color.jgrT3)
                .tracking(-0.05)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - ReceptivityRow
// Settings row + 7 dots whose diameter encodes engagement that day.

struct ReceptivityRow: View {
    @Binding var isOn: Bool
    /// Ordered Mon-..-Sun (or last-7-days), today rightmost. size in pt 3..8.
    let days: [(day: String, size: CGFloat)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Read my rhythm")
                    .font(JGRFont.regular(17))
                    .foregroundStyle(Color.jgrT1)
                    .tracking(-0.2)
                Spacer()
                JGRToggle(isOn: $isOn)
            }
            Spacer().frame(height: 8)
            Text("Reads your last week to time things better. Stays on this device.")
                .font(JGRFont.regular(12.5))
                .foregroundStyle(Color.jgrT3)
                .lineSpacing(3)

            Spacer().frame(height: 18)

            HStack(alignment: .bottom) {
                ForEach(Array(days.enumerated()), id: \.offset) { idx, d in
                    let isToday = idx == days.count - 1
                    VStack(spacing: 8) {
                        ZStack {
                            if isToday {
                                Circle()
                                    .stroke(Color.jgrT3, lineWidth: 0.75)
                                    .frame(width: d.size + 8, height: d.size + 8)
                            }
                            Circle()
                                .fill(Color.jgrT2)
                                .opacity(isOn ? 0.55 : 0.18)
                                .frame(width: d.size, height: d.size)
                        }
                        .frame(height: 16)
                        Text(d.day)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.jgrT3)
                            .tracking(0.6)
                            .opacity(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - ThisWeekArea
// 7 days × 4 categories, etiketsiz stacked area. No numbers, no labels.

struct ThisWeekArea: View {
    /// Each entry: dictionary keyed by category with 0..1 fractions.
    let data: [[ReminderCategory: Double]]
    var observation: String = "A quiet week. Mostly body and mind — you stepped outside less."

    private let cats: [ReminderCategory] = [.body, .move, .mind, .grow]
    private let weekdayLabels = ["M","T","W","T","F","S","S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "This week")
            Spacer().frame(height: 14)
            Text(observation)
                .font(JGRFont.regular(17))
                .foregroundStyle(Color.jgrT1)
                .tracking(-0.2)
                .lineSpacing(3)
            Spacer().frame(height: 22)

            GeometryReader { geo in
                let w = geo.size.width
                let h: CGFloat = 92
                let n = max(data.count, 1)
                let stepX = w / CGFloat(max(n - 1, 1))

                ZStack(alignment: .topLeading) {
                    // Build stacked fills, bottom layer first
                    ForEach(Array(cats.enumerated()), id: \.offset) { ci, cat in
                        let topPoints: [CGPoint] = data.enumerated().map { (i, d) in
                            let upTo = cats.prefix(ci + 1).reduce(0.0) { $0 + (d[$1] ?? 0) }
                            return CGPoint(x: CGFloat(i) * stepX, y: h - CGFloat(upTo) * h)
                        }
                        let prevPoints: [CGPoint] = ci == 0
                            ? data.enumerated().map { (i, _) in CGPoint(x: CGFloat(i) * stepX, y: h) }
                            : data.enumerated().map { (i, d) in
                                let upTo = cats.prefix(ci).reduce(0.0) { $0 + (d[$1] ?? 0) }
                                return CGPoint(x: CGFloat(i) * stepX, y: h - CGFloat(upTo) * h)
                            }

                        Path { p in
                            if let first = topPoints.first { p.move(to: first) }
                            for pt in topPoints.dropFirst() { p.addLine(to: pt) }
                            for pt in prevPoints.reversed() { p.addLine(to: pt) }
                            p.closeSubpath()
                        }
                        .fill(Color.categoryColor(cat).opacity(0.7))
                    }

                    // Hairline baseline
                    Path { p in
                        p.move(to: .init(x: 0, y: h + 0.5))
                        p.addLine(to: .init(x: w, y: h + 0.5))
                    }
                    .stroke(Color.jgrT4, lineWidth: 0.75)

                    // Day ticks
                    HStack {
                        ForEach(0..<min(weekdayLabels.count, n), id: \.self) { i in
                            Text(weekdayLabels[i])
                                .font(.system(size: 9))
                                .foregroundStyle(Color.jgrT3)
                                .tracking(0.6)
                                .opacity(0.7)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .offset(y: h + 4)
                }
            }
            .frame(height: 110)

            Spacer().frame(height: 8)
            Text("Categories are felt, not labelled.")
                .font(JGRFont.regular(12.5))
                .foregroundStyle(Color.jgrT3)
                .lineSpacing(3)
        }
    }
}

// MARK: - NotificationWithActions (preview card)
// Faux iOS notification with Done / Maybe later actions side-by-side.

struct NotificationWithActions: View {
    let title: String
    let message: String

    var bodyView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.jgrBg)
                        .frame(width: 30, height: 30)
                    LogoMark(size: 18)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("JUST GENTLE REMINDERS")
                            .font(JGRFont.eyebrow())
                            .tracking(0.1)
                            .foregroundStyle(Color.black.opacity(0.62))
                        Spacer()
                        Text("now")
                            .font(JGRFont.regular(11.5))
                            .foregroundStyle(Color.black.opacity(0.62))
                    }
                    Spacer().frame(height: 2)
                    Text(title)
                        .font(JGRFont.medium(14))
                        .foregroundStyle(Color.black.opacity(0.95))
                        .tracking(-0.2)
                    Text(message)
                        .font(JGRFont.regular(13.5))
                        .foregroundStyle(Color.black.opacity(0.78))
                        .tracking(-0.1)
                        .lineSpacing(2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().background(Color.black.opacity(0.08))

            HStack(spacing: 0) {
                Button("Done") {}
                    .font(JGRFont.medium(14))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: 44)
                Divider().background(Color.black.opacity(0.08))
                Button("Maybe later") {}
                    .font(JGRFont.regular(14))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .background(Color(red: 1.0, green: 0.98, blue: 0.953).opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    var body: some View { bodyView }
}

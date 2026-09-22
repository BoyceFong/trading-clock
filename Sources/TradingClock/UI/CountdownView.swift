import SwiftUI

/// Small `M:SS` readout to the next 5-minute candle close. Tints with the
/// alert color while flashing. A black stroke keeps the digits readable over
/// white / bright chart backgrounds.
struct CountdownView: View {
    let text: String
    let alert: CandleClock.Snapshot.Alert

    var body: some View {
        StrokedText(
            text: text,
            fill: tint,
            stroke: .black,
            strokeWidth: 2.2,
            font: .system(size: Theme.countdownFontSize, weight: .medium, design: .rounded))
        .shadow(color: .black.opacity(0.30), radius: 3, y: 1)
    }

    private var tint: Color {
        switch alert {
        case .none:   return .white
        case .yellow: return Color(nsColor: .systemYellow)
        case .red:    return Color(nsColor: .systemRed)
        }
    }
}

/// Text with a crisp outline: eight offset copies of the glyph ring behind the
/// filled copy on top. Readable on any background.
struct StrokedText: View {
    let text: String
    let fill: Color
    let stroke: Color
    let strokeWidth: CGFloat
    let font: Font

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) * .pi / 4
                label(stroke)
                    .offset(x: cos(angle) * strokeWidth, y: sin(angle) * strokeWidth)
            }
            label(fill)
        }
        .monospacedDigit()
    }

    private func label(_ color: Color) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
    }
}

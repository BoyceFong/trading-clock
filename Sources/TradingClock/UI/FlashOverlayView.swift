import SwiftUI

/// Candle-close alert built on `EdgeGlowMask`'s distance-field profile:
/// soft diffusion that is mathematically identical at every point of the
/// perimeter, plus one crisp highlight ring (colored body + white core).
///
/// Nothing here is a blurred stroke: the haze is `f(distance)`, so "the whole
/// ring glows equally" holds at any window size and aspect ratio by
/// construction.
struct FlashOverlayView: View {
    let alert: CandleClock.Snapshot.Alert
    /// Bump once per pulse; retriggers the keyframed flash.
    let pulseToken: Int
    let windowSize: CGSize

    @State private var mask: NSImage?

    var body: some View {
        KeyframeAnimator(initialValue: CGFloat(0), trigger: pulseToken) { strength in
            shape(opacity: strength)
        } keyframes: { _ in
            // ≈0.45 s lit inside every 1 s: quick rise, hold, soft fall.
            KeyframeTrack(\.self) {
                CubicKeyframe(1, duration: Theme.pulseRise)
                CubicKeyframe(1, duration: Theme.pulseHold)
                CubicKeyframe(0, duration: Theme.pulseFall)
            }
        }
        .allowsHitTesting(false)
        .task(id: windowSize) {
            // Debounce live resize; the mask is pure geometry (tint-free).
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let scale = max(NSScreen.main?.backingScaleFactor ?? 2, 2)
            mask = EdgeGlowMask.image(size: windowSize, scale: scale)
        }
    }

    private func shape(opacity o: CGFloat) -> some View {
        let color = glowColor
        let v = Double(o)
        return ZStack {
            // Diffuse haze: f(t) around the whole perimeter, fading to a
            // gentle wash across the middle of the pane.
            if let mask {
                Rectangle()
                    .fill(color)
                    .frame(width: windowSize.width, height: windowSize.height)
                    .mask(
                        Image(nsImage: mask)
                            .resizable()
                            .frame(width: windowSize.width, height: windowSize.height))
                    .opacity(v)
            }

            // Crisp highlight ring: constant width and opacity the whole way
            // around, with a white core so it reads on bright charts too.
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(color.opacity(0.92 * v), lineWidth: Theme.flashRingWidth)
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(Color.white.opacity(0.70 * v), lineWidth: Theme.flashCoreWidth)
        }
    }

    private var glowColor: Color {
        switch alert {
        case .none:   return .clear
        case .yellow: return Color(nsColor: .systemYellow)
        case .red:    return Color(nsColor: .systemRed)
        }
    }
}

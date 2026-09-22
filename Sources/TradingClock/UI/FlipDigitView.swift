import SwiftUI

/// Interpolated fold progress: 0 = flap folded up over the top half (about to
/// fall), 1 = flap landed flat on the bottom half.
private struct FlipPhase: Sendable {
    var tau: Double = 0
}

/// One Solari split-flap digit.
///
/// A single half-card falls forward 180° around the center seam — the real
/// mechanical motion: front face shows the OLD top half, back face (pre-
/// flipped) shows the NEW bottom half. The static top already shows the NEW
/// top (revealed as the flap falls); the static bottom keeps the OLD bottom
/// (covered as the flap lands).
///
/// One continuous rotation driven by `KeyframeAnimator` at display refresh
/// (60–120 fps): gravity fall, whip past vertical, tiny settle on landing.
/// Card faces are pre-rasterized bitmaps, so the 3D rotation never re-lays-out
/// text — no blur, no frame drops.
struct FlipDigitView: View {
    let value: Character
    var size: CGSize = Theme.digitSize

    @State private var from: Character
    @State private var to: Character
    /// Bumped after `from`/`to` are swapped, so the animator's restart frame
    /// still paints the previous digit — the reset is invisible.
    @State private var trigger = 0

    init(value: Character, size: CGSize = Theme.digitSize) {
        self.value = value
        self.size = size
        _from = State(initialValue: value)
        _to = State(initialValue: value)
    }

    var body: some View {
        KeyframeAnimator(initialValue: FlipPhase(), trigger: trigger) { phase in
            card(from: from, to: to, tau: phase.tau)
        } keyframes: { _ in
            KeyframeTrack(\.tau) {
                let s = Theme.flipSpeedScale
                // Slow tip off the latch (0→~60°): gravity just starts winning.
                CubicKeyframe(0.33, duration: Theme.flipTip * s,
                             startVelocity: 0.9 / s, endVelocity: 3.5 / s)
                // Accelerating fall through horizontal (60→126°).
                CubicKeyframe(0.70, duration: Theme.flipFall * s,
                             startVelocity: 3.5 / s, endVelocity: 6.2 / s)
                // Whip to the stop at maximum speed (126→171°).
                CubicKeyframe(0.95, duration: Theme.flipWhip * s,
                             startVelocity: 6.2 / s, endVelocity: 7.0 / s)
                // Slam onto the stop: hard landing, barely-there bounce.
                SpringKeyframe(1.0, duration: Theme.flipLand * s,
                              spring: .init(duration: Theme.flipLand * s, bounce: 0.12),
                              startVelocity: 7.0 / s)
            }
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: value) { _, newValue in
            from = to
            to = newValue
            trigger &+= 1
        }
    }

    // MARK: Static halves + falling flap

    @ViewBuilder
    private func card(from: Character, to: Character, tau: Double) -> some View {
        // Negative angle about x with anchor .bottom = the flap's top edge
        // swings toward the viewer (Solari falls forward).
        let angle = -180 * tau

        ZStack {
            // Static halves. Top shows the target (revealed by the fall),
            // bottom keeps the outgoing digit (covered on landing).
            VStack(spacing: 0) {
                FaceImage(digit: to, half: .top, size: size)
                FaceImage(digit: from, half: .bottom, size: size)
            }

            landingShadow(tau: tau)

            ZStack {
                if tau < 0.5 {
                    // Front face: old top half, darkening as it turns away.
                    FaceImage(digit: from, half: .top, size: size)
                        .overlay(Color.black.opacity(0.40 * min(tau * 2, 1)))
                } else {
                    // Back face: new bottom half, pre-flipped so it reads
                    // upright once the flap has fallen through.
                    FaceImage(digit: to, half: .bottom, size: size)
                        .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
                        .overlay(Color.black.opacity(0.40 * max(0, 1 - (tau - 0.5) * 2)))
                }
            }
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 1, y: 0, z: 0),
                anchor: .bottom,
                anchorZ: 0,
                perspective: 0.42)
            .offset(y: -size.height / 4) // flap box sits on the top half slot
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    /// Contact shadow the falling flap casts onto the bottom half as it lands.
    private func landingShadow(tau: Double) -> some View {
        let opacity = Double(max(0, (tau - 0.55) / 0.45)) * 0.32
        return LinearGradient(
            colors: [Color.black.opacity(opacity), .clear],
            startPoint: .top, endPoint: .bottom)
            .frame(width: size.width, height: size.height / 2)
            .offset(y: size.height / 4)
            .allowsHitTesting(false)
    }
}

enum FlipHalf {
    case top, bottom
}

/// A cached bitmap of one half-card face. Rasterized once per digit at 4× so
/// the 3D fold is a pure GPU transform and stays crisp under window scaling.
@MainActor
enum FaceRaster {
    private static var cache: [String: NSImage] = [:]

    static func image(digit: Character, half: FlipHalf, size: CGSize) -> NSImage {
        let key = "\(digit)-\(half == .top ? "T" : "B")-\(Int(size.width))x\(Int(size.height))"
        if let hit = cache[key] { return hit }
        let renderer = ImageRenderer(content: HalfCardFace(digit: digit, half: half, size: size))
        renderer.scale = 4 // design-pt → pixels; crisp up to ≈2.5× scaleEffect
        let image = renderer.nsImage
            ?? NSImage(size: NSSize(width: size.width, height: size.height / 2))
        cache[key] = image
        return image
    }
}

struct FaceImage: View {
    let digit: Character
    let half: FlipHalf
    let size: CGSize

    var body: some View {
        Image(nsImage: FaceRaster.image(digit: digit, half: half, size: size))
            .interpolation(.high)
            .frame(width: size.width, height: size.height / 2)
    }
}

/// Full flip-card face clipped to its top or bottom half (the clip naturally
/// keeps only the outer rounded corners of that half).
private struct HalfCardFace: View {
    let digit: Character
    let half: FlipHalf
    let size: CGSize

    var body: some View {
        CardFace(digit: digit, size: size)
            .frame(width: size.width, height: size.height / 2,
                   alignment: half == .top ? .top : .bottom)
            .clipped()
    }
}

/// The complete (unclipped) card face: gradient plastic halves, centered
/// numeral, center seam with hinge nubs.
private struct CardFace: View {
    let digit: Character
    let size: CGSize

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Theme.cardTopGradient)
                    .frame(height: size.height / 2)
                Rectangle()
                    .fill(Theme.cardBottomGradient)
                    .frame(height: size.height / 2)
            }

            Text(String(digit))
                .font(.system(size: size.height * 0.70, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.digitColor)
                .frame(height: size.height)

            seam
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.digitCornerRadius))
    }

    private var seam: some View {
        VStack(spacing: 0) {
            Color.black.opacity(0.55).frame(height: 2)
            Color.white.opacity(0.06).frame(height: 1)
        }
        .frame(height: 3)
        .overlay(alignment: .leading) {
            hingeNub.offset(x: 3)
        }
        .overlay(alignment: .trailing) {
            hingeNub.offset(x: -3)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var hingeNub: some View {
        Circle()
            .fill(Color.black.opacity(0.45))
            .frame(width: 4, height: 4)
    }
}

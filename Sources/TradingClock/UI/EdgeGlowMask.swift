import AppKit

/// The flash glow's spatial profile, defined from first principles.
///
/// Intensity depends ONLY on `t` — the true Euclidean distance from a pixel to
/// the window's rounded-rect edge:
///
///     f(t) = wash + peak · e^(−t/λ) + slope · max(0, 1 − t/H)
///
/// Under this definition "the whole perimeter glows equally" is an identity,
/// not a tuning outcome: top, bottom, sides and corners all share one profile.
/// (Stacking blurred strokes can never guarantee this — wide strokes distort
/// at the rounded corners, blur spills get clipped at the window edge, and
/// bar-like bands read heavier along the longer edges.)
///
/// Rendered once per size as a white alpha mask; tinted at draw time so the
/// geometry never changes with the alert color.
enum EdgeGlowMask {
    struct Profile {
        /// Distance-independent floor — the wash across the whole pane.
        var wash: Double = 0.05
        /// Extra intensity right at the edge (the rim's halo).
        var peak: Double = 0.13
        /// Gentle ramp toward the middle (the diffusion).
        var slope: Double = 0.08
        /// λ, the exponential decay length, as a fraction of the shorter side.
        var decayFraction: Double = 0.085
        var cornerRadius: Double = Theme.cornerRadius
    }

    /// Signed distance to the rounded-rect boundary (negative inside).
    static func sdf(x: Double, y: Double, w: Double, h: Double, r: Double) -> Double {
        let rr = min(r, min(w, h) / 2)
        let qx = abs(x - w / 2) - (w / 2 - rr)
        let qy = abs(y - h / 2) - (h / 2 - rr)
        let ox = max(qx, 0)
        let oy = max(qy, 0)
        return hypot(ox, oy) + min(max(qx, qy), 0) - rr
    }

    /// Glow intensity at interior distance `t >= 0` from the edge.
    static func intensity(t: Double, minDim: Double, profile: Profile) -> Double {
        let lambda = max(profile.decayFraction * minDim, 1)
        let H = max(minDim / 2, 1)
        return profile.wash
            + profile.peak * exp(-t / lambda)
            + profile.slope * max(0, 1 - t / H)
    }

    /// White alpha mask of `f(t)` over the window shape. The profile is
    /// mirror-symmetric, so the raw bitmap row order cannot distort it.
    static func image(size: CGSize, scale: CGFloat, profile: Profile = .init()) -> NSImage {
        let w = max(Int((size.width * scale).rounded()), 1)
        let h = max(Int((size.height * scale).rounded()), 1)
        let minDim = Double(min(size.width, size.height))

        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data?.bindMemory(to: UInt8.self, capacity: w * h * 4) else {
            return NSImage(size: size)
        }

        let ww = Double(size.width)
        let hh = Double(size.height)
        for row in 0..<h {
            for col in 0..<w {
                let x = (Double(col) + 0.5) / Double(scale)
                let y = (Double(row) + 0.5) / Double(scale)
                let d = sdf(x: x, y: y, w: ww, h: hh, r: profile.cornerRadius)
                let a = d < 0 ? intensity(t: -d, minDim: minDim, profile: profile) : 0
                let i = (row * w + col) * 4
                data[i] = 255
                data[i &+ 1] = 255
                data[i &+ 2] = 255
                data[i &+ 3] = UInt8(max(0, min(255, (a * 255).rounded())))
            }
        }
        guard let cg = ctx.makeImage() else { return NSImage(size: size) }
        return NSImage(cgImage: cg, size: size)
    }
}

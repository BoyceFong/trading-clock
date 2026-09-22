import SwiftUI

/// Shared metrics and the Solari flip-card palette.
enum Theme {
    /// Window corner radius (Liquid Glass card + 凝光 ring).
    static let cornerRadius: CGFloat = 26

    // Design canvas — all content is laid out at this fixed size and scaled
    // uniformly to the window (see RootView).
    static let canvasSize = CGSize(width: 640, height: 240)

    // Flip-card metrics (design points).
    static let digitSize = CGSize(width: 84, height: 124)
    static let digitCornerRadius: CGFloat = 12
    static let intraGroupGap: CGFloat = 12   // gap inside HH / MM / SS
    static let groupGap: CGFloat = 32        // gap between groups (stands in for the colon)
    static let countdownSpacing: CGFloat = 18
    static let countdownFontSize: CGFloat = 34

    // Split-flap timing — physical pendulum fall (≈0.32 s total): the flap
    // tips slowly off the latch, accelerates under gravity, whips past
    // vertical at top speed and slams onto the stop with a micro-settle.
    static let flipTip: TimeInterval = 0.165  // 0→~60°: slow tip-off
    static let flipFall: TimeInterval = 0.080 // 60→126°: accelerating fall
    static let flipWhip: TimeInterval = 0.038 // 126→171°: maximum speed
    static let flipLand: TimeInterval = 0.040 // impact on the stop, tiny bounce

    // Alert pulse: ~0.45 s lit inside every second.
    static let pulseRise: TimeInterval = 0.05
    static let pulseHold: TimeInterval = 0.35
    static let pulseFall: TimeInterval = 0.15

    // Flash highlight ring (vector-crisp, constant width around the entire
    // perimeter): colored body + white core so it stays visible on any chart.
    static let flashRingWidth: CGFloat = 3.5
    static let flashCoreWidth: CGFloat = 1.3

    /// Slow-motion flips for visual verification (TC_FLIP_SLOW=1).
    static var flipSpeedScale: Double {
        ProcessInfo.processInfo.environment["TC_FLIP_SLOW"] == nil ? 1 : 10
    }

    // Solari card colors: deep neutral gray halves with a slight vertical
    // lightening, white numerals.
    static let cardTopGradient = LinearGradient(
        colors: [
            Color(red: 0.20, green: 0.20, blue: 0.22),
            Color(red: 0.17, green: 0.17, blue: 0.19),
        ],
        startPoint: .top, endPoint: .bottom)
    static let cardBottomGradient = LinearGradient(
        colors: [
            Color(red: 0.15, green: 0.15, blue: 0.17),
            Color(red: 0.12, green: 0.12, blue: 0.14),
        ],
        startPoint: .top, endPoint: .bottom)
    static let digitColor = Color.white.opacity(0.92)

    // 凝光 edge ring (from the calendar widget): dark outer ring + specular rim.
    static func idleRingOpacity(_ scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.20 : 0.10
    }
}

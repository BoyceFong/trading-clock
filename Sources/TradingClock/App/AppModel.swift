import AppKit
import Observation

/// Glass material mode, mirroring the calendar widget's proven setup.
enum GlassMode: Sendable {
    case glass     // NSGlassEffectView (macOS 26 Liquid Glass)
    case material  // NSVisualEffectView fallback (debug / compatibility)
    case solid     // opaque (Reduce Transparency)
}

/// Single source of truth for displayed state and menu-visible toggles.
@MainActor
@Observable
final class AppModel {
    // Wall-clock-derived display state (updated once per second by ClockEngine).
    private(set) var now = Date()
    private(set) var hour = 0
    private(set) var minute = 0
    private(set) var second = 0
    private(set) var secondsToClose = 300
    private(set) var alert: CandleClock.Snapshot.Alert = .none
    /// Incremented once per alert pulse so FlashOverlay can re-trigger its animation.
    private(set) var pulseToken = 0

    // Menu-visible toggles.
    private(set) var windowVisible = true
    private(set) var launchAtLogin = false

    var glassMode: GlassMode

    init(glassMode: GlassMode) {
        self.glassMode = glassMode
    }

    /// Called by ClockEngine at every wall-clock second boundary (and on resync).
    func apply(date: Date) {
        now = date
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        hour = comps.hour ?? 0
        minute = comps.minute ?? 0
        second = comps.second ?? 0

        let snapshot = CandleClock.snapshot(at: date)
        secondsToClose = snapshot.secondsToClose

        let wasAlert = alert
        alert = snapshot.alert
        if snapshot.alert != .none {
            // One pulse per second while an alert is live (yellow ×3, red ×5).
            pulseToken &+= 1
        } else if wasAlert != .none {
            // Alert window just ended — one last token bump lets the overlay settle off.
            pulseToken &+= 1
        }
    }

    func setWindowVisible(_ visible: Bool) {
        windowVisible = visible
    }

    func setLaunchAtLogin(_ on: Bool) {
        launchAtLogin = on
    }

    /// Digit strings for the flip clock, zero-padded 24h `HH MM SS`.
    var digitChars: [Character] {
        let h = String(format: "%02d", hour)
        let m = String(format: "%02d", minute)
        let s = String(format: "%02d", second)
        return Array(h + m + s)
    }

    var countdownText: String {
        CandleClock.countdownText(secondsToClose: secondsToClose)
    }
}

import Foundation

/// 5-minute candle phase relative to the local wall clock.
///
/// Candle boundaries are local-clock whole 5 minutes (:00 :05 :10 …), i.e.
/// `minute % 5 == 0 && second == 0` is a close. One-second-aligned snapshot:
///
/// - remaining 30/29/28 s → yellow alert ×3 pulses (1 per second)
/// - remaining  5/4/3/2/1 s → red alert ×5 pulses (1 per second)
///
/// `TC_CANDLE_LEN_SECONDS` (default 300) compresses the candle length for
/// quickly exercising the flash cadence in development.
enum CandleClock {
    struct Snapshot: Equatable {
        enum Alert: Equatable {
            case none
            case yellow
            case red
        }

        /// Seconds left until the next close, `1...period`
        /// (`period` at the first second of a fresh candle).
        var secondsToClose: Int
        var alert: Alert
    }

    /// Candle length in seconds (period). Debuggable via env.
    static var periodSeconds: Int {
        let env = ProcessInfo.processInfo.environment["TC_CANDLE_LEN_SECONDS"].flatMap(Int.init) ?? 300
        return env > 0 ? env : 300
    }

    static func snapshot(at date: Date) -> Snapshot {
        let period = periodSeconds
        let comps = Calendar.current.dateComponents([.minute, .second], from: date)
        let pos = ((comps.minute ?? 0) * 60 + (comps.second ?? 0)) % period
        let remaining = period - pos // 1...period

        let alert: Snapshot.Alert
        switch remaining {
        case 28...30: alert = .yellow
        case 1...5:   alert = .red
        default:      alert = .none
        }
        return Snapshot(secondsToClose: remaining, alert: alert)
    }

    /// `M:SS` countdown label (e.g. `3:42`, `5:00`).
    static func countdownText(secondsToClose: Int) -> String {
        String(format: "%d:%02d", secondsToClose / 60, secondsToClose % 60)
    }
}

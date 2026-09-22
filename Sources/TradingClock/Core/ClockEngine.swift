import AppKit
import Foundation

/// Drives one callback per wall-clock second boundary.
///
/// Never uses a free-running `interval: 1` timer (those accumulate drift):
/// each wake computes the next whole-second boundary from `Date()`, fires a
/// one-shot timer there, and re-derives every displayed value from the current
/// `Date()` — late fires self-correct and the display cannot drift.
/// Wake-from-sleep and system-clock/timezone changes resync immediately.
@MainActor
final class ClockEngine {
    var onTick: ((Date) -> Void)?

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    func start() {
        stop()

        let wsCenter = NSWorkspace.shared.notificationCenter
        observers.append(wsCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resync() }
        })

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resync() }
        })
        observers.append(center.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resync() }
        })

        // Immediate first paint, then tick at each whole second.
        fire()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers = []
    }

    /// Re-derive everything right now (post-wake / clock jump) and restart the schedule.
    func resync() {
        timer?.invalidate()
        timer = nil
        fire()
    }

    private func fire() {
        onTick?(Date())
        scheduleNext()
    }

    private func scheduleNext() {
        timer?.invalidate()
        let now = Date()
        let frac = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
        let delay = frac == 0 ? 1 : 1 - frac
        let t = Timer(fire: now.addingTimeInterval(delay), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        // Precision matters for second-aligned flips; keep tolerance at zero.
        t.tolerance = 0
        // .common so the clock keeps ticking while a menu is open.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

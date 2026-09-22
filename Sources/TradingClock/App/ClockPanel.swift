import AppKit
import SwiftUI

/// Borderless, non-activating floating panel: no traffic lights, always above
/// chart windows, free resize via invisible edge handles, edge/corner snap.
final class ClockPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    static let minSize = NSSize(width: 280, height: 120)
    static let maxSize = NSSize(width: 1600, height: 700)

    /// Snap threshold to screen visibleFrame edges, in points.
    static let snapThreshold: CGFloat = 14

    /// Guards against snap → setFrame → windowDidMove → snap recursion.
    private var isSnapping = false
    private var geometrySaveTask: Task<Void, Never>?

    static func make() -> ClockPanel {
        let geometry = Settings.geometry
        let panel = ClockPanel(
            contentRect: NSRect(x: 0, y: 0, width: geometry.width, height: geometry.height),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        // All Spaces + above full-screen apps (trading terminals) + out of ⌘` cycle.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.minSize = minSize
        panel.maxSize = maxSize
        return panel
    }

    // MARK: Geometry persistence (macOS top-left coordinates)

    func restoreFrame() {
        let geometry = Settings.geometry
        let size = NSSize(width: geometry.width, height: geometry.height)
        setContentSize(size)
        if Settings.hasSavedGeometry && geometry.origin != .zero {
            setFrameTopLeftPoint(NSPoint(x: geometry.origin.x, y: geometry.origin.y))
        } else {
            center()
        }
    }

    func persistFrame() {
        let frame = self.frame
        let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
        Settings.geometry = CGRect(origin: topLeft, size: frame.size)
    }

    private func schedulePersist() {
        geometrySaveTask?.cancel()
        geometrySaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.persistFrame()
        }
    }

    /// Borderless-window shadows go stale after moves; nudge AppKit to re-read
    /// the opaque pixels.
    func invalidateCardShadow() {
        invalidateShadow()
    }

    // MARK: Edge / corner snapping

    /// Snap the window to the nearest edges/corners of the host screen's
    /// visibleFrame when within `snapThreshold`. No system API exists for this
    /// (verified against the macOS 26 SDK), so it is computed by hand.
    func snapIfNeeded() {
        guard !isSnapping, let screen = self.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let threshold = Self.snapThreshold
        var frame = self.frame
        var moved = false

        // Left / right (independent — both apply at corners).
        if abs(frame.minX - visible.minX) < threshold {
            frame.origin.x = visible.minX
            moved = true
        } else if abs(frame.maxX - visible.maxX) < threshold {
            frame.origin.x = visible.maxX - frame.width
            moved = true
        }
        // Bottom / top (macOS y grows upward; menu bar lives above visibleFrame.maxY).
        if abs(frame.minY - visible.minY) < threshold {
            frame.origin.y = visible.minY
            moved = true
        } else if abs(frame.maxY - visible.maxY) < threshold {
            frame.origin.y = visible.maxY - frame.height
            moved = true
        }

        guard moved else { return }
        isSnapping = true
        setFrame(frame, display: true)
        isSnapping = false
    }

    // MARK: Move / resize hooks (wired from the window delegate)

    func noteMoved() {
        snapIfNeeded()
        invalidateCardShadow()
        schedulePersist()
    }

    func noteResized() {
        invalidateCardShadow()
        schedulePersist()
    }
}

/// Hosting view that turns any left-button press into a window drag (the
/// whole glass surface is a drag handle). Right-click still falls through to
/// SwiftUI for the context menu.
final class DragHostingView<Content: View>: NSHostingView<Content> {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)
    }
}

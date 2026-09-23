import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var actions: AppActions!
    private var panel: ClockPanel!
    private var clockEngine: ClockEngine!
    private var hotKeyService: HotKeyService!
    private var statusItemController: StatusItemController!

    private var transparencyObserver: AnyCancellable?
    private var glassView: NSGlassEffectView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pin the glass fog valves shut (see GlassKeeper for the two frost
        // mechanisms and why the key-state brain is left intact).
        GlassKeeper.install()

        // Glass mode: env override → Reduce Transparency forces solid.
        var glassMode: GlassMode = switch ProcessInfo.processInfo.environment["TC_GLASS_MODE"] {
        case "material": .material
        case "solid": .solid
        default: .glass
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            glassMode = .solid
        }

        model = AppModel(glassMode: glassMode)
        actions = AppActions()
        attachActions()

        buildPanel()

        clockEngine = ClockEngine()
        clockEngine.onTick = { [weak self] date in
            self?.model.apply(date: date)
        }
        clockEngine.start()

        hotKeyService = HotKeyService()
        hotKeyService.onToggle = { [weak self] in
            self?.toggleWindowVisibility()
        }
        hotKeyService.start()

        statusItemController = StatusItemController(model: model, actions: actions)
        model.setLaunchAtLogin(LoginItemService.isEnabled())

        observeReduceTransparency()
        observeGlassEdges()
        // Launch edge: WindowServer backdrop capture registers asynchronously.
        if let glassView {
            GlassKeeper.assertFresh(glassView)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        panel?.persistFrame()
        clockEngine?.stop()
        hotKeyService?.stop()
    }

    // MARK: Window assembly

    private func buildPanel() {
        let panel = ClockPanel.make()
        panel.delegate = self

        let container = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        container.autoresizingMask = [.width, .height]

        let hosting: NSView = DragHostingView(
            rootView: RootView()
                .environment(model)
                .environment(actions))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]

        switch model.glassMode {
        case .glass:
            // Liquid Glass card: content embedded via `contentView` per
            // WWDC25-310 (keeps AppKit's legibility treatments live).
            let glass = NSGlassEffectView(frame: container.bounds)
            glass.style = .clear
            glass.cornerRadius = Theme.cornerRadius
            glass.wantsLayer = true
            glass.layer?.masksToBounds = true
            glass.layer?.cornerRadius = Theme.cornerRadius
            glass.autoresizingMask = [.width, .height]
            glass.contentView = hosting
            container.addSubview(glass)
            glassView = glass

        case .material:
            let effect = NSVisualEffectView(frame: container.bounds)
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = Theme.cornerRadius
            effect.layer?.masksToBounds = true
            effect.autoresizingMask = [.width, .height]
            container.addSubview(effect)
            container.addSubview(hosting)

        case .solid:
            container.addSubview(hosting)
        }

        // Invisible resize handles on top (claim left-drag only).
        let handles = ResizeHandlesView(frame: container.bounds)
        container.addSubview(handles)

        panel.contentView = container
        panel.restoreFrame()
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateCardShadow()
        model.setWindowVisible(true)

        self.panel = panel
    }

    // MARK: Glass invariant edges

    /// Sampling-desync edges only — launch and un-hide are wired at their call
    /// sites. Key transitions are deliberately NOT here: rebuilding the glass
    /// material while unfocused re-frosts it (v2 regression).
    private func observeGlassEdges() {
        let center = NotificationCenter.default
        let wsCenter = NSWorkspace.shared.notificationCenter
        let assert: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let glassView = self?.glassView else { return }
                GlassKeeper.assertFresh(glassView)
            }
        }
        center.addObserver(forName: NSWindow.didChangeScreenNotification, object: panel, queue: .main, using: assert)
        wsCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: assert)
    }

    // MARK: Actions

    private func attachActions() {
        actions.toggleWindowVisibility = { [weak self] in
            self?.toggleWindowVisibility()
        }
        actions.setWindowVisible = { [weak self] visible in
            self?.setWindowVisible(visible)
        }
        actions.toggleLaunchAtLogin = { [weak self] in
            let on = LoginItemService.toggle()
            self?.model.setLaunchAtLogin(on)
        }
        actions.setHotkeyPreset = { [weak self] index in
            guard let self else { return }
            if !self.hotKeyService.register(presetIndex: index) {
                NSLog("Hotkey preset \(index) failed to register; staying on \(self.hotKeyService.registeredIndex)")
            }
        }
        actions.quit = {
            NSApp.terminate(nil)
        }
    }

    private func toggleWindowVisibility() {
        setWindowVisible(!model.windowVisible)
    }

    private func setWindowVisible(_ visible: Bool) {
        if visible {
            panel.orderFrontRegardless()
            panel.invalidateCardShadow()
            // Un-hide edge: orderOut tore down backdrop capture; a hotkey
            // show does not pass through key transitions, so assert here.
            if let glassView {
                GlassKeeper.assertFresh(glassView)
            }
        } else {
            panel.orderOut(nil)
        }
        model.setWindowVisible(visible)
    }

    // MARK: Reduce Transparency

    private func observeReduceTransparency() {
        transparencyObserver = NSWorkspace.shared.publisher(
            for: \.accessibilityDisplayShouldReduceTransparency)
            .sink { [weak self] reduced in
                Task { @MainActor in
                    guard let self else { return }
                    // Glass ↔ solid is a rebuild-level change; simplest robust
                    // behavior: note it and keep running in the current mode.
                    // (Full live-rebuild is overkill for an accessibility edge.)
                    if reduced {
                        self.model.glassMode = .solid
                    }
                }
            }
    }
}

// MARK: - NSWindowDelegate (snap, geometry persistence, shadow upkeep)

extension AppDelegate: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        panel?.noteMoved()
    }

    func windowDidResize(_ notification: Notification) {
        panel?.noteResized()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        panel?.invalidateCardShadow()
        panel?.persistFrame()
    }
}

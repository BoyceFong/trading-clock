import AppKit

/// Menu-bar resident status item. Its dropdown mirrors the window's right-click
/// menu (show/hide, launch at login, hotkey presets, quit). Menu titles follow
/// the system language (NSLocalizedString resolves per open).
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let model: AppModel
    private let actions: AppActions

    private var visibilityItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var hotkeyMenu: NSMenu!
    private var hotkeyItems: [NSMenuItem] = []

    init(model: AppModel, actions: AppActions) {
        self.model = model
        self.actions = actions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "clock", accessibilityDescription: L10n.t("menu.title"))
            image?.isTemplate = true
            button.image = image
            button.toolTip = "TradingClock"
        }

        buildMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func buildMenu() {
        menu.removeAllItems()

        visibilityItem = NSMenuItem(
            title: L10n.t("menu.toggleWindow"),
            action: #selector(toggleVisibility),
            keyEquivalent: "")
        visibilityItem.target = self
        menu.addItem(visibilityItem)

        menu.addItem(.separator())

        loginItem = NSMenuItem(
            title: L10n.t("menu.launchAtLogin"),
            action: #selector(toggleLogin),
            keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        let hotkeyParent = NSMenuItem(title: L10n.t("menu.hotkey"), action: nil, keyEquivalent: "")
        hotkeyMenu = NSMenu(title: L10n.t("menu.hotkey"))
        hotkeyItems = []
        for (index, preset) in HotKeyService.presets.enumerated() {
            let item = NSMenuItem(title: preset.name, action: #selector(selectHotkey(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            hotkeyMenu.addItem(item)
            hotkeyItems.append(item)
        }
        hotkeyParent.submenu = hotkeyMenu
        menu.addItem(hotkeyParent)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L10n.t("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// Refresh titles (system language may change) and checkmark states.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        visibilityItem.title = L10n.t("menu.toggleWindow")
        visibilityItem.state = model.windowVisible ? .on : .off
        loginItem.title = L10n.t("menu.launchAtLogin")
        loginItem.state = model.launchAtLogin ? .on : .off

        // Refresh the hotkey labels + selection against the live service preset.
        let selectedIndex = HotKeyService.presets.indices.contains(Settings.hotkeyPresetIndex)
            ? Settings.hotkeyPresetIndex : 0
        for (index, item) in hotkeyItems.enumerated() {
            item.title = HotKeyService.presets[index].name
            item.state = index == selectedIndex ? .on : .off
        }
    }

    // MARK: Actions

    @objc private func toggleVisibility() {
        actions.toggleWindowVisibility()
    }

    @objc private func toggleLogin() {
        actions.toggleLaunchAtLogin()
    }

    @objc private func selectHotkey(_ sender: NSMenuItem) {
        actions.setHotkeyPreset(sender.tag)
    }

    @objc private func quit() {
        actions.quit()
    }
}

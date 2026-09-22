import SwiftUI

/// Right-click menu on the clock window — mirrors the status-bar menu.
/// Titles follow the system language.
struct ContextMenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(AppActions.self) private var actions

    var body: some View {
        Button(L10n.t("menu.hideWindow")) { actions.setWindowVisible(false) }

        Divider()

        Toggle(L10n.t("menu.launchAtLogin"), isOn: Binding(
            get: { model.launchAtLogin },
            set: { _ in actions.toggleLaunchAtLogin() }))

        Menu(L10n.t("menu.hotkey")) {
            ForEach(HotKeyService.presets.indices, id: \.self) { index in
                Toggle(HotKeyService.presets[index].name, isOn: Binding(
                    get: { Settings.hotkeyPresetIndex == index },
                    set: { _ in actions.setHotkeyPreset(index) }))
            }
        }

        Divider()

        Button(L10n.t("menu.quit")) { actions.quit() }
    }
}

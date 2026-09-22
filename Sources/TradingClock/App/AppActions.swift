import Foundation
import Observation

/// Menu-facing actions, attached by AppDelegate and invoked from both the
/// right-click menu and the status-bar menu so state stays in sync.
@MainActor
@Observable
final class AppActions {
    var toggleWindowVisibility: () -> Void = {}
    var setWindowVisible: (Bool) -> Void = { _ in }
    var toggleLaunchAtLogin: () -> Void = {}
    var setHotkeyPreset: (Int) -> Void = { _ in }
    var quit: () -> Void = {}
}

import AppKit
import Carbon.HIToolbox

/// Global hotkey via Carbon `RegisterEventHotKey` — no Accessibility permission
/// required, works system-wide (verified: no deprecation in the macOS 26 SDK).
///
/// Presets: default ⌃⌘K (K for K-line/candle). If another app ever claims the
/// combo, switch from the context menu — registration failure falls back to the
/// next preset automatically.
final class HotKeyService {
    struct Preset {
        let name: String          // "⌃⌘K" — display only, not localized
        let keyCode: UInt32
        let carbonModifiers: UInt32

        /// NSEvent-modifier description for menu key-equivalent display.
        var keyEquivalentModifierMask: NSEvent.ModifierFlags {
            var flags: NSEvent.ModifierFlags = []
            if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
            if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
            if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
            if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
            return flags
        }

        var keyEquivalent: String {
            // ANSI key codes for the letter keys we use.
            switch keyCode {
            case UInt32(kVK_ANSI_K): return "k"
            default: return ""
            }
        }
    }

    static let presets: [Preset] = [
        Preset(name: "⌃⌘K", keyCode: UInt32(kVK_ANSI_K),
               carbonModifiers: UInt32(controlKey | cmdKey)),
        Preset(name: "⌃⌥⌘K", keyCode: UInt32(kVK_ANSI_K),
               carbonModifiers: UInt32(controlKey | optionKey | cmdKey)),
        Preset(name: "⌥⌘K", keyCode: UInt32(kVK_ANSI_K),
               carbonModifiers: UInt32(optionKey | cmdKey)),
    ]

    /// Fired on the main thread whenever the registered combo is pressed.
    var onToggle: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private(set) var registeredIndex = 0

    private static let hotKeySignature: OSType = 0x5443_4B43 // 'TKCK'

    /// Set for the C hot-key callback's lifetime (main run loop dispatch).
    private nonisolated(unsafe) static var active: HotKeyService?

    /// Register the persisted preset; on failure fall back through the list.
    func start() {
        Self.active = self
        let preferred = Settings.hotkeyPresetIndex
        let order = [preferred] + (0..<Self.presets.count).filter { $0 != preferred }
        for index in order {
            if register(presetIndex: index) {
                return
            }
        }
        NSLog("HotKeyService: all presets failed to register")
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
            self.hotKeyHandlerRef = nil
        }
        Self.active = nil
    }

    @discardableResult
    func register(presetIndex: Int) -> Bool {
        guard Self.presets.indices.contains(presetIndex) else { return false }
        stop()
        Self.active = self // stop() cleared it; preset switches must re-arm
        installHandlerIfNeeded()

        let preset = Self.presets[presetIndex]
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            preset.keyCode,
            preset.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref)
        guard status == noErr, let ref else {
            NSLog("HotKeyService: RegisterEventHotKey(\(preset.name)) failed: \(status)")
            return false
        }
        hotKeyRef = ref
        registeredIndex = presetIndex
        Settings.hotkeyPresetIndex = presetIndex
        return true
    }

    var currentPreset: Preset {
        Self.presets[registeredIndex]
    }

    private func installHandlerIfNeeded() {
        guard hotKeyHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        // Carbon dispatches hot-key events on the main run loop. The C callback
        // captures nothing (Swift 6 sendability); it reaches the service via
        // `Self.active`.
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                MainActor.assumeIsolated {
                    HotKeyService.active?.onToggle?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &hotKeyHandlerRef)
    }

    deinit {
        stop()
    }
}

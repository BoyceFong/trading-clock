import AppKit

/// Persisted app settings (window geometry, hotkey preset).
enum Settings {
    private static var ud: UserDefaults { .standard }

    // MARK: Geometry (macOS top-left coordinates, same convention as the calendar widget)

    static var geometry: CGRect {
        get {
            let d = ud.dictionary(forKey: "geometry") as? [String: Double] ?? [:]
            return CGRect(
                x: d["x"] ?? 0,
                y: d["y"] ?? 0,
                width: d["width"] ?? 640,
                height: d["height"] ?? 280
            )
        }
        set {
            ud.set(["x": newValue.origin.x, "y": newValue.origin.y,
                    "width": newValue.width, "height": newValue.height],
                   forKey: "geometry")
        }
    }

    static var hasSavedGeometry: Bool {
        ud.dictionary(forKey: "geometry") != nil
    }

    // MARK: Global hotkey preset index (HotKeyService.presets order)

    static var hotkeyPresetIndex: Int {
        get { ud.integer(forKey: "hotkey.presetIndex") }
        set { ud.set(newValue, forKey: "hotkey.presetIndex") }
    }
}

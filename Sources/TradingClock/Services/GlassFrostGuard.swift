import AppKit
import ObjectiveC

/// NSGlassEffectView frosts ("subdue") whenever its window resigns key —
/// verified against the macOS 26.5 runtime: the class implements
/// `-_windowChangedKeyState`, `-_subduedState` / `-set_subduedState:` and
/// `-_scrimState`, and there is no public opt-out on macOS 26
/// (`effectIsInteractive` is macOS 27+).
///
/// This guard replaces those private hooks with no-ops so the glass keeps the
/// exact focused treatment — fully transparent, never frosted — whether or
/// not the clock window is key. Both target selectors take a single scalar
/// argument at most, so ignoring them is ABI-safe on arm64.
enum GlassFrostGuard {
    static func install() {
        neutralizeNoArg(NSGlassEffectView.self, selector: "_windowChangedKeyState")
        neutralizeSetter(NSGlassEffectView.self, selector: "set_subduedState:")
        neutralizeSetter(NSGlassEffectView.self, selector: "set_scrimState:")
    }

    private static func neutralizeNoArg(_ cls: AnyClass, selector name: String) {
        let sel = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(cls, sel) else { return }
        let imp = imp_implementationWithBlock({ (_: AnyObject) in } as @convention(block) (AnyObject) -> Void)
        method_setImplementation(method, imp)
    }

    private static func neutralizeSetter(_ cls: AnyClass, selector name: String) {
        let sel = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(cls, sel) else { return }
        let imp = imp_implementationWithBlock({ (_: AnyObject, _: Int) in } as @convention(block) (AnyObject, Int) -> Void)
        method_setImplementation(method, imp)
    }
}

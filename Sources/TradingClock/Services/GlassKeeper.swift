import AppKit
import ObjectiveC

/// Keeps Liquid Glass in its transparent treatment — permanently, across
/// every lifecycle edge that can desync it.
///
/// Two distinct frost mechanisms exist on macOS 26 (verified by runtime
/// probing a live NSGlassEffectView):
///
/// 1. **Subdued treatment** — on `-_windowChangedKeyState` the system writes
///    `-_subduedState` / `-_scrimState` via `-set_subduedState:` /
///    `-set_scrimState:` (Int64 ivars) and the glass frosts while unfocused.
/// 2. **Stale/absent backdrop capture** — the WindowServer-side sampling of
///    what's behind the window registers asynchronously (launch race) and is
///    torn down while the window is ordered out (long-hide → hotkey show).
///    With no live sample the glass renders its no-sample fallback, which
///    *looks* identical to frost. Moving the window across screens "fixes"
///    it because that path force-rebuilds the material + capture.
///
/// The invariant is therefore two-part: *no fog trigger* and *backdrop
/// sampling fresh*. This type enforces both:
///
/// - `install()` kills the `-_windowChangedKeyState` fog trigger outright and
///   pins the fog setters to 0. (v2 tried to keep the trigger alive and clamp
///   only the setters — it frosted on every resign-key again: the trigger's
///   fog reaches the renderer through internal direct writes the clamps do
///   not intercept. The trigger has no sampling duty worth keeping; see below.)
/// - `assertFresh(_:)` re-asserts sampling freshness at the edges that break
///   it — launch, un-hide, screen change, wake — and **only** those. Key
///   transitions are deliberately NOT edges here (v2 regression: rebuilding
///   the material while unfocused re-initializes it straight into the fogged
///   treatment). The material teardown/rebuild is the deliberate equivalent
///   of "drag to another screen and back", plus a delayed second pass for
///   the async capture registration.
enum GlassKeeper {
    // MARK: Install (fog trigger dead, fog valves pinned shut)

    static func install() {
        // The key-state brain is the FOG TRIGGER: on resign-key it pushes the
        // subdued treatment (via direct internal writes the setter clamps may
        // not intercept — v2 proved this by regression). Kill it. Sampling
        // re-registration does NOT depend on it: the cross-screen-drag cure is
        // the material teardown/rebuild in `apply(_:)`, which we invoke
        // ourselves at the sampling edges.
        neutralizeNoArg("_windowChangedKeyState")
        // Belt and suspenders: pin the fog setters too.
        clampSetter("set_subduedState:", ivar: "_subduedState")
        clampSetter("set_scrimState:", ivar: "_scrimState")
        // `set_interactionState:` is hover behaviour, not fog — untouched.
    }

    private static func neutralizeNoArg(_ selName: String) {
        let sel = NSSelectorFromString(selName)
        guard let method = class_getInstanceMethod(NSGlassEffectView.self, sel) else { return }
        let imp = imp_implementationWithBlock({ (_: AnyObject) in } as @convention(block) (AnyObject) -> Void)
        method_setImplementation(method, imp)
    }

    private static func clampSetter(_ selName: String, ivar: String) {
        let sel = NSSelectorFromString(selName)
        guard let method = class_getInstanceMethod(NSGlassEffectView.self, sel) else { return }
        let imp = imp_implementationWithBlock({ obj, _ in
            GlassKeeper.writeScalar(obj, ivar: ivar, value: 0)
        } as @convention(block) (AnyObject, Int) -> Void)
        method_setImplementation(method, imp)
    }

    // MARK: Invariant assertion (fresh sampling + valves shut)

    /// Re-assert the transparent invariant on `glass`. Call at every edge
    /// that can desync the material: becoming visible, screen change, wake,
    /// key transitions.
    @MainActor
    static func assertFresh(_ glass: NSGlassEffectView) {
        apply(glass)
        // WindowServer backdrop registration is asynchronous — assert again
        // once it has settled (covers the launch / un-hide race).
        Task { @MainActor [weak glass] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let glass, !glass.isHidden, glass.window?.isVisible == true else { return }
            apply(glass)
        }
    }

    @MainActor
    private static func apply(_ glass: NSGlassEffectView) {
        // 1) Direct ivar clamp — covers internal writes that bypass setters.
        writeScalar(glass, ivar: "_subduedState", value: 0)
        writeScalar(glass, ivar: "_scrimState", value: 0)
        // 2) Material teardown/rebuild via the style setter: the same rebuild
        //    a cross-screen drag provokes, which re-registers backdrop
        //    sampling. (The style setter resets cornerRadius — re-apply all.)
        glass.style = .regular
        glass.style = .clear
        glass.cornerRadius = Theme.cornerRadius
        glass.wantsLayer = true
        glass.layer?.masksToBounds = true
        glass.layer?.cornerRadius = Theme.cornerRadius
        glass.needsDisplay = true
    }

    // MARK: Int64-typed ivar writes (type encodings `q`/`B`, probed on 26.3)

    fileprivate static func writeScalar(_ obj: AnyObject, ivar name: String, value: Int64) {
        guard let ivar = class_getInstanceVariable(type(of: obj), name),
              let encPtr = ivar_getTypeEncoding(ivar) else { return }
        let enc = String(cString: encPtr)
        let p = Unmanaged.passUnretained(obj).toOpaque().advanced(by: ivar_getOffset(ivar))
        switch enc.first {
        case "B", "C", "c": p.assumingMemoryBound(to: UInt8.self).pointee = UInt8(value)
        case "s":            p.assumingMemoryBound(to: Int16.self).pointee = Int16(value)
        case "S":            p.assumingMemoryBound(to: UInt16.self).pointee = UInt16(value)
        case "i":            p.assumingMemoryBound(to: Int32.self).pointee = Int32(value)
        case "I":            p.assumingMemoryBound(to: UInt32.self).pointee = UInt32(value)
        case "l", "q":       p.assumingMemoryBound(to: Int64.self).pointee = value
        case "L", "Q":       p.assumingMemoryBound(to: UInt64.self).pointee = UInt64(value)
        default: break
        }
    }
}

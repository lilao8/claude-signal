import AppKit
import Foundation

/// Thin wrapper over the private `DFRFoundation` Control-Strip API.
///
/// Verified working on macOS 14.6 (2019 MacBook Pro) by a spike. Uses runtime
/// `dlopen`/`dlsym` so there is no link-time dependency on a private framework,
/// and degrades gracefully (every call becomes a no-op) on machines where the
/// symbols are absent — e.g. Apple Silicon Macs without a Touch Bar. This keeps
/// all the private-API surface in one isolated, well-labeled place.
enum DFRControlStrip {
    private typealias SetPresenceFn = @convention(c) (NSString, ObjCBool) -> Void

    /// Resolved once. nil if the private framework/symbol isn't available here.
    private static let setPresence: SetPresenceFn? = {
        // Resolve once; the dlopen handle is intentionally never dlclose'd — the framework
        // stays loaded for the process lifetime (dlclose'ing a system framework is risky).
        let path = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation"
        guard let handle = dlopen(path, RTLD_NOW),
              let sym = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier")
        else { return nil }
        return unsafeBitCast(sym, to: SetPresenceFn.self)
    }()

    private static let addSystemTraySel = NSSelectorFromString("addSystemTrayItem:")

    /// Whether the persistent Control-Strip API is usable on this machine.
    /// Resolved once — availability is invariant for the process lifetime.
    static let isAvailable: Bool = setPresence != nil && NSTouchBarItem.responds(to: addSystemTraySel)

    /// Register `item` as a persistent Control-Strip item (always visible,
    /// independent of the focused app). No-op if the private API is unavailable.
    @MainActor
    static func add(_ item: NSTouchBarItem) {
        guard isAvailable else { return }
        NSTouchBarItem.perform(addSystemTraySel, with: item)
        setPresence?(item.identifier.rawValue as NSString, true)
    }
}

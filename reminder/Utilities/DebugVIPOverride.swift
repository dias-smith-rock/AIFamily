import Foundation

#if DEBUG
/// DEBUG-only local override so Settings can force VIP without StoreKit / cloud entitlement.
enum DebugVIPOverride {
    static let defaultsKey = "debug.forceVIPEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
}
#endif

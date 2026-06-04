import Foundation

/// 应用内「后台定位」开关；默认开启。关闭后仅保留使用期间单次定位（位置 Tab / 回前台）。
enum BackgroundLocationPreferences {
    static let storageKey = "backgroundLocationEnabled"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [storageKey: true])
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true
    }
}

import Foundation

enum RevenueCatConfiguration {
    /// RevenueCat Public API Key（iOS）。在 Dashboard → API Keys → App-specific keys 获取。
    static var publicAPIKey: String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, trimmed.isEmpty == false, trimmed.contains("REPLACE") == false else {
            return nil
        }
        return trimmed
    }

    /// RevenueCat Dashboard → Entitlements 标识符（与 Offering 绑定）
    static let premiumEntitlementID = "premium"

    /// RevenueCat Dashboard → Offerings 标识符（全小写 `current`，并勾选为 Current offering）
    static let defaultOfferingIdentifier = "current"

    /// 部分项目 Current offering 误设为 `default` 时的兼容回退
    static let legacyOfferingIdentifier = "default"
}

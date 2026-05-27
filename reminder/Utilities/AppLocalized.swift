import Foundation
import SwiftUI

/// 仅在 **非 SwiftUI View**（ViewModel、格式化工具、异步逻辑）中解析 String Catalog。
/// View 层请使用 `Text("键")`、`TextField("键", ...)` 等原生 API，并依赖根节点的 `\.locale` 注入。
enum AppLocalized {
    static func string(_ key: String, locale: Locale) -> String {
        String(localized: String.LocalizationValue(key), bundle: .main, locale: locale)
    }

    /// ViewModel / Service 等非 View 上下文：跟随应用内语言设置解析 String Catalog。
    @MainActor
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: AppSettingsManager.shared.appLocale)
    }

    /// 通知等 `nonisolated` 上下文：从 `UserDefaults` 读取 `app_language` 后解析。
    nonisolated static func localizedSync(_ key: String.LocalizationValue) -> String {
        let raw = UserDefaults.standard.string(forKey: "app_language") ?? AppLanguage.system.rawValue
        let language = AppLanguage(rawValue: raw) ?? .system
        return String(localized: key, locale: language.locale)
    }
}

import Foundation
import SwiftUI

/// 仅在 **非 SwiftUI View**（ViewModel、格式化工具、异步逻辑）中解析 String Catalog。
/// View 层请使用 `Text(L10n.….localized)` 并依赖根节点的 `\.locale` 注入。
enum AppLocalized {
    static func string(_ key: String, table: L10n.Table = .common, locale: Locale) -> String {
        String(
            localized: String.LocalizationValue(key),
            table: table.rawValue,
            bundle: .main,
            locale: locale
        )
    }

    static func string(_ entry: L10n.Entry, locale: Locale) -> String {
        entry.string(locale: locale)
    }

    /// ViewModel / Service 等非 View 上下文：跟随应用内语言设置解析 String Catalog。
    @MainActor
    static func localized(_ key: String, table: L10n.Table = .common) -> String {
        string(key, table: table, locale: AppSettingsManager.shared.appLocale)
    }

    @MainActor
    static func localized(_ entry: L10n.Entry) -> String {
        entry.string()
    }

    /// 通知等 `nonisolated` 上下文：从 `UserDefaults` 读取 `app_language` 后解析。
    nonisolated static func localizedSync(_ key: String, table: L10n.Table = .common) -> String {
        let raw = UserDefaults.standard.string(forKey: "app_language") ?? ""
        let language: AppLanguage = raw.isEmpty || raw == "system"
            ? .system
            : (AppLanguage(rawValue: raw) ?? .system)
        return string(key, table: table, locale: language.locale)
    }

    nonisolated static func localizedSync(_ entry: L10n.Entry) -> String {
        localizedSync(entry.key, table: entry.table)
    }
}

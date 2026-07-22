import Foundation
import SwiftUI

/// 仅在 **非 SwiftUI View**（ViewModel、格式化工具、异步逻辑）中解析 String Catalog。
/// View 层请使用 `Text(L10n.….localized)` 并依赖根节点的 `\.locale` 注入。
enum AppLocalized {
    static func string(_ key: String, table: L10n.Table = .common, locale: Locale) -> String {
        // 应用内手动选语言时，优先从对应 `*.lproj` 取文案。
        // 仅依赖 `String(localized:locale:)` 在部分系统上仍会回落到系统语言。
        if let bundle = localizationBundle(for: locale) {
            let value = bundle.localizedString(forKey: key, value: "\u{0}", table: table.rawValue)
            if value != "\u{0}", value.isEmpty == false {
                return value
            }
        }
        return String(
            localized: String.LocalizationValue(key),
            table: table.rawValue,
            bundle: .main,
            locale: locale
        )
    }

    /// 按 locale 找到 Bundle 内对应语言包（支持 `zh-Hans` / `zh_CN` 等变体）。
    private static func localizationBundle(for locale: Locale) -> Bundle? {
        var candidates: [String] = [locale.identifier]
        if let languageCode = locale.language.languageCode?.identifier {
            candidates.append(languageCode)
            if let script = locale.language.script?.identifier {
                candidates.append("\(languageCode)-\(script)")
            }
            if let region = locale.region?.identifier {
                candidates.append("\(languageCode)-\(region)")
                candidates.append("\(languageCode)_\(region)")
            }
        }
        candidates.append(contentsOf: [
            locale.identifier.replacingOccurrences(of: "_", with: "-"),
            locale.identifier.replacingOccurrences(of: "-", with: "_"),
        ])

        let unique = candidates.reduce(into: [String]()) { result, item in
            if result.contains(item) == false { result.append(item) }
        }

        for id in unique {
            if let path = Bundle.main.path(forResource: id, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }

        for available in Bundle.main.localizations {
            if unique.contains(where: { available.caseInsensitiveCompare($0) == .orderedSame }),
               let path = Bundle.main.path(forResource: available, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return nil
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

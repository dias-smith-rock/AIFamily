import Foundation
import SwiftUI

/// Type-safe accessors for split String Catalog tables (`Common`, `Settings`, …).
enum L10n {
    enum Table: String {
        case common = "Common"
        case settings = "Settings"
        case auth = "Auth"
        case schedule = "Schedule"
        case family = "Family"
        case location = "Location"
        case vip = "VIP"
        case todo = "Todo"
        case feedback = "Feedback"
        case assistant = "Assistant"
        case ledger = "Ledger"
    }

    struct Entry {
        let key: String
        let table: Table

        /// SwiftUI 文案：保留 catalog key + table，由 `\.locale` 环境在渲染时解析。
        var localized: LocalizedStringResource {
            LocalizedStringResource(
                String.LocalizationValue(key),
                table: table.rawValue,
                bundle: .main
            )
        }

        /// 仍需 `LocalizedStringKey` 的旧 API（无 table 支持，仅作兼容）。
        var localizedKey: LocalizedStringKey {
            LocalizedStringKey(key)
        }

        func string(locale: Locale) -> String {
            String(
                localized: String.LocalizationValue(key),
                table: table.rawValue,
                bundle: .main,
                locale: locale
            )
        }

        @MainActor
        func string() -> String {
            string(locale: AppSettingsManager.shared.appLocale)
        }

        func formatted(locale: Locale, _ arguments: CVarArg...) -> String {
            withVaList(arguments) { pointer in
                NSString(format: string(locale: locale), locale: locale, arguments: pointer) as String
            }
        }

        @MainActor
        func formatted(_ arguments: CVarArg...) -> String {
            formatted(locale: AppSettingsManager.shared.appLocale, arguments)
        }
    }

    static func key(_ key: String, table: Table) -> LocalizedStringResource {
        Entry(key: key, table: table).localized
    }
}

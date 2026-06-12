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
    }

    struct Entry {
        let key: String
        let table: Table

        var localized: LocalizedStringKey {
            L10n.key(key, table: table)
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

    static func key(_ key: String, table: Table) -> LocalizedStringKey {
        LocalizedStringKey(String.LocalizationValue(key), table: table.rawValue)
    }
}

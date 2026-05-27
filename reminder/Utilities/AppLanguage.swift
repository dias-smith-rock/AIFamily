import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case spanish = "es"
    case portuguese = "pt"
    case arabic = "ar"
    case hindi = "hi"
    case french = "fr"
    case tamil = "ta"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .system: return String(localized: "跟随系统")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .spanish: return "Español"
        case .portuguese: return "Português"
        case .arabic: return "العربية"
        case .hindi: return "हिन्दी"
        case .french: return "Français"
        case .tamil: return "தமிழ்"
        }
    }

    var locale: Locale {
        if self == .system { return Locale.current }
        return Locale(identifier: rawValue)
    }

    var layoutDirection: LayoutDirection {
        if self == .arabic { return .rightToLeft }
        if self == .system {
            return Locale.current.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
        }
        return .leftToRight
    }
}

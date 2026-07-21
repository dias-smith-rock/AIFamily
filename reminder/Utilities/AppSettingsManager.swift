import SwiftUI
import Combine

enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// UI 展示用（键与 String Catalog 一致，勿使用 `rawValue`）。
    var localizedName: LocalizedStringResource {
        switch self {
        case .system: L10n.Common.followSystem.localized
        case .light: L10n.Common.lightMode.localized
        case .dark: L10n.Common.darkMode.localized
        }
    }

    /// 与 `localizedName` 相同；设置页列表等沿用此命名。
    var settingsTitleKey: LocalizedStringResource { localizedName }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppSettingsManager: ObservableObject {
    static let shared = AppSettingsManager()

    @AppStorage("app_appearance")
    private var appearanceStorage = AppAppearance.system.rawValue

    @AppStorage("app_text_size_tier")
    private var textSizeTierStorage = AppTextSize.standard.rawValue

    @AppStorage("app_language")
    private var languageStorage = ""

    @AppStorage("ledger_display_currency")
    private var ledgerDisplayCurrencyStorage = LedgerCurrency.defaultCode

    var appearance: AppAppearance {
        get { AppAppearance(rawValue: appearanceStorage) ?? .system }
        set {
            objectWillChange.send()
            appearanceStorage = newValue.rawValue
        }
    }

    var appTextSize: AppTextSize {
        get { AppTextSize(rawValue: textSizeTierStorage) ?? .standard }
        set {
            objectWillChange.send()
            textSizeTierStorage = newValue.rawValue
        }
    }

    var selectedLanguage: AppLanguage {
        get { Self.resolvedLanguage(from: languageStorage) }
        set {
            objectWillChange.send()
            languageStorage = newValue == .system ? "" : newValue.rawValue
        }
    }

    /// Wallet / 报表展示用货币（ISO 4217）；非法值回退 HKD。
    var ledgerDisplayCurrency: String {
        get { LedgerCurrency.normalized(ledgerDisplayCurrencyStorage) }
        set {
            objectWillChange.send()
            ledgerDisplayCurrencyStorage = LedgerCurrency.normalized(newValue)
        }
    }

    /// 用户是否在应用内手动指定了语言（非跟随系统）。
    var overridesAppLocale: Bool {
        selectedLanguage != .system
    }

    /// ViewModel / 无障碍等需要显式 `Locale` 时使用；跟随系统时返回 `Locale.current`。
    var appLocale: Locale {
        selectedLanguage.locale
    }

    private static func resolvedLanguage(from storage: String) -> AppLanguage {
        if storage.isEmpty || storage == "system" {
            return .system
        }
        return AppLanguage(rawValue: storage) ?? .system
    }

    var layoutDirection: LayoutDirection {
        selectedLanguage.layoutDirection
    }

    var colorScheme: ColorScheme? {
        appearance.colorScheme
    }

    var dynamicTypeSize: DynamicTypeSize {
        appTextSize.dynamicTypeSize
    }

    private init() {}
}

#if canImport(UIKit)
import UIKit

enum SystemSettingsHelper {
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
#endif

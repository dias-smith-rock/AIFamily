import SwiftUI
import Combine

enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// UI 展示用（键与 `Localizable.xcstrings` 一致，勿使用 `rawValue`）。
    var localizedName: LocalizedStringKey {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色模式"
        case .dark: "深色模式"
        }
    }

    /// 与 `localizedName` 相同；设置页列表等沿用此命名。
    var settingsTitleKey: LocalizedStringKey { localizedName }

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
    private var languageStorage = AppLanguage.system.rawValue

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
        get { AppLanguage(rawValue: languageStorage) ?? .system }
        set {
            objectWillChange.send()
            languageStorage = newValue.rawValue
        }
    }

    /// 与 `@AppStorage("app_language")` 同步；供 `WeFamilyApp` 注入 `\.locale`，驱动全应用 String Catalog 解析。
    var appLocale: Locale {
        selectedLanguage.locale
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

import SwiftUI
import Combine

enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var settingsTitleKey: LocalizedStringKey {
        switch self {
        case .system: return "Follow System"
        case .light: return "Light Mode"
        case .dark: return "Dark Mode"
        }
    }

    var settingsLocalizationKey: String {
        switch self {
        case .system: return "Follow System"
        case .light: return "Light Mode"
        case .dark: return "Dark Mode"
        }
    }

    func valueTitle(locale: Locale) -> String {
        AppLocalized.string(settingsLocalizationKey, locale: locale)
    }

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

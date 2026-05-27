import SwiftUI

extension View {
    /// 仅当用户在应用内手动选择语言时覆盖 `\.locale`；否则跟随 iOS 系统。
    @ViewBuilder
    func appLocaleEnvironment(using settings: AppSettingsManager) -> some View {
        if settings.overridesAppLocale {
            environment(\.locale, settings.selectedLanguage.locale)
        } else {
            self
        }
    }
}

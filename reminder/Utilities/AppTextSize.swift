import SwiftUI

enum AppTextSize: Int, CaseIterable, Identifiable, Codable {
    case tiny = 0
    case small = 1
    case standard = 2
    case large = 3
    case extraLarge = 4

    var id: Int { rawValue }

    /// UI 展示用（键与 String Catalog 一致）。
    var title: LocalizedStringKey {
        switch self {
        case .tiny: L10n.Common.tiny.localized
        case .small: L10n.Common.small.localized
        case .standard: L10n.Common.standard.localized
        case .large: L10n.Common.large.localized
        case .extraLarge: L10n.Common.huge.localized
        }
    }

    /// VoiceOver 等需要 `String` 的上下文。
    func accessibilityTitle(locale: Locale) -> String {
        String(localized: String.LocalizationValue(accessibilityCatalogKey), bundle: .main, locale: locale)
    }

    private var accessibilityCatalogKey: String {
        switch self {
        case .tiny: L10n.Common.tiny.key
        case .small: L10n.Common.small.key
        case .standard: L10n.Common.standard.key
        case .large: L10n.Common.large.key
        case .extraLarge: L10n.Common.huge.key
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .tiny: return .small
        case .small: return .medium
        case .standard: return .large
        case .large: return .xLarge
        case .extraLarge: return .xxLarge
        }
    }

    static var defaultTier: AppTextSize { .standard }

    static func fromSliderIndex(_ index: Int) -> AppTextSize {
        AppTextSize(rawValue: index) ?? .standard
    }
}

// MARK: - Global font modifier

private struct AppTextSizeModifier: ViewModifier {
    @AppStorage("app_text_size_tier")
    private var textSizeTierRaw = AppTextSize.standard.rawValue

    private var textSize: AppTextSize {
        AppTextSize(rawValue: textSizeTierRaw) ?? .standard
    }

    func body(content: Content) -> some View {
        content.dynamicTypeSize(textSize.dynamicTypeSize)
    }
}

extension View {
    func applyAppTextSize() -> some View {
        modifier(AppTextSizeModifier())
    }
}

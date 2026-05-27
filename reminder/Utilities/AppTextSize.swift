import SwiftUI

enum AppTextSize: Int, CaseIterable, Identifiable, Codable {
    case tiny = 0
    case small = 1
    case standard = 2
    case large = 3
    case extraLarge = 4

    var id: Int { rawValue }

    /// UI 展示用（键与 `Localizable.xcstrings` 一致）。
    var title: LocalizedStringKey {
        switch self {
        case .tiny: "极小"
        case .small: "较小"
        case .standard: "标准"
        case .large: "较大"
        case .extraLarge: "特大"
        }
    }

    /// VoiceOver 等需要 `String` 的上下文。
    func accessibilityTitle(locale: Locale) -> String {
        String(localized: String.LocalizationValue(accessibilityCatalogKey), bundle: .main, locale: locale)
    }

    private var accessibilityCatalogKey: String {
        switch self {
        case .tiny: "极小"
        case .small: "较小"
        case .standard: "标准"
        case .large: "较大"
        case .extraLarge: "特大"
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

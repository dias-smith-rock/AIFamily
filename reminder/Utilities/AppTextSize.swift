import SwiftUI

enum AppTextSize: Int, CaseIterable, Identifiable, Codable {
    case tiny = 0
    case small = 1
    case standard = 2
    case large = 3
    case extraLarge = 4

    var id: Int { rawValue }

    var localizationKey: String {
        switch self {
        case .tiny: return "极小"
        case .small: return "较小"
        case .standard: return "标准"
        case .large: return "较大"
        case .extraLarge: return "特大"
        }
    }

    func title(locale: Locale) -> String {
        AppLocalized.string(localizationKey, locale: locale)
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

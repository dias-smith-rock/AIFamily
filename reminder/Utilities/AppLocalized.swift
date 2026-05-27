import Foundation
import SwiftUI

/// 使用应用内选择的 `Locale` 解析 String Catalog（避免 `String(localized:)` 在非 View 上下文跟随系统语言）。
enum AppLocalized {
    static func string(_ key: String, locale: Locale) -> String {
        String(localized: String.LocalizationValue(key), bundle: .main, locale: locale)
    }
}

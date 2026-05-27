import Foundation
import SwiftUI

/// 仅在 **非 SwiftUI View**（ViewModel、格式化工具、异步逻辑）中解析 String Catalog。
/// View 层请使用 `Text("键")`、`TextField("键", ...)` 等原生 API，并依赖根节点的 `\.locale` 注入。
enum AppLocalized {
    static func string(_ key: String, locale: Locale) -> String {
        String(localized: String.LocalizationValue(key), bundle: .main, locale: locale)
    }
}

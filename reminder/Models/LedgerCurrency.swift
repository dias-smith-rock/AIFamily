import Foundation

/// 记账可选 / 显示货币白名单（与记一笔表单对齐）。
enum LedgerCurrency: String, CaseIterable, Identifiable, Sendable {
    case hkd = "HKD"
    case cny = "CNY"
    case usd = "USD"
    case eur = "EUR"
    case jpy = "JPY"

    var id: String { rawValue }

    var code: String { rawValue }

    /// 设置列表副标题（英文码 + 本地化名由系统 Locale 解析）。
    var displayName: String {
        Locale.current.localizedString(forCurrencyCode: rawValue) ?? rawValue
    }

    static let defaultCode = LedgerCurrency.hkd.rawValue

    static var allCodes: [String] { allCases.map(\.rawValue) }

    static func normalized(_ code: String) -> String {
        let upper = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if allCodes.contains(upper) { return upper }
        return defaultCode
    }
}

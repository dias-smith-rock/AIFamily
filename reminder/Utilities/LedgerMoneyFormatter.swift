import Foundation

enum LedgerMoneyFormatter {
    /// 按 ISO 4217 格式化为带货币符号的金额（如 `HK$243`、`¥243`）。
    static func string(
        _ amount: Double,
        currencyCode: String,
        locale: Locale = .current
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = LedgerCurrency.normalized(currencyCode)
        formatter.locale = locale
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount))
            ?? "\(LedgerCurrency.normalized(currencyCode)) \(amount.formatted(.number.precision(.fractionLength(0...2))))"
    }
}

import Foundation
import SwiftUI

/// 公账预设分类/标签：`preset_key` → Ledger catalog 文案。
enum LedgerPresetLocalization {
    enum ResolvePath: String, Sendable {
        case presetKey
        case englishNameFallback
        case rawName
    }

    struct ResolveOutcome: Sendable {
        let displayName: String
        let path: ResolvePath
        let catalogValue: String?
        let presetKey: String?
    }

    static func name(forPresetKey key: String, locale: Locale) -> String? {
        guard knownPresetKeys.contains(key) else { return nil }
        return AppLocalized.string(key, table: .ledger, locale: locale)
    }

    static func localizedNameResource(forPresetKey key: String) -> LocalizedStringResource? {
        guard knownPresetKeys.contains(key) else { return nil }
        return L10n.Entry(key: key, table: .ledger).localized
    }

    /// 解析展示名：优先 `preset_key`，否则用英文种子名回退映射（兼容旧数据 `preset_key` 为空）。
    static func resolve(_ category: ExpenseCategory, locale: Locale) -> ResolveOutcome {
        if let presetKey = category.presetKey?.nilIfEmpty,
           let localized = name(forPresetKey: presetKey, locale: locale) {
            return ResolveOutcome(
                displayName: localized,
                path: .presetKey,
                catalogValue: localized,
                presetKey: presetKey
            )
        }

        if let fallbackKey = presetKey(forEnglishName: category.name),
           let localized = name(forPresetKey: fallbackKey, locale: locale) {
            return ResolveOutcome(
                displayName: localized,
                path: .englishNameFallback,
                catalogValue: localized,
                presetKey: fallbackKey
            )
        }

        return ResolveOutcome(
            displayName: category.name,
            path: .rawName,
            catalogValue: nil,
            presetKey: category.presetKey
        )
    }

    static func resolve(_ tag: CategoryTag, locale: Locale) -> ResolveOutcome {
        if let presetKey = tag.presetKey?.nilIfEmpty,
           let localized = name(forPresetKey: presetKey, locale: locale) {
            return ResolveOutcome(
                displayName: localized,
                path: .presetKey,
                catalogValue: localized,
                presetKey: presetKey
            )
        }

        if let fallbackKey = presetKey(forEnglishName: tag.name),
           let localized = name(forPresetKey: fallbackKey, locale: locale) {
            return ResolveOutcome(
                displayName: localized,
                path: .englishNameFallback,
                catalogValue: localized,
                presetKey: fallbackKey
            )
        }

        return ResolveOutcome(
            displayName: tag.name,
            path: .rawName,
            catalogValue: nil,
            presetKey: tag.presetKey
        )
    }

    static func resolvedPresetKey(for category: ExpenseCategory) -> String? {
        category.presetKey?.nilIfEmpty ?? presetKey(forEnglishName: category.name)
    }

    static func resolvedPresetKey(for tag: CategoryTag) -> String? {
        tag.presetKey?.nilIfEmpty ?? presetKey(forEnglishName: tag.name)
    }

    static func presetKey(forEnglishName name: String) -> String? {
        englishNameToPresetKey[name]
    }

    static let knownPresetKeys: Set<String> = [
        "cat_dining",
        "cat_transport",
        "cat_shopping",
        "cat_sports",
        "cat_travel",
        "cat_repairs",
        "cat_income",
        "cat_refunds",
        "tag_breakfast",
        "tag_lunch",
        "tag_dinner",
        "tag_takeout",
        "tag_coffee",
        "tag_public_transit",
        "tag_taxi",
        "tag_gas",
        "tag_parking",
        "tag_groceries",
        "tag_clothing",
        "tag_electronics",
        "tag_gym",
        "tag_sports_equipment",
        "tag_flights_trains",
        "tag_hotels",
        "tag_appliance_repair",
        "tag_plumbing",
        "tag_salary",
        "tag_bonus",
        "tag_side_hustle",
        "tag_merchant_refund",
        "tag_deposit_return",
    ]

    /// 与 seed SQL 中的英文 `name` 对齐，用于 `preset_key` 缺失时的兼容。
    private static let englishNameToPresetKey: [String: String] = [
        "Dining": "cat_dining",
        "Transportation": "cat_transport",
        "Shopping": "cat_shopping",
        "Sports & Fitness": "cat_sports",
        "Travel": "cat_travel",
        "Home Repairs": "cat_repairs",
        "Salary & Income": "cat_income",
        "Refunds": "cat_refunds",
        "Breakfast": "tag_breakfast",
        "Lunch": "tag_lunch",
        "Dinner": "tag_dinner",
        "Takeout": "tag_takeout",
        "Coffee & Drinks": "tag_coffee",
        "Public Transit": "tag_public_transit",
        "Taxi / Rideshare": "tag_taxi",
        "Gas / Fuel": "tag_gas",
        "Parking": "tag_parking",
        "Groceries": "tag_groceries",
        "Clothing": "tag_clothing",
        "Electronics": "tag_electronics",
        "Gym Membership": "tag_gym",
        "Sports Equipment": "tag_sports_equipment",
        "Flights & Trains": "tag_flights_trains",
        "Hotels": "tag_hotels",
        "Appliance Repair": "tag_appliance_repair",
        "Plumbing & Hardware": "tag_plumbing",
        "Base Salary": "tag_salary",
        "Bonus": "tag_bonus",
        "Side Hustle": "tag_side_hustle",
        "Merchant Refund": "tag_merchant_refund",
        "Deposit Return": "tag_deposit_return",
    ]
}

extension ExpenseCategory {
    func localizedName(locale: Locale) -> String {
        LedgerPresetLocalization.resolve(self, locale: locale).displayName
    }

    func localizedDisplayLabel(locale: Locale) -> String {
        "\(icon) \(localizedName(locale: locale))"
    }

    /// SwiftUI 渲染用：与「支出/收入」同路径，跟随 `\.locale`。
    var localizedNameResource: LocalizedStringResource? {
        guard let key = LedgerPresetLocalization.resolvedPresetKey(for: self) else { return nil }
        return LedgerPresetLocalization.localizedNameResource(forPresetKey: key)
    }
}

extension CategoryTag {
    func localizedName(locale: Locale) -> String {
        LedgerPresetLocalization.resolve(self, locale: locale).displayName
    }

    var localizedNameResource: LocalizedStringResource? {
        guard let key = LedgerPresetLocalization.resolvedPresetKey(for: self) else { return nil }
        return LedgerPresetLocalization.localizedNameResource(forPresetKey: key)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

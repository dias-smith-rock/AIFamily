import Foundation
import os

/// 账本预设分类多语言诊断埋点：Console + os.Logger + Analytics + Crashlytics。
enum LedgerPresetLocalizationLogger {
    enum Step: String, Sendable {
        case dashboardProbe = "dashboard_probe"
        case categoryResolve = "category_resolve"
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.aifamilygroup.reminder",
        category: "LedgerPresetL10n"
    )

    nonisolated(unsafe) private(set) static var lastSummary: String = ""
    nonisolated(unsafe) private static var lastProbeSignature: String = ""

    /// 仪表盘出现分类网格时打一次探针（同 locale + 分类指纹去重）。
    @MainActor
    static func probeDashboard(
        categories: [ExpenseCategory],
        locale: Locale,
        householdId: UUID?,
        source: String
    ) {
        let signature = [
            locale.identifier,
            householdId?.uuidString.lowercased() ?? "nil",
            categories.map { "\($0.id.uuidString.lowercased()):\($0.presetKey ?? "nil"):\($0.name)" }.joined(separator: "|"),
        ].joined(separator: "#")
        guard signature != lastProbeSignature else { return }
        lastProbeSignature = signature

        let appLang = UserDefaults.standard.string(forKey: "app_language") ?? ""
        let expenseProbe = L10n.Ledger.expense.string(locale: locale)
        let diningProbe = LedgerPresetLocalization.name(forPresetKey: "cat_dining", locale: locale) ?? "nil"

        var missingPreset = 0
        var usedFallback = 0
        var stillEnglish = 0
        var samples: [String] = []

        for category in categories.prefix(8) {
            let outcome = LedgerPresetLocalization.resolve(category, locale: locale)
            if category.presetKey == nil || category.presetKey?.isEmpty == true {
                missingPreset += 1
            }
            if outcome.path == .englishNameFallback {
                usedFallback += 1
            }
            if outcome.displayName == category.name, category.name != outcome.catalogValue {
                stillEnglish += 1
            }
            samples.append(
                "\(category.name)|pk=\(category.presetKey ?? "nil")|path=\(outcome.path.rawValue)|out=\(outcome.displayName)|cat=\(outcome.catalogValue ?? "-")"
            )
            step(
                .categoryResolve,
                householdId: householdId,
                detail: samples.last ?? ""
            )
        }

        let detail = [
            "source=\(source)",
            "locale=\(locale.identifier)",
            "app_language=\(appLang.isEmpty ? "system" : appLang)",
            "system=\(Locale.current.identifier)",
            "cats=\(categories.count)",
            "missing_pk=\(missingPreset)",
            "fallback=\(usedFallback)",
            "still_en=\(stillEnglish)",
            "probe_expense=\(expenseProbe)",
            "probe_dining=\(diningProbe)",
            "bundle_zh=\(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj") != nil)",
            "samples=\(samples.joined(separator: " || "))",
        ].joined(separator: " ")

        step(.dashboardProbe, householdId: householdId, detail: detail)
        AnalyticsManager.log(
            event: .ledgerPresetL10n(
                step: Step.dashboardProbe.rawValue,
                detail: String(detail.prefix(100))
            )
        )
    }

    nonisolated static func step(
        _ step: Step,
        householdId: UUID? = nil,
        detail: String = ""
    ) {
        var parts: [String] = ["[LedgerPresetL10n]", "step=\(step.rawValue)"]
        if let householdId { parts.append("household_id=\(householdId.uuidString.lowercased())") }
        if detail.isEmpty == false { parts.append("detail=\(detail)") }
        let message = parts.joined(separator: " ")
        lastSummary = message
        logger.info("\(message, privacy: .public)")
        #if DEBUG
        print(message)
        #endif
        CrashReporting.log(message)
    }
}

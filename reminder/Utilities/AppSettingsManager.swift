import SwiftUI
import Combine

enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// UI 展示用（键与 String Catalog 一致，勿使用 `rawValue`）。
    var localizedName: LocalizedStringResource {
        switch self {
        case .system: L10n.Common.followSystem.localized
        case .light: L10n.Common.lightMode.localized
        case .dark: L10n.Common.darkMode.localized
        }
    }

    /// 与 `localizedName` 相同；设置页列表等沿用此命名。
    var settingsTitleKey: LocalizedStringResource { localizedName }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppSettingsManager: ObservableObject {
    static let shared = AppSettingsManager()

    @AppStorage("app_appearance")
    private var appearanceStorage = AppAppearance.system.rawValue

    @AppStorage("app_text_size_tier")
    private var textSizeTierStorage = AppTextSize.standard.rawValue

    @AppStorage("app_language")
    private var languageStorage = ""

    @AppStorage("ledger_display_currency")
    private var ledgerDisplayCurrencyStorage = LedgerCurrency.defaultCode

    @AppStorage(AppDisplayTimeZone.storageKey)
    private var displayTimeZoneStorage = ""

    @AppStorage("schedule_background_mode")
    private var scheduleBackgroundModeStorage = ScheduleBackgroundMode.systemDefault.rawValue

    @AppStorage("schedule_background_color_hex")
    private var scheduleBackgroundColorHexStorage = ""

    @AppStorage("schedule_background_image_fit")
    private var scheduleBackgroundImageFitStorage = ScheduleBackgroundImageFit.fill.rawValue

    /// 图片文件变更时递增，驱动 `SchedulePageBackgroundFill` 刷新。
    @Published private(set) var scheduleBackgroundRevision = 0

    var appearance: AppAppearance {
        get { AppAppearance(rawValue: appearanceStorage) ?? .system }
        set {
            objectWillChange.send()
            appearanceStorage = newValue.rawValue
        }
    }

    var appTextSize: AppTextSize {
        get { AppTextSize(rawValue: textSizeTierStorage) ?? .standard }
        set {
            objectWillChange.send()
            textSizeTierStorage = newValue.rawValue
        }
    }

    var selectedLanguage: AppLanguage {
        get { Self.resolvedLanguage(from: languageStorage) }
        set {
            objectWillChange.send()
            languageStorage = newValue == .system ? "" : newValue.rawValue
        }
    }

    /// Wallet / 报表展示用货币（ISO 4217）；非法值回退 HKD。
    var ledgerDisplayCurrency: String {
        get { LedgerCurrency.normalized(ledgerDisplayCurrencyStorage) }
        set {
            objectWillChange.send()
            ledgerDisplayCurrencyStorage = LedgerCurrency.normalized(newValue)
        }
    }

    /// `nil` = 跟随系统；否则为 IANA 时区 id。
    var displayTimeZoneIdentifier: String? {
        get {
            let trimmed = displayTimeZoneStorage.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        set {
            objectWillChange.send()
            if let newValue {
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                displayTimeZoneStorage = trimmed
            } else {
                displayTimeZoneStorage = ""
            }
        }
    }

    /// 日程展示 / 「今天」切日用的时区。
    var effectiveTimeZone: TimeZone {
        AppDisplayTimeZone.effectiveTimeZone
    }

    var effectiveCalendar: Calendar {
        AppDisplayTimeZone.calendar(for: effectiveTimeZone)
    }

    /// 设置行副标题。
    var displayTimeZoneSettingsValue: String {
        if displayTimeZoneIdentifier == nil {
            return AppLocalized.localized(L10n.Settings.timezoneFollowSystem)
        }
        return AppDisplayTimeZone.displayName(for: effectiveTimeZone, locale: appLocale)
    }

    /// 用户是否在应用内手动指定了语言（非跟随系统）。
    var overridesAppLocale: Bool {
        selectedLanguage != .system
    }

    /// ViewModel / 无障碍等需要显式 `Locale` 时使用；跟随系统时返回 `Locale.current`。
    var appLocale: Locale {
        selectedLanguage.locale
    }

    private static func resolvedLanguage(from storage: String) -> AppLanguage {
        if storage.isEmpty || storage == "system" {
            return .system
        }
        return AppLanguage(rawValue: storage) ?? .system
    }

    var layoutDirection: LayoutDirection {
        selectedLanguage.layoutDirection
    }

    var colorScheme: ColorScheme? {
        appearance.colorScheme
    }

    var dynamicTypeSize: DynamicTypeSize {
        appTextSize.dynamicTypeSize
    }

    // MARK: - Schedule page background（个人偏好）

    var scheduleBackgroundMode: ScheduleBackgroundMode {
        get { ScheduleBackgroundMode(rawValue: scheduleBackgroundModeStorage) ?? .systemDefault }
        set {
            objectWillChange.send()
            scheduleBackgroundModeStorage = newValue.rawValue
            scheduleBackgroundRevision &+= 1
        }
    }

    var scheduleBackgroundImageFit: ScheduleBackgroundImageFit {
        get { ScheduleBackgroundImageFit(rawValue: scheduleBackgroundImageFitStorage) ?? .fill }
        set {
            objectWillChange.send()
            scheduleBackgroundImageFitStorage = newValue.rawValue
            scheduleBackgroundRevision &+= 1
        }
    }

    /// 纯色模式下的 `#RRGGBB`；非法或空时回退系统背景。
    var scheduleBackgroundColorHex: String? {
        get {
            let trimmed = scheduleBackgroundColorHexStorage.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        set {
            objectWillChange.send()
            if let newValue, let hex = HouseholdColorStore.normalizedHex(newValue) {
                scheduleBackgroundColorHexStorage = hex
            } else {
                scheduleBackgroundColorHexStorage = ""
            }
            scheduleBackgroundRevision &+= 1
        }
    }

    func applyScheduleBackgroundColor(hex: String) {
        guard let normalized = HouseholdColorStore.normalizedHex(hex) else { return }
        objectWillChange.send()
        scheduleBackgroundColorHexStorage = normalized
        scheduleBackgroundModeStorage = ScheduleBackgroundMode.solidColor.rawValue
        scheduleBackgroundRevision &+= 1
    }

    func applyScheduleBackgroundCustomColor(_ color: Color) {
        guard let hex = HouseholdColorStore.token(fromCustomColor: color) else { return }
        applyScheduleBackgroundColor(hex: hex)
    }

    #if canImport(UIKit)
    @discardableResult
    func applyScheduleBackgroundImage(_ image: UIImage) -> Bool {
        guard ScheduleBackgroundStore.saveUIImage(image) else { return false }
        objectWillChange.send()
        scheduleBackgroundModeStorage = ScheduleBackgroundMode.image.rawValue
        scheduleBackgroundRevision &+= 1
        return true
    }

    @discardableResult
    func applyScheduleBackgroundImageData(_ data: Data) -> Bool {
        guard ScheduleBackgroundStore.saveImageData(data) else { return false }
        objectWillChange.send()
        scheduleBackgroundModeStorage = ScheduleBackgroundMode.image.rawValue
        scheduleBackgroundRevision &+= 1
        return true
    }
    #endif

    func clearScheduleBackgroundImage() {
        ScheduleBackgroundStore.clearImage()
        objectWillChange.send()
        if scheduleBackgroundMode == .image {
            if scheduleBackgroundColorHex != nil {
                scheduleBackgroundModeStorage = ScheduleBackgroundMode.solidColor.rawValue
            } else {
                scheduleBackgroundModeStorage = ScheduleBackgroundMode.systemDefault.rawValue
            }
        }
        scheduleBackgroundRevision &+= 1
    }

    func resetScheduleBackground() {
        ScheduleBackgroundStore.clearImage()
        objectWillChange.send()
        scheduleBackgroundModeStorage = ScheduleBackgroundMode.systemDefault.rawValue
        scheduleBackgroundColorHexStorage = ""
        scheduleBackgroundImageFitStorage = ScheduleBackgroundImageFit.fill.rawValue
        scheduleBackgroundRevision &+= 1
    }

    private init() {}
}

#if canImport(UIKit)
import UIKit

enum SystemSettingsHelper {
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
#endif

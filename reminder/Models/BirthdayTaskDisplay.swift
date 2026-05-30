import Foundation

// MARK: - 生日自动任务展示

/// 生日同步任务在库内仅存标题模板（含 `%@`）与 `target_profile_ids`；展示名实时解析。
enum BirthdayTaskDisplay {
    static let syncMarkerPrefix = "birthday_sync_profile:"
    static let autoDescriptionKey = "生日自动任务（年度循环）"

    enum Template: CaseIterable {
        case wishList
        case bookVenue
        case buyGift
        case confirmCake
        case setupAndPickup
        case celebrate

        var dayOffset: Int {
            switch self {
            case .wishList: return -30
            case .bookVenue: return -15
            case .buyGift: return -7
            case .confirmCake: return -3
            case .setupAndPickup: return -1
            case .celebrate: return 0
            }
        }

        /// String Catalog 中文 Key（含 `%@` 占位符）。
        var titleFormatKey: String {
            switch self {
            case .wishList: return "准备 %@ 的生日愿望清单"
            case .bookVenue: return "为 %@ 预订生日餐厅/场地"
            case .buyGift: return "购买 %@ 的生日礼物"
            case .confirmCake: return "确认 %@ 的生日蛋糕预订"
            case .setupAndPickup: return "布置现场并取回 %@ 的生日蛋糕"
            case .celebrate: return "陪伴 %@，祝生日快乐！"
            }
        }

        func matchesStoredTitle(_ title: String) -> Bool {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return false }
            if trimmed == titleFormatKey { return true }
            switch self {
            case .wishList:
                return trimmed.contains("生日愿望清单")
            case .bookVenue:
                return trimmed.contains("预订生日餐厅/场地")
            case .buyGift:
                return trimmed.contains("生日礼物") && trimmed.contains("购买")
            case .confirmCake:
                return trimmed.contains("生日蛋糕预订")
            case .setupAndPickup:
                return trimmed.contains("布置现场") && trimmed.contains("生日蛋糕")
            case .celebrate:
                return trimmed.contains("祝生日快乐")
            }
        }
    }

    static func isBirthdaySyncTask(_ task: FamilyTask) -> Bool {
        if task.originalPrompt?.hasPrefix(syncMarkerPrefix) == true {
            return true
        }
        let description = task.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return description == autoDescriptionKey
    }

    static func inferredTemplate(for task: FamilyTask) -> Template? {
        guard isBirthdaySyncTask(task) else { return nil }
        return Template.allCases.first { $0.matchesStoredTitle(task.title) }
    }

    static func resolvedTargetProfileId(for task: FamilyTask) -> UUID? {
        if let ids = task.targetProfileIds, let first = ids.first {
            return first
        }
        return task.targetProfileId
    }

    static func resolvedTargetDisplayName(
        for task: FamilyTask,
        profiles: [FamilyProfile]
    ) -> String? {
        guard let profileId = resolvedTargetProfileId(for: task) else { return nil }
        if let profile = profiles.first(where: { $0.id == profileId }) {
            return profile.displayName
        }
        let trimmedSubject = task.targetSubject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedSubject.isEmpty ? nil : trimmedSubject
    }

    static func resolvedTitle(
        for task: FamilyTask,
        profiles: [FamilyProfile],
        locale: Locale
    ) -> String {
        guard let template = inferredTemplate(for: task) else {
            return task.title
        }
        let name = resolvedTargetDisplayName(for: task, profiles: profiles)
            ?? MemberDisplayName.unknownFallback
        let format = AppLocalized.string(template.titleFormatKey, locale: locale)
        return String(format: format, locale: locale, arguments: [name])
    }
}

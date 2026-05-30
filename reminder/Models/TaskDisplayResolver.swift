import Foundation

// MARK: - 任务展示名 / 模板标题解析

/// 与 `target_profile_ids` 绑定的展示名、模板标题（含 `%@`）在 UI 层实时解析，禁止把 nickname 快照写入库。
enum TaskDisplayResolver {
    static func resolvedTitle(
        for task: FamilyTask,
        profiles: [FamilyProfile],
        locale: Locale
    ) -> String {
        if let template = BirthdayTaskDisplay.inferredTemplate(for: task) {
            let name = resolvedTargetDisplayName(for: task, profiles: profiles)
                ?? MemberDisplayName.unknownFallback
            let format = AppLocalized.string(template.titleFormatKey, locale: locale)
            return String(format: format, locale: locale, arguments: [name])
        }

        let trimmedTitle = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.contains("%@"),
           resolvedTargetProfileId(for: task) != nil,
           let name = resolvedTargetDisplayName(for: task, profiles: profiles) {
            let format = AppLocalized.string(trimmedTitle, locale: locale)
            return String(format: format, locale: locale, arguments: [name])
        }

        return task.title
    }

    static func resolvedTargetProfileId(for task: FamilyTask) -> UUID? {
        BirthdayTaskDisplay.resolvedTargetProfileId(for: task)
    }

    static func resolvedTargetDisplayName(
        for task: FamilyTask,
        profiles: [FamilyProfile]
    ) -> String? {
        BirthdayTaskDisplay.resolvedTargetDisplayName(for: task, profiles: profiles)
    }
}

extension FamilyTask {
    /// 任务是否通过 `target_profile_id(s)` 关联「为了谁」档案。
    var hasTargetProfileReference: Bool {
        if targetProfileId != nil { return true }
        guard let ids = targetProfileIds else { return false }
        return ids.isEmpty == false
    }

    /// 写入 Supabase 前：有关联档案时不持久化 `target_subject` 称呼快照。
    func sanitizedForPersistence() -> FamilyTask {
        guard hasTargetProfileReference else { return self }
        var sanitized = self
        sanitized.targetSubject = nil
        return sanitized
    }
}

#if canImport(Supabase)
import Supabase

enum TaskTargetSubjectMaintenance {
    /// 档案 nickname 变更后，清空仍挂在 `target_profile_ids` 上的旧 `target_subject` 快照。
    static func clearPersistedTargetSubject(
        for profileId: UUID,
        householdId: UUID
    ) async throws {
        let client = SupabaseManager.shared.client
        let hid = householdId.uuidString.lowercased()

        let rows: [FamilyTask] = try await client
            .from("tasks")
            .select()
            .eq("household_id", value: hid)
            .execute()
            .value

        let idsToClear = rows
            .filter { row in
                row.targetProfileIds?.contains(profileId) == true
                    && row.targetSubject?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
            .map(\.id)

        guard idsToClear.isEmpty == false else { return }

        let patch = TargetSubjectNullPatch()
        for taskId in idsToClear {
            _ = try await client
                .from("tasks")
                .update(patch)
                .eq("household_id", value: hid)
                .eq("id", value: taskId.uuidString.lowercased())
                .execute()
        }
    }
}

private struct TargetSubjectNullPatch: Encodable {
    enum CodingKeys: String, CodingKey {
        case targetSubject = "target_subject"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNil(forKey: .targetSubject)
    }
}
#endif

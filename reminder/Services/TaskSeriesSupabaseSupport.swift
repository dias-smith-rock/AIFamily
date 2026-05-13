import Foundation

#if canImport(Supabase)
import Supabase

/// 重复任务序列在 Supabase 上的拉取与批量删除（`parent_task_id` 实体化 + 旧 `group_id` 兼容）。
enum TaskSeriesSupabaseSupport {

    static func fetchSeriesTasks(
        householdId: UUID,
        grouping: FamilyTask.SeriesGrouping,
        dueOnOrAfter cutoff: Date
    ) async throws -> [FamilyTask] {
        let client = SupabaseManager.shared.client
        let hid = householdId.uuidString.lowercased()
        switch grouping {
        case .byParentRoot(let root):
            let rootLower = root.uuidString.lowercased()
            async let children: [FamilyTask] = client
                .from("tasks")
                .select()
                .eq("household_id", value: hid)
                .eq("parent_task_id", value: rootLower)
                .gte("due_date", value: cutoff)
                .execute()
                .value
            let mother: FamilyTask = try await client
                .from("tasks")
                .select()
                .eq("household_id", value: hid)
                .eq("id", value: rootLower)
                .single()
                .execute()
                .value
            let childRows = try await children
            return ([mother] + childRows).sorted {
                ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast)
            }
        case .byLegacyGroup(let gid):
            let gidLower = gid.uuidString.lowercased()
            let rows: [FamilyTask] = try await client
                .from("tasks")
                .select()
                .eq("household_id", value: hid)
                .eq("group_id", value: gidLower)
                .gte("due_date", value: cutoff)
                .execute()
                .value
            return rows.sorted {
                ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast)
            }
        }
    }

    static func deleteTasks(ids: [UUID]) async throws {
        let client = SupabaseManager.shared.client
        for id in ids {
            try await client
                .from("tasks")
                .delete()
                .eq("id", value: id.uuidString.lowercased())
                .execute()
        }
    }
}

#endif

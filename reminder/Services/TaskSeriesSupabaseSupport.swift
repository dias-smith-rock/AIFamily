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

    // MARK: - 周期规则变更：未来实例清理与再展开

    struct RecurrenceFieldSnapshot: Equatable {
        let rule: String?
        let interval: Int?
        let endDate: Date?

        static func normalized(
            rule: String?,
            interval: Int?,
            endDate: Date?
        ) -> RecurrenceFieldSnapshot {
            let trimmed = rule?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedRule = (trimmed?.isEmpty == false) ? trimmed : nil
            return RecurrenceFieldSnapshot(
                rule: normalizedRule,
                interval: interval,
                endDate: endDate
            )
        }

        static func normalized(from task: FamilyTask) -> RecurrenceFieldSnapshot {
            normalized(
                rule: task.recurrenceRule,
                interval: task.recurrenceInterval,
                endDate: task.recurrenceEndDate
            )
        }

        var isRecurring: Bool { rule != nil }
    }

    /// 母任务更新成功后，按旧/新周期规则同步未来子任务行。
    static func handleRecurrenceTransition(
        rootTaskId: UUID,
        householdId: UUID,
        oldSnapshot: RecurrenceFieldSnapshot,
        newSnapshot: RecurrenceFieldSnapshot,
        updatedMother: FamilyTask,
        fromDate: Date = Date()
    ) async throws {
        guard oldSnapshot != newSnapshot else { return }

        let oldRule = oldSnapshot.rule
        let newRule = newSnapshot.rule
        let oldIsRecurring = oldSnapshot.isRecurring
        let newIsRecurring = newSnapshot.isRecurring
        let scheduleChangedWithoutRuleChange = oldRule == newRule

        if oldIsRecurring == false && newIsRecurring {
            try await generateFutureInstances(
                mother: updatedMother,
                rootTaskId: rootTaskId,
                fromDate: fromDate
            )
            return
        }

        if oldIsRecurring && newIsRecurring == false {
            try await deleteFutureUncompletedInstances(
                rootTaskId: rootTaskId,
                householdId: householdId,
                fromDate: fromDate
            )
            return
        }

        if oldIsRecurring && newIsRecurring && (oldRule != newRule || scheduleChangedWithoutRuleChange) {
            try await deleteFutureUncompletedInstances(
                rootTaskId: rootTaskId,
                householdId: householdId,
                fromDate: fromDate
            )
            try await generateFutureInstances(
                mother: updatedMother,
                rootTaskId: rootTaskId,
                fromDate: fromDate
            )
        }
    }

    /// 删除 `parent_task_id == rootTaskId` 且 `due_date > fromDate` 且未完成的子任务；历史已完成行保留。
    static func deleteFutureUncompletedInstances(
        rootTaskId: UUID,
        householdId: UUID,
        fromDate: Date = Date()
    ) async throws {
        let client = SupabaseManager.shared.client
        let hid = householdId.uuidString.lowercased()
        let rootLower = rootTaskId.uuidString.lowercased()

        let rows: [FamilyTask] = try await client
            .from("tasks")
            .select()
            .eq("household_id", value: hid)
            .eq("parent_task_id", value: rootLower)
            .gt("due_date", value: fromDate)
            .execute()
            .value

        let idsToDelete = rows
            .filter { $0.status != .completed }
            .map(\.id)

        guard idsToDelete.isEmpty == false else { return }
        try await deleteTasks(ids: idsToDelete)
    }

    static func generateFutureInstances(
        mother: FamilyTask,
        rootTaskId: UUID,
        fromDate: Date = Date()
    ) async throws {
        guard mother.isRecurringSeriesMother || mother.id == rootTaskId else { return }
        guard RecurrenceFieldSnapshot.normalized(from: mother).isRecurring else { return }

        let children = await Task.detached(priority: .userInitiated) {
            RecurrenceEngine.generateInstances(from: mother, after: fromDate)
        }.value

        guard children.isEmpty == false else { return }

        let client = SupabaseManager.shared.client
        let now = Date()
        let creatorIdLowercased = mother.creatorId.uuidString.lowercased()
        let payloads = children.map { child in
            RecurrenceChildInsertPayload(
                id: child.id,
                householdId: mother.householdId,
                creatorId: creatorIdLowercased,
                parentTaskId: rootTaskId,
                involvedMemberIds: child.involvedMemberIds,
                targetProfileIds: child.targetProfileIds,
                title: child.title,
                description: child.description,
                status: child.status.rawValue,
                priority: child.priority.rawValue,
                dueDate: child.dueDate ?? mother.dueDate ?? now,
                endDatetime: child.endDatetime,
                durationMinutes: child.durationMinutes,
                isAllDay: child.isAllDay,
                reminderOffsets: child.reminderOffsets,
                estimatedCost: child.estimatedCost,
                backgroundColor: child.backgroundColor,
                emergencyPhone: child.emergencyPhone,
                locationData: child.locationData,
                createdAt: now,
                updatedAt: now
            )
        }

        _ = try await client
            .from("tasks")
            .insert(payloads)
            .execute()
    }

    static func fetchTask(id: UUID, householdId: UUID) async throws -> FamilyTask {
        let client = SupabaseManager.shared.client
        return try await client
            .from("tasks")
            .select()
            .eq("household_id", value: householdId.uuidString.lowercased())
            .eq("id", value: id.uuidString.lowercased())
            .single()
            .execute()
            .value
    }
}

private struct RecurrenceChildInsertPayload: Encodable {
    let id: UUID
    let householdId: UUID
    let creatorId: String
    let parentTaskId: UUID
    let involvedMemberIds: [UUID]?
    let targetProfileIds: [UUID]?
    let title: String
    let description: String?
    let status: String
    let priority: String
    let dueDate: Date
    let endDatetime: Date?
    let durationMinutes: Int
    let isAllDay: Bool
    let reminderOffsets: [Int]?
    let estimatedCost: Int?
    let backgroundColor: String?
    let emergencyPhone: String?
    let locationData: FamilyTask.LocationData?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case creatorId = "creator_id"
        case parentTaskId = "parent_task_id"
        case involvedMemberIds = "involved_member_ids"
        case targetProfileIds = "target_profile_ids"
        case title
        case description
        case status
        case priority
        case dueDate = "due_date"
        case endDatetime = "end_datetime"
        case durationMinutes = "duration_minutes"
        case isAllDay = "is_all_day"
        case recurrenceRule = "recurrence_rule"
        case recurrenceEndDate = "recurrence_end_date"
        case recurrenceInterval = "recurrence_interval"
        case reminderOffsets = "reminder_offsets"
        case estimatedCost = "estimated_cost"
        case backgroundColor = "background_color"
        case emergencyPhone = "emergency_phone"
        case locationData = "location_data"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(householdId, forKey: .householdId)
        try container.encode(creatorId, forKey: .creatorId)
        try container.encode(parentTaskId, forKey: .parentTaskId)
        if let involvedMemberIds {
            try container.encode(involvedMemberIds, forKey: .involvedMemberIds)
        } else {
            try container.encodeNil(forKey: .involvedMemberIds)
        }
        if let targetProfileIds {
            try container.encode(targetProfileIds, forKey: .targetProfileIds)
        } else {
            try container.encodeNil(forKey: .targetProfileIds)
        }
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(status, forKey: .status)
        try container.encode(priority, forKey: .priority)
        try container.encode(dueDate, forKey: .dueDate)
        if let endDatetime {
            try container.encode(endDatetime, forKey: .endDatetime)
        } else {
            try container.encodeNil(forKey: .endDatetime)
        }
        try container.encode(durationMinutes, forKey: .durationMinutes)
        try container.encode(isAllDay, forKey: .isAllDay)
        try container.encodeNil(forKey: .recurrenceRule)
        try container.encodeNil(forKey: .recurrenceEndDate)
        try container.encodeNil(forKey: .recurrenceInterval)
        try container.encodeIfPresent(reminderOffsets, forKey: .reminderOffsets)
        try container.encodeIfPresent(estimatedCost, forKey: .estimatedCost)
        if let backgroundColor {
            try container.encode(backgroundColor, forKey: .backgroundColor)
        } else {
            try container.encodeNil(forKey: .backgroundColor)
        }
        if let emergencyPhone {
            try container.encode(emergencyPhone, forKey: .emergencyPhone)
        } else {
            try container.encodeNil(forKey: .emergencyPhone)
        }
        if let locationData {
            try container.encode(locationData, forKey: .locationData)
        } else {
            try container.encodeNil(forKey: .locationData)
        }
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

#endif

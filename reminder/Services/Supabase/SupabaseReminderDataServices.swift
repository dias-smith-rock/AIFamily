import Foundation

#if canImport(Supabase)
import Supabase
#endif

// MARK: - Table Names
private enum SupabaseTable {
    static let tasks = "tasks"
    static let feedbacks = "feedbacks"
    static let households = "households"
    static let memberships = "household_memberships"
    static let inviteLinkNonces = "invite_link_nonces"
    static let subscriptionOrders = "subscription_orders"
}

// MARK: - Task Service

struct SupabaseTaskDataService: TaskDataService {
    private let provider: SupabaseClientProviding

    init(provider: SupabaseClientProviding) {
        self.provider = provider
    }

    func fetchTasks(in householdId: UUID) async throws -> [FamilyTask] {
        #if canImport(Supabase)
        let response: [FamilyTask] = try await provider.client
            .from(SupabaseTable.tasks)
            .select()
            .eq("household_id", value: householdId.uuidString)
            .order("due_date", ascending: true)
            .execute()
            .value
        return response
        #else
        _ = householdId
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func createTask(_ task: FamilyTask) async throws -> FamilyTask {
        #if canImport(Supabase)
        let response: FamilyTask = try await provider.client
            .from(SupabaseTable.tasks)
            .insert(task)
            .select()
            .single()
            .execute()
            .value
        return response
        #else
        _ = task
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func updateTask(_ task: FamilyTask) async throws -> FamilyTask {
        #if canImport(Supabase)
        let response: FamilyTask = try await provider.client
            .from(SupabaseTable.tasks)
            .update(task)
            .eq("id", value: task.id.uuidString)
            .select()
            .single()
            .execute()
            .value
        return response
        #else
        _ = task
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }
}

// MARK: - Feedback Service

struct SupabaseFeedbackDataService: FeedbackDataService {
    private let provider: SupabaseClientProviding

    init(provider: SupabaseClientProviding) {
        self.provider = provider
    }

    func fetchFeedbacks(in householdId: UUID, for taskId: UUID?) async throws -> [Feedback] {
        #if canImport(Supabase)
        if let taskId {
            let response: [Feedback] = try await provider.client
                .from(SupabaseTable.feedbacks)
                .select()
                .eq("household_id", value: householdId.uuidString)
                .eq("task_id", value: taskId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            return response
        } else {
            let response: [Feedback] = try await provider.client
                .from(SupabaseTable.feedbacks)
                .select()
                .eq("household_id", value: householdId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            return response
        }
        #else
        _ = householdId
        _ = taskId
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func createFeedback(_ feedback: Feedback) async throws -> Feedback {
        #if canImport(Supabase)
        let response: Feedback = try await provider.client
            .from(SupabaseTable.feedbacks)
            .insert(feedback)
            .select()
            .single()
            .execute()
            .value
        return response
        #else
        _ = feedback
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    /// 已读语义：把 `readerId` 加入 `read_by` 数组。
    /// PostgREST 不支持原子的数组 append，先读后写完成。
    func markFeedbackAsRead(id: UUID, readerId: UUID) async throws {
        #if canImport(Supabase)
        struct ReadByRow: Decodable {
            let readBy: [UUID]?
        }
        struct ReadByPatch: Encodable {
            let readBy: [UUID]
        }

        let rows: [ReadByRow] = try await provider.client
            .from(SupabaseTable.feedbacks)
            .select("read_by")
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
            .value

        var current = rows.first?.readBy ?? []
        guard current.contains(readerId) == false else { return }
        current.append(readerId)

        _ = try await provider.client
            .from(SupabaseTable.feedbacks)
            .update(ReadByPatch(readBy: current))
            .eq("id", value: id.uuidString)
            .execute()
        #else
        _ = id
        _ = readerId
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }
}

// MARK: - Household Membership Service

struct SupabaseHouseholdMembershipDataService: HouseholdMembershipDataService {
    private let provider: SupabaseClientProviding

    init(provider: SupabaseClientProviding) {
        self.provider = provider
    }

    func fetchMemberships(in householdId: UUID) async throws -> [HouseholdMembership] {
        #if canImport(Supabase)
        let response: [HouseholdMembership] = try await provider.client
            .from(SupabaseTable.memberships)
            .select()
            .eq("household_id", value: householdId.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
        return response
        #else
        _ = householdId
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func createMembership(_ membership: HouseholdMembership) async throws -> HouseholdMembership {
        #if canImport(Supabase)
        let response: HouseholdMembership = try await provider.client
            .from(SupabaseTable.memberships)
            .insert(membership)
            .select()
            .single()
            .execute()
            .value
        return response
        #else
        _ = membership
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func updateMembership(_ membership: HouseholdMembership) async throws -> HouseholdMembership {
        #if canImport(Supabase)
        let response: HouseholdMembership = try await provider.client
            .from(SupabaseTable.memberships)
            .update(membership)
            .eq("id", value: membership.id.uuidString)
            .select()
            .single()
            .execute()
            .value
        return response
        #else
        _ = membership
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }
}

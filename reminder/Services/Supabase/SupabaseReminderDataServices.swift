import Foundation

#if canImport(Supabase)
import Supabase
#endif

// MARK: - Table Names
private enum SupabaseTable {
    static let tasks = "tasks"
    static let feedbacks = "feedbacks"
    static let familyMembers = "family_members"
}

// MARK: - Task Service
struct SupabaseTaskDataService: TaskDataService {
    private let provider: SupabaseClientProviding

    init(provider: SupabaseClientProviding) {
        self.provider = provider
    }

    func fetchTasks() async throws -> [Task] {
        #if canImport(Supabase)
        let response: [Task] = try await provider.client
            .from(SupabaseTable.tasks)
            .select()
            .order("scheduled_at", ascending: true)
            .execute()
            .value
        return response
        #else
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func createTask(_ task: Task) async throws -> Task {
        #if canImport(Supabase)
        let response: Task = try await provider.client
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

    func updateTask(_ task: Task) async throws -> Task {
        #if canImport(Supabase)
        let response: Task = try await provider.client
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

    func fetchFeedbacks(for taskId: UUID?) async throws -> [Feedback] {
        #if canImport(Supabase)
        var query = provider.client
            .from(SupabaseTable.feedbacks)
            .select()
            .order("created_at", ascending: false)

        if let taskId {
            query = query.eq("task_id", value: taskId.uuidString)
        }

        let response: [Feedback] = try await query.execute().value
        return response
        #else
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

    func markFeedbackAsRead(id: UUID) async throws {
        #if canImport(Supabase)
        struct ReadPatch: Encodable {
            let isRead: Bool

            enum CodingKeys: String, CodingKey {
                case isRead = "is_read"
            }
        }

        _ = try await provider.client
            .from(SupabaseTable.feedbacks)
            .update(ReadPatch(isRead: true))
            .eq("id", value: id.uuidString)
            .execute()
        #else
        _ = id
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }
}

// MARK: - Family Member Service
struct SupabaseFamilyMemberDataService: FamilyMemberDataService {
    private let provider: SupabaseClientProviding

    init(provider: SupabaseClientProviding) {
        self.provider = provider
    }

    func fetchFamilyMembers() async throws -> [FamilyMember] {
        #if canImport(Supabase)
        let response: [FamilyMember] = try await provider.client
            .from(SupabaseTable.familyMembers)
            .select()
            .order("created_at", ascending: true)
            .execute()
            .value
        return response
        #else
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func createFamilyMember(_ member: FamilyMember) async throws -> FamilyMember {
        #if canImport(Supabase)
        let response: FamilyMember = try await provider.client
            .from(SupabaseTable.familyMembers)
            .insert(member)
            .select()
            .single()
            .execute()
            .value
        return response
        #else
        _ = member
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func updateFamilyMember(_ member: FamilyMember) async throws -> FamilyMember {
        #if canImport(Supabase)
        let response: FamilyMember = try await provider.client
            .from(SupabaseTable.familyMembers)
            .update(member)
            .eq("id", value: member.id.uuidString)
            .select()
            .single()
            .execute()
            .value
        return response
        #else
        _ = member
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }
}

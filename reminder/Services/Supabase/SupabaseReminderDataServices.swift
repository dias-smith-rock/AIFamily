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
            .execute()
            .value
        return response.sorted { $0.scheduledAt < $1.scheduledAt }
        #else
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func createTask(_ task: Task) async throws -> Task {
        #if canImport(Supabase)
        do {
            let response: Task = try await provider.client
                .from(SupabaseTable.tasks)
                .insert(task)
                .select()
                .single()
                .execute()
                .value
            return response
        } catch {
            let response: Task = try await provider.client
                .from(SupabaseTable.tasks)
                .insert(task.asCamelPayload)
                .select()
                .single()
                .execute()
                .value
            return response
        }
        #else
        _ = task
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func updateTask(_ task: Task) async throws -> Task {
        #if canImport(Supabase)
        do {
            let response: Task = try await provider.client
                .from(SupabaseTable.tasks)
                .update(task)
                .eq("id", value: task.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            return response
        } catch {
            let response: Task = try await provider.client
                .from(SupabaseTable.tasks)
                .update(task.asCamelPayload)
                .eq("id", value: task.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            return response
        }
        #else
        _ = task
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }
}

private extension Task {
    var asCamelPayload: CamelPayload {
        CamelPayload(
            id: id,
            title: title,
            note: note,
            scheduledAt: scheduledAt,
            dueAt: dueAt,
            location: location,
            assigneeId: assigneeId,
            childName: childName,
            status: status.rawValue,
            priority: priority.rawValue,
            source: source.rawValue,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    struct CamelPayload: Encodable {
        let id: UUID
        let title: String
        let note: String?
        let scheduledAt: Date
        let dueAt: Date?
        let location: String?
        let assigneeId: UUID
        let childName: String?
        let status: String
        let priority: String
        let source: String
        let createdAt: Date
        let updatedAt: Date
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
        if let taskId {
            let response: [Feedback] = try await provider.client
                .from(SupabaseTable.feedbacks)
                .select()
                .eq("task_id", value: taskId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            return response
        } else {
            let response: [Feedback] = try await provider.client
                .from(SupabaseTable.feedbacks)
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
            return response
        }
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

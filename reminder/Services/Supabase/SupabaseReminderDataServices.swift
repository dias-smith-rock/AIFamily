import Foundation

#if canImport(Supabase)
import Supabase

/// 将 `involved_member_ids` 明确写成 SQL `NULL`。库中 `[]` 在常见 RLS 下不等价于「全员可见」，成员会拉不到任务行。
private struct TasksInvolvedMemberIdsNullPatch: Encodable {
    enum CodingKeys: String, CodingKey {
        case involvedMemberIds = "involved_member_ids"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNil(forKey: .involvedMemberIds)
    }
}
#endif

// MARK: - PostgREST Select 片段

/// 成员列表 Left Join：`household_memberships` 子查询必须含 `role`、`status`，否则嵌套解码失败、UI 误判为虚拟档案。
enum SupabaseProfileSelect {
    static let nestedMembershipFields = """
        id,\
        household_id,\
        user_id,\
        profile_id,\
        nickname,\
        role,\
        status,\
        joined_at,\
        created_at,\
        updated_at
        """

    static let profilesWithMemberships =
        "*, household_memberships!profile_id(\(nestedMembershipFields))"
}

// MARK: - Table Names
private enum SupabaseTable {
    static let tasks = "tasks"
    static let feedbacks = "feedbacks"
    static let households = "households"
    static let memberships = "household_memberships"
    static let familyProfiles = "family_profiles"
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
        // 不添加基于 `involved_member_ids` + `auth.uid()` 的过滤：`involved_member_ids` 为 membership id 数组，与 user id 维度不同；隔离交给 RLS。
        let response: [FamilyTask] = try await provider.client
            .from(SupabaseTable.tasks)
            .select()
            .eq("household_id", value: householdId.uuidString)
            .order("due_date", ascending: true)
            .execute()
            .value
        return response.map(Self.normalizeInvolvedMemberIdsForRowSemantics)
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
        return Self.normalizeInvolvedMemberIdsForRowSemantics(response)
        #else
        _ = task
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func updateTask(_ task: FamilyTask) async throws -> FamilyTask {
        #if canImport(Supabase)
        /// 与 `FamilyTask.involvesWholeHousehold` 一致：库中 `[]` 在部分 RLS 下不等价于 `NULL`，成员会看不到行。
        if task.involvesWholeHousehold {
            _ = try await provider.client
                .from(SupabaseTable.tasks)
                .update(TasksInvolvedMemberIdsNullPatch())
                .eq("id", value: task.id.uuidString)
                .execute()
        }

        var normalized = task
        if normalized.involvedMemberIds?.isEmpty == true {
            normalized.involvedMemberIds = nil
        }

        let response: FamilyTask = try await provider.client
            .from(SupabaseTable.tasks)
            .update(normalized)
            .eq("id", value: task.id.uuidString)
            .select()
            .single()
            .execute()
            .value
        return Self.normalizeInvolvedMemberIdsForRowSemantics(response)
        #else
        _ = task
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func patchTaskStatus(taskId: UUID, to status: TaskStatus) async throws -> FamilyTask {
        #if canImport(Supabase)
        struct StatusPatch: Encodable {
            let status: String
        }

        let response: FamilyTask = try await provider.client
            .from(SupabaseTable.tasks)
            .update(StatusPatch(status: status.rawValue))
            .eq("id", value: taskId.uuidString)
            .select()
            .single()
            .execute()
            .value
        return Self.normalizeInvolvedMemberIdsForRowSemantics(response)
        #else
        _ = taskId
        _ = status
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func deleteTask(taskId: UUID) async throws {
        #if canImport(Supabase)
        try await provider.client
            .from(SupabaseTable.tasks)
            .delete()
            .eq("id", value: taskId.uuidString)
            .execute()
        #else
        _ = taskId
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    private static func normalizeInvolvedMemberIdsForRowSemantics(_ task: FamilyTask) -> FamilyTask {
        guard task.involvedMemberIds?.isEmpty == true else { return task }
        var copy = task
        copy.involvedMemberIds = nil
        return copy
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

    func createSystemFeedback(householdId: UUID, content: String, taskId: UUID?) async throws -> Feedback {
        #if canImport(Supabase)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContent.isEmpty == false else {
            throw SupabaseServiceError.invalidResponse
        }

        let payload = SystemFeedbackInsertPayload(
            id: UUID(),
            householdId: householdId,
            taskId: taskId,
            content: trimmedContent,
            createdAt: Date()
        )

        let response: Feedback = try await provider.client
            .from(SupabaseTable.feedbacks)
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return response
        #else
        _ = householdId
        _ = content
        _ = taskId
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }
}

private struct SystemFeedbackInsertPayload: Encodable {
    let id: UUID
    let householdId: UUID
    let taskId: UUID?
    let content: String
    let senderId: UUID? = nil
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case taskId = "task_id"
        case content
        case senderId = "sender_id"
        case createdAt = "created_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(householdId.uuidString.lowercased(), forKey: .householdId)
        try container.encodeIfPresent(taskId?.uuidString.lowercased(), forKey: .taskId)
        try container.encode(content, forKey: .content)
        try container.encode(senderId, forKey: .senderId)
        try container.encode(
            SupabaseFeedbackDataService.formatDateForInsert(createdAt),
            forKey: .createdAt
        )
    }
}

extension SupabaseFeedbackDataService {
    fileprivate static func formatDateForInsert(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

// MARK: - Family Profiles Service

struct SupabaseFamilyProfileDataService: FamilyProfileDataService {
    private let provider: SupabaseClientProviding

    /// PostgREST Left Join：`family_profiles` 为主表；嵌套须含 `role`、`status` 供身份 Badge 与虚拟档案判定。
    private static let selectProfilesWithMemberships = SupabaseProfileSelect.profilesWithMemberships

    init(provider: SupabaseClientProviding) {
        self.provider = provider
    }

    func fetchProfiles(in householdId: UUID) async throws -> [FamilyProfile] {
        #if canImport(Supabase)
        #if DEBUG
        print("🔎 [FamilyDebug] fetchProfiles start — household_id=\(householdId.uuidString)")
        print("🔎 [FamilyDebug] fetchProfiles select=\"\(Self.selectProfilesWithMemberships)\"")
        #endif
        // 勿把 `execute()` 写成 `PostgrestResponse<Data>`：`execute<T: Decodable>` 会用 JSONDecoder 把 body 解成 `T`；
        // `Data` 的 Codable 语义是 **Base64 字符串**，与 PostgREST 返回的 JSON 数组冲突 → “Expected String, found array”。
        let rawResponse: PostgrestResponse<Void>
        do {
            rawResponse = try await provider.client
                .from(SupabaseTable.familyProfiles)
                .select(Self.selectProfilesWithMemberships)
                .eq("household_id", value: householdId.uuidString)
                .order("name", ascending: true)
                .execute()
        } catch {
            #if DEBUG
            print("❌ [FamilyDebug] fetchProfiles execute failed — household_id=\(householdId.uuidString)")
            print("   errorType=\(String(describing: Swift.type(of: error)))")
            print("   localizedDescription=\(error.localizedDescription)")
            if error is DecodingError {
                print("   hint: 若此处为 DecodingError，检查是否误用了 `PostgrestResponse<Data>`；应使用 `execute()` → `PostgrestResponse<Void>`，再用 `rawResponse.data` 手动解码。")
            }
            let ns = error as NSError
            if ns.domain.isEmpty == false || ns.code != 0 {
                print("   nsError domain=\(ns.domain) code=\(ns.code) userInfo=\(ns.userInfo)")
            }
            #endif
            throw error
        }
        #if DEBUG
        let http = rawResponse.response
        print("🔎 [FamilyDebug] fetchProfiles response status=\(http.statusCode) bytes=\(rawResponse.data.count)")
        if let rawJSON = String(data: rawResponse.data, encoding: .utf8) {
            print("💡 [终极排查] Supabase 原始返回 JSON: \n\(rawJSON)")
        } else {
            print("💡 [终极排查] Supabase 原始返回无法转为 UTF-8，bytes=\(rawResponse.data.count)")
        }
        #endif
        do {
            return try SupabaseCodec.makeDecoder().decode([FamilyProfile].self, from: rawResponse.data)
        } catch {
            #if DEBUG
            let rawJSONString = String(data: rawResponse.data, encoding: .utf8) ?? "<non-utf8>"
            print("❌ [FamilyDebug] family_profiles decode failed — household_id=\(householdId.uuidString)")
            print("🔎 [FamilyDebug] fetchProfiles select was=\"\(Self.selectProfilesWithMemberships)\"")
            print("📦 [FamilyDebug] family_profiles raw payload: \(rawJSONString)")
            print("🧨 [FamilyDebug] decode error: \(error.localizedDescription)")
            #endif
            throw error
        }
        #else
        _ = householdId
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func fetchProfile(id: UUID) async throws -> FamilyProfile? {
        #if canImport(Supabase)
        #if DEBUG
        print("🔎 [FamilyDebug] fetchProfile start — profile_id=\(id.uuidString)")
        #endif
        let rawResponse = try await provider.client
            .from(SupabaseTable.familyProfiles)
            .select(Self.selectProfilesWithMemberships)
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
        let rows = try SupabaseCodec.makeDecoder().decode([FamilyProfile].self, from: rawResponse.data)
        return rows.first
        #else
        _ = id
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func createLocalProfile(householdId: UUID, draft: LocalProfileDraft) async throws {
        #if canImport(Supabase)
        struct ProfileWriteRow: Encodable {
            let householdId: UUID
            let name: String
            let avatarUrl: String?
            let gender: String?
            let birthDate: String?
            let idCardNum: String?
            let passportNum: String?
            let permitNum: String?
            let height: Double?
            let weight: Double?
            let school: String?
            let grade: String?
            let email: String?
            let mainphone: String?
            let secondphone: String?

            enum CodingKeys: String, CodingKey {
                case householdId = "household_id"
                case name
                case avatarUrl = "avatar_url"
                case gender
                case birthDate = "birth_date"
                case idCardNum = "id_card_num"
                case passportNum = "passport_num"
                case permitNum = "permit_num"
                case height
                case weight
                case school
                case grade
                case email
                case mainphone
                case secondphone
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let payload = ProfileWriteRow(
            householdId: householdId,
            name: draft.name,
            avatarUrl: draft.avatarURL,
            gender: draft.gender,
            birthDate: draft.birthDate.map { dateFormatter.string(from: $0) },
            idCardNum: draft.idCardNum,
            passportNum: draft.passportNum,
            permitNum: draft.permitNum,
            height: draft.height,
            weight: draft.weight,
            school: draft.school,
            grade: draft.grade,
            email: draft.email,
            mainphone: draft.mainPhone,
            secondphone: draft.secondPhone
        )
        _ = try await provider.client
            .from(SupabaseTable.familyProfiles)
            .insert(payload)
            .execute()
        #else
        _ = householdId
        _ = draft
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }

    func updateProfile(profileId: UUID, draft: LocalProfileDraft) async throws {
        #if canImport(Supabase)
        struct ProfileUpdateRow: Encodable {
            let name: String
            let avatarUrl: String?
            let gender: String?
            let birthDate: String?
            let idCardNum: String?
            let passportNum: String?
            let permitNum: String?
            let height: Double?
            let weight: Double?
            let school: String?
            let grade: String?
            let email: String?
            let mainphone: String?
            let secondphone: String?

            enum CodingKeys: String, CodingKey {
                case name
                case avatarUrl = "avatar_url"
                case gender
                case birthDate = "birth_date"
                case idCardNum = "id_card_num"
                case passportNum = "passport_num"
                case permitNum = "permit_num"
                case height
                case weight
                case school
                case grade
                case email
                case mainphone
                case secondphone
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let payload = ProfileUpdateRow(
            name: draft.name,
            avatarUrl: draft.avatarURL,
            gender: draft.gender,
            birthDate: draft.birthDate.map { dateFormatter.string(from: $0) },
            idCardNum: draft.idCardNum,
            passportNum: draft.passportNum,
            permitNum: draft.permitNum,
            height: draft.height,
            weight: draft.weight,
            school: draft.school,
            grade: draft.grade,
            email: draft.email,
            mainphone: draft.mainPhone,
            secondphone: draft.secondPhone
        )

        _ = try await provider.client
            .from(SupabaseTable.familyProfiles)
            .update(payload)
            .eq("id", value: profileId.uuidString)
            .execute()
        #else
        _ = profileId
        _ = draft
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
        let rawResponse = try await provider.client
            .from(SupabaseTable.memberships)
            .select()
            .eq("household_id", value: householdId.uuidString)
            .order("created_at", ascending: true)
            .execute()
        do {
            return try SupabaseCodec.makeDecoder().decode([HouseholdMembership].self, from: rawResponse.data)
        } catch let DecodingError.valueNotFound(value, context) {
            #if DEBUG
            let rawJSONString = String(data: rawResponse.data, encoding: .utf8) ?? "<non-utf8>"
            print("❌ [FamilyDebug] household_memberships valueNotFound - type=\(value), codingPath=\(context.codingPath.map(\.stringValue).joined(separator: "."))")
            print("📦 [FamilyDebug] household_memberships raw payload: \(rawJSONString)")
            #endif
            throw DecodingError.valueNotFound(value, context)
        } catch let DecodingError.keyNotFound(key, context) {
            #if DEBUG
            let rawJSONString = String(data: rawResponse.data, encoding: .utf8) ?? "<non-utf8>"
            print("❌ [FamilyDebug] household_memberships keyNotFound - key=\(key.stringValue), codingPath=\(context.codingPath.map(\.stringValue).joined(separator: "."))")
            print("📦 [FamilyDebug] household_memberships raw payload: \(rawJSONString)")
            #endif
            throw DecodingError.keyNotFound(key, context)
        } catch {
            #if DEBUG
            let rawJSONString = String(data: rawResponse.data, encoding: .utf8) ?? "<non-utf8>"
            print("❌ [FamilyDebug] household_memberships decode failed - householdId=\(householdId.uuidString)")
            print("📦 [FamilyDebug] household_memberships raw payload: \(rawJSONString)")
            print("🧨 [FamilyDebug] decode error: \(error.localizedDescription)")
            #endif
            throw error
        }
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

    func updateNickname(householdId: UUID, profileId: UUID, nickname: String) async throws {
        #if canImport(Supabase)
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw SupabaseServiceError.invalidResponse
        }
        struct NicknamePatch: Encodable {
            let nickname: String
        }
        _ = try await provider.client
            .from(SupabaseTable.memberships)
            .update(NicknamePatch(nickname: trimmed))
            .eq("household_id", value: householdId.uuidString)
            .eq("profile_id", value: profileId.uuidString)
            .execute()
        #else
        _ = householdId
        _ = profileId
        _ = nickname
        throw SupabaseServiceError.sdkUnavailable
        #endif
    }
}

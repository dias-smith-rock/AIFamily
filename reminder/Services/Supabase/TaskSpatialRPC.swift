import Foundation

#if canImport(Supabase)

struct CreateTaskWithSpatialParams: Encodable, Sendable {
    let pTitle: String
    let pDescription: String?
    let pCreatorId: String
    let pTenantId: String
    let pGeofence: TaskGeofence?

    enum CodingKeys: String, CodingKey {
        case pTitle = "p_title"
        case pDescription = "p_description"
        case pCreatorId = "p_creator_id"
        case pTenantId = "p_tenant_id"
        case pGeofence = "p_geofence"
    }

    /// PostgREST 按「实际出现的 JSON 键」匹配函数重载；省略 `null` 会误匹配三参数签名。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pTitle, forKey: .pTitle)
        if let pDescription {
            try container.encode(pDescription, forKey: .pDescription)
        } else {
            try container.encodeNil(forKey: .pDescription)
        }
        try container.encode(pCreatorId, forKey: .pCreatorId)
        try container.encode(pTenantId, forKey: .pTenantId)
        if let pGeofence {
            try container.encode(pGeofence, forKey: .pGeofence)
        } else {
            try container.encodeNil(forKey: .pGeofence)
        }
    }
}

struct CompleteTaskWithSpatialParams: Encodable, Sendable {
    let pTaskId: String
    let pUserId: String
    let pCompletionLocation: TaskCompletionLocation?

    enum CodingKeys: String, CodingKey {
        case pTaskId = "p_task_id"
        case pUserId = "p_user_id"
        case pCompletionLocation = "p_completion_location"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pTaskId, forKey: .pTaskId)
        try container.encode(pUserId, forKey: .pUserId)
        if let pCompletionLocation {
            try container.encode(pCompletionLocation, forKey: .pCompletionLocation)
        } else {
            try container.encodeNil(forKey: .pCompletionLocation)
        }
    }
}

enum TaskSpatialRPCSupport {
    static func isMissingCreateTaskRPC(_ error: Error) -> Bool {
        matchesSpatialRPCSchemaCacheMiss(error, functionName: "create_task_with_spatial")
    }

    static func isMissingCompleteTaskRPC(_ error: Error) -> Bool {
        matchesSpatialRPCSchemaCacheMiss(error, functionName: "complete_task_with_spatial")
    }

    private static func matchesSpatialRPCSchemaCacheMiss(_ error: Error, functionName: String) -> Bool {
        let message = String(describing: error).lowercased()
        let localized = error.localizedDescription.lowercased()
        let haystack = message + " " + localized
        return haystack.contains(functionName) && haystack.contains("schema cache")
    }
}

#endif
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
}

#endif
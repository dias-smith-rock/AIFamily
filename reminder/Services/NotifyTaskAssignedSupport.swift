import Foundation

#if canImport(Supabase)
import Supabase
#endif

/// Fire-and-forget client call to `notify-task-assigned` after an explicit assignee save.
enum NotifyTaskAssignedSupport {
    private static let functionName = "notify-task-assigned"

    #if DEBUG
    private static func debugLog(_ message: String) {
        print("[NotifyTaskAssigned] \(message)")
    }
    #else
    private static func debugLog(_ message: String) {}
    #endif

    static func notify(
        taskId: UUID,
        householdId: UUID,
        assigneeMembershipIds: [UUID]?,
        title: String,
        actorMembershipId: UUID
    ) async {
        #if canImport(Supabase)
        guard let assignees = assigneeMembershipIds, assignees.isEmpty == false else {
            debugLog("skip: no explicit assignees")
            return
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty == false else {
            debugLog("skip: empty title")
            return
        }

        struct RequestBody: Encodable {
            let taskId: String
            let householdId: String
            let assigneeMembershipIds: [String]
            let title: String
            let actorMembershipId: String

            enum CodingKeys: String, CodingKey {
                case taskId = "task_id"
                case householdId = "household_id"
                case assigneeMembershipIds = "assignee_membership_ids"
                case title
                case actorMembershipId = "actor_membership_id"
            }
        }

        let body = RequestBody(
            taskId: taskId.uuidString.lowercased(),
            householdId: householdId.uuidString.lowercased(),
            assigneeMembershipIds: assignees.map { $0.uuidString.lowercased() },
            title: trimmedTitle,
            actorMembershipId: actorMembershipId.uuidString.lowercased()
        )

        do {
            _ = try await SupabaseManager.shared.client.functions.invoke(
                functionName,
                options: FunctionInvokeOptions(body: body)
            )
            debugLog("ok task=\(taskId.uuidString.prefix(8)) assignees=\(assignees.count)")
        } catch {
            debugLog("failed: \(error.localizedDescription)")
        }
        #else
        _ = taskId
        _ = householdId
        _ = assigneeMembershipIds
        _ = title
        _ = actorMembershipId
        #endif
    }
}

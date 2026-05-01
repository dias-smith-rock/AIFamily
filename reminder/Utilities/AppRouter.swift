import Foundation
import Combine

#if canImport(Supabase)
import Supabase
#endif

@MainActor
final class AppRouter: ObservableObject {
    enum AppState: Equatable {
        case unauthenticated
        case orgRouting
        case pendingApproval
        case activeMember
    }

    @Published var appState: AppState = .unauthenticated

    func refreshStateFromBackend() async {
        #if canImport(Supabase)
        do {
            let client = SupabaseManager.shared.client
            let session = try await client.auth.session
            let membership = try await fetchMembership(client: client, userId: session.user.id)

            guard let membership else {
                appState = .orgRouting
                return
            }

            let normalizedStatus = membership.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch normalizedStatus {
            case "active":
                appState = .activeMember
            case "invited", "pending":
                appState = .pendingApproval
            default:
                appState = .orgRouting
            }
        } catch {
            appState = .unauthenticated
        }
        #else
        appState = .unauthenticated
        #endif
    }

    func goToOrgRouting() {
        appState = .orgRouting
    }

    func goToPendingApproval() {
        appState = .pendingApproval
    }

    func goToActiveMember() {
        appState = .activeMember
    }

    #if canImport(Supabase)
    private struct MembershipRow: Decodable {
        let householdId: UUID
        let status: String

        enum CodingKeys: String, CodingKey {
            case householdId = "household_id"
            case status
        }
    }

    private func fetchMembership(client: SupabaseClient, userId: UUID) async throws -> MembershipRow? {
        let rows: [MembershipRow] = try await client
            .from("household_memberships")
            .select("household_id,status")
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first
    }
    #endif
}

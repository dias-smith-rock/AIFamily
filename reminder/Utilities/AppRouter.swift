import Foundation
import Combine

#if canImport(Supabase)
import Supabase
#endif

@MainActor
final class AppRouter: ObservableObject {
    enum AppState: Equatable {
        case unauthenticated
        case noHousehold
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
                appState = .noHousehold
                return
            }

            if membership.status == "invited" {
                appState = .pendingApproval
                return
            }

            let hasPendingBinding = try await hasPendingBindingMember(
                client: client,
                householdId: membership.householdId
            )
            appState = hasPendingBinding ? .pendingApproval : .activeMember
        } catch {
            appState = .unauthenticated
        }
        #else
        appState = .unauthenticated
        #endif
    }

    func goToNoHousehold() {
        appState = .noHousehold
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

    private struct BindingRow: Decodable {
        let bindingStatus: String

        enum CodingKeys: String, CodingKey {
            case bindingStatus = "binding_status"
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

    private func hasPendingBindingMember(client: SupabaseClient, householdId: UUID) async throws -> Bool {
        let rows: [BindingRow] = try await client
            .from("family_members")
            .select("binding_status")
            .eq("household_id", value: householdId.uuidString)
            .limit(20)
            .execute()
            .value
        return rows.contains { $0.bindingStatus == "pending" }
    }
    #endif
}

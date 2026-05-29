import Combine
import Foundation

@MainActor
final class VIPSubscriptionViewModel: ObservableObject {
    @Published private(set) var isClaiming = false
    @Published var errorMessage: String?
    @Published private(set) var claimedExpiryDate: Date?

    func claimFreeProTrial(appRouter: AppRouter) async -> Bool {
        #if canImport(Supabase)
        guard isClaiming == false else { return false }
        isClaiming = true
        errorMessage = nil
        defer { isClaiming = false }

        do {
            let expiry = try await SubscriptionSupabaseSupport.claimFreeProTrialForCurrentUser()
            claimedExpiryDate = expiry
            AnalyticsManager.log(event: .vipClaimed)
            await appRouter.refreshPremiumStateAfterClaim()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        #else
        errorMessage = String(localized: "当前构建环境未包含 Supabase SDK。")
        return false
        #endif
    }
}

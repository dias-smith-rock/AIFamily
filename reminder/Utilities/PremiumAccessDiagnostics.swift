import Foundation

/// VIP 权限诊断日志：登录、登出、回前台、切换组织时输出三元状态。
enum PremiumAccessDiagnostics {
    @MainActor
    static func log(appRouter: AppRouter, trigger: String) {
        let householdLabel = resolvedHouseholdLabel(appRouter: appRouter)
        let householdIdText = appRouter.selectedHouseholdId.map(\.uuidString) ?? "nil"
        let creatorIsVIP = appRouter.selectedHouseholdCreatorHasActivePro
        let currentUserIsVIP = StoreKitSubscriptionService.shared.isPersonalSubscriber(
            userEntitlement: appRouter.userEntitlement
        )
        let inOrgVIP = resolvedInOrganizationVIP(appRouter: appRouter)
        let rpcDiagnostics = SubscriptionSupabaseSupport.lastCreatorProFetchDiagnostics.summaryForLog

        print(
            """
            [VIPAccess] \(trigger) | 组织=\(householdLabel) | householdId=\(householdIdText) | 组织创建者VIP=\(boolText(creatorIsVIP)) | 当前用户VIP=\(boolText(currentUserIsVIP)) | 组织内VIP=\(boolText(inOrgVIP)) | \(rpcDiagnostics)
            """
        )
    }

    @MainActor
    private static func resolvedInOrganizationVIP(appRouter: AppRouter) -> Bool {
        if GuestSessionStore.isGuestMode {
            return true
        }
        guard appRouter.selectedHouseholdId != nil else {
            return false
        }
        return PremiumAccess.hasPremiumAccess(
            userEntitlement: appRouter.userEntitlement,
            creatorHasActivePro: appRouter.selectedHouseholdCreatorHasActivePro
        ) || StoreKitSubscriptionService.shared.hasLocalActiveSubscription
    }

    @MainActor
    private static func resolvedHouseholdLabel(appRouter: AppRouter) -> String {
        guard let householdId = appRouter.selectedHouseholdId else {
            return "未进入组织"
        }
        let name = appRouter.selectedHouseholdName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (name?.isEmpty == false) ? name! : "未命名群组"
        let shortId = householdId.uuidString.prefix(8)
        return "\(displayName)(\(shortId))"
    }

    private static func boolText(_ value: Bool) -> String {
        value ? "是" : "否"
    }
}

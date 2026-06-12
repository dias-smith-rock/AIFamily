import Foundation

/// VIP 权限诊断日志：登录、登出、回前台、切换组织时输出三元状态。
enum PremiumAccessDiagnostics {
    @MainActor
    static func log(appRouter: AppRouter, trigger: String) {
        let householdLabel = resolvedHouseholdLabel(appRouter: appRouter)
        let householdIdText = appRouter.selectedHouseholdId.map(\.uuidString) ?? "nil"
        let creatorIsVIP = appRouter.selectedHouseholdCreatorHasActivePro
        let revenueCat = RevenueCatSubscriptionService.shared
        let currentUserIsVIP = revenueCat.isPersonalSubscriber(
            userEntitlement: appRouter.userEntitlement
        )
        let inOrgVIP = resolvedInOrganizationVIP(appRouter: appRouter)
        let rpcDiagnostics = SubscriptionSupabaseSupport.lastCreatorProFetchDiagnostics.summaryForLog
        let rcActive = revenueCat.hasActiveProEntitlement

        print(
            """
            [VIPAccess] \(trigger) | 组织=\(householdLabel) | householdId=\(householdIdText) | 组织创建者VIP=\(boolText(creatorIsVIP)) | 当前用户VIP=\(boolText(currentUserIsVIP)) | RevenueCat=\(boolText(rcActive)) | 组织内VIP=\(boolText(inOrgVIP)) | \(rpcDiagnostics)
            """
        )
    }

    @MainActor
    private static func resolvedInOrganizationVIP(appRouter: AppRouter) -> Bool {
        appRouter.hasPremiumAccess
    }

    @MainActor
    private static func resolvedHouseholdLabel(appRouter: AppRouter) -> String {
        guard let householdId = appRouter.selectedHouseholdId else {
            return L10n.Common.notInOrganization.string()
        }
        let name = appRouter.selectedHouseholdName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (name?.isEmpty == false) ? name! : AppLocalized.localizedSync(L10n.Family.unnamedGroup)
        let shortId = householdId.uuidString.prefix(8)
        return "\(displayName)(\(shortId))"
    }

    private static func boolText(_ value: Bool) -> String {
        value ? AppLocalized.localizedSync(L10n.Common.yes) : AppLocalized.localizedSync(L10n.Common.no)
    }
}

import Combine
import SwiftUI

/// 群组切换弹窗状态：由 `ContentView` 根视图持有，子页面仅通过纯 Button 触发。
@MainActor
final class GroupSwitcherCoordinator: ObservableObject {
    @Published var showSwitchGroupDialog = false
    @Published var isShowingCreateOrganizationSheet = false
    @Published var newOrganizationName = ""
    @Published var newOrganizationDescription = ""
    @Published var createOrganizationError: String?

    @Published var showJoinGroupSheet = false
    @Published var joinCode = ""
    @Published var joinInputError: String?

    let orgRoutingViewModel: OrgRoutingViewModel

    init(orgRoutingViewModel: OrgRoutingViewModel) {
        self.orgRoutingViewModel = orgRoutingViewModel
    }

    convenience init() {
        self.init(orgRoutingViewModel: AppViewModels.makeOrgRoutingViewModel())
    }

    var normalizedInviteCode: String {
        joinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var isInviteCodeValid: Bool {
        normalizedInviteCode.range(of: "^[A-Z0-9]{6}$", options: .regularExpression) != nil
    }

    func submitCreateOrganization(appRouter: AppRouter) async {
        createOrganizationError = nil
        guard appRouter.canCreateOrJoinAnotherHousehold() else {
            presentPremiumUpgradeAfterDismiss(appRouter: appRouter)
            return
        }
        let normalizedName = newOrganizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName.isEmpty == false else {
            createOrganizationError = L10n.Family.pleaseEnterAGroupName.string()
            return
        }
        let trimmedDescription = newOrganizationDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let description = trimmedDescription.isEmpty ? nil : trimmedDescription

        guard let createdHouseholdId = await orgRoutingViewModel.createHousehold(
            displayName: normalizedName,
            description: description,
            isPremium: appRouter.hasPremiumAccess
        ) else {
            createOrganizationError = orgRoutingViewModel.errorMessage
            return
        }

        newOrganizationName = ""
        newOrganizationDescription = ""
        isShowingCreateOrganizationSheet = false
        appRouter.preferHouseholdOnNextRefresh(createdHouseholdId)
        if appRouter.isAnonymousUser {
            AnonymousBindPromptStore.scheduleAfterGroupAction()
        }
        await appRouter.refreshStateFromBackend()
    }

    func submitJoinGroup(appRouter: AppRouter, locale: Locale) async {
        joinInputError = nil
        guard appRouter.canCreateOrJoinAnotherHousehold() else {
            presentPremiumUpgradeAfterDismiss(appRouter: appRouter)
            return
        }
        guard isInviteCodeValid else {
            joinInputError = L10n.Family.invalidInviteCodeFormatMustBe6LettersOr.string()
            return
        }
        let success = await orgRoutingViewModel.joinGroup(code: normalizedInviteCode)
        guard success else {
            joinInputError = orgRoutingViewModel.errorMessage
            return
        }
        showJoinGroupSheet = false
        showSwitchGroupDialog = false
        if appRouter.isAnonymousUser {
            AnonymousBindPromptStore.scheduleAfterGroupAction()
        }
        await appRouter.refreshStateFromBackend()
        if let groupId = appRouter.selectedHouseholdId {
            AnalyticsManager.log(event: .groupJoined(groupId: groupId))
        }
    }

    func firstInviteCode(from text: String) -> String? {
        let pattern = "\\b[A-Z0-9]{6}\\b"
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(text[range])
    }

    func presentCreateOrganizationAfterDismiss(appRouter: AppRouter) {
        guard appRouter.canCreateOrJoinAnotherHousehold() else {
            presentPremiumUpgradeAfterDismiss(appRouter: appRouter)
            return
        }
        showSwitchGroupDialog = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            isShowingCreateOrganizationSheet = true
        }
    }

    func presentJoinGroupAfterDismiss(appRouter: AppRouter) {
        guard appRouter.canCreateOrJoinAnotherHousehold() else {
            presentPremiumUpgradeAfterDismiss(appRouter: appRouter)
            return
        }
        showSwitchGroupDialog = false
        joinInputError = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            showJoinGroupSheet = true
        }
    }

    /// 关闭群组相关 Sheet 后，在根视图直接弹出 VIP 订阅页。
    private func presentPremiumUpgradeAfterDismiss(appRouter: AppRouter) {
        showSwitchGroupDialog = false
        isShowingCreateOrganizationSheet = false
        showJoinGroupSheet = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            appRouter.presentPremiumUpgrade()
        }
    }
}

import Combine
import SwiftUI

/// 群组切换弹窗状态：由 `ContentView` 根视图持有，子页面仅通过纯 Button 触发。
@MainActor
final class GroupSwitcherCoordinator: ObservableObject {
    @Published var showSwitchGroupDialog = false
    @Published var isShowingCreateOrganizationSheet = false
    @Published var newOrganizationName = ""
    @Published var createOrganizationError: String?

    @Published var showJoinGroupSheet = false
    @Published var joinCode = ""
    @Published var joinInputError: String?
    @Published var showJoinScanner = false

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
        let normalizedName = newOrganizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName.isEmpty == false else {
            createOrganizationError = "Organization name cannot be empty."
            return
        }

        guard let createdHouseholdId = await orgRoutingViewModel.createHousehold(displayName: normalizedName) else {
            createOrganizationError = orgRoutingViewModel.errorMessage
            return
        }

        newOrganizationName = ""
        isShowingCreateOrganizationSheet = false
        appRouter.preferHouseholdOnNextRefresh(createdHouseholdId)
        await appRouter.refreshStateFromBackend()
    }

    func submitJoinGroup(appRouter: AppRouter, locale: Locale) async {
        joinInputError = nil
        guard isInviteCodeValid else {
            joinInputError = String(localized: "邀请码格式无效：必须为 6 位字母或数字。")
            return
        }
        let success = await orgRoutingViewModel.joinGroup(code: normalizedInviteCode)
        guard success else {
            joinInputError = orgRoutingViewModel.errorMessage
            return
        }
        showJoinGroupSheet = false
        showSwitchGroupDialog = false
        await appRouter.refreshStateFromBackend()
    }

    func firstInviteCode(from text: String) -> String? {
        let pattern = "\\b[A-Z0-9]{6}\\b"
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(text[range])
    }

    func presentCreateOrganizationAfterDismiss() {
        showSwitchGroupDialog = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            isShowingCreateOrganizationSheet = true
        }
    }

    func presentJoinGroupAfterDismiss() {
        showSwitchGroupDialog = false
        joinInputError = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            showJoinGroupSheet = true
        }
    }
}

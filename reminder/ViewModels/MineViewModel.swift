import Foundation
import Combine

#if canImport(UIKit)
import UIKit
#endif

#if canImport(Supabase)
import Supabase
#endif

@MainActor
final class MineViewModel: ObservableObject {
    @Published private(set) var displayName: String = "Qi Lun"
    @Published private(set) var email: String = "qi.lun@example.com"
    @Published private(set) var avatarInitials: String = "QL"

    @Published var toastMessage: String?
    @Published var signOutErrorMessage: String?
    @Published var deleteAccountErrorMessage: String?
    @Published var showDeleteAccountAlert = false
    @Published var isCheckingCreatorStatus = false
    @Published var showCreatorBlockAlert = false
    @Published var creatorBlockGroupName = ""
    @Published var creatorBlockGroupCount = 0
    @Published var isSigningOut = false
    @Published var isDeletingAccount = false

    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    func loadAccountSummary() async {
        #if canImport(Supabase)
        let supabase = SupabaseManager.shared.client
        do {
            let session = try await supabase.auth.session
            let user = session.user
            if let mail = user.email, mail.isEmpty == false {
                email = mail
                displayName = displayNameFromEmail(mail)
            } else {
                email = user.id.uuidString
                displayName = String(user.id.uuidString.prefix(8))
            }
            avatarInitials = Self.initials(from: displayName)
        } catch {
            // 保持设计稿占位，不阻断页面
        }
        #endif
    }

    func signOut(appRouter: AppRouter) async {
        guard isSigningOut == false else { return }
        isSigningOut = true
        signOutErrorMessage = nil
        defer { isSigningOut = false }

        AuthSessionGuard.shared.beginLoggingOut()
        appRouter.logVIPAccessState(trigger: "用户退出前")
        do {
            try await authService.signOut()
            UserDefaults.standard.set(false, forKey: "isUserLoggedIn")
            UserDefaults.standard.removeObject(forKey: AppRouter.offlineHouseholdSnapshotKey)
            LocalCacheManager.shared.removeAll()
            await appRouter.refreshStateFromBackend()
        } catch {
            signOutErrorMessage = error.localizedDescription
        }
        await AuthSessionGuard.shared.endLoggingOut()
    }

    func deleteAccount(appRouter: AppRouter) async {
        guard isDeletingAccount == false else { return }
        isDeletingAccount = true
        deleteAccountErrorMessage = nil
        defer { isDeletingAccount = false }

        AuthSessionGuard.shared.beginLoggingOut()
        appRouter.logVIPAccessState(trigger: "用户退出前")
        do {
            // 预留：接入 delete-account Edge Function / RPC 后在此调用
            // try await supabase.functions.invoke("delete-account")
            await authService.cleanUpCurrentUserAvatars()
            try await authService.signOut()
            UserDefaults.standard.set(false, forKey: "isUserLoggedIn")
            UserDefaults.standard.removeObject(forKey: AppRouter.offlineHouseholdSnapshotKey)
            LocalCacheManager.shared.removeAll()
            await appRouter.refreshStateFromBackend()
        } catch {
            deleteAccountErrorMessage = error.localizedDescription
        }
        await AuthSessionGuard.shared.endLoggingOut()
    }

    func checkCreatorStatusBeforeDeletion() async {
        guard isCheckingCreatorStatus == false, isDeletingAccount == false else { return }

        #if canImport(Supabase)
        isCheckingCreatorStatus = true
        defer { isCheckingCreatorStatus = false }

        let supabase = SupabaseManager.shared.client
        guard let userId = supabase.auth.currentUser?.id else { return }

        do {
            let records: [CreatorMembershipRecord] = try await supabase
                .from("household_memberships")
                .select("households!inner(name)")
                .eq("user_id", value: userId.uuidString)
                .eq("role", value: MembershipRole.creator.rawValue)
                .eq("status", value: MembershipStatus.active.rawValue)
                .eq("households.status", value: HouseholdStatus.active.rawValue)
                .execute()
                .value

            let names = records.compactMap { $0.households?.name.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }

            if names.isEmpty {
                showDeleteAccountAlert = true
            } else {
                let groupName: String = {
                    guard let first = names.first, first.isEmpty == false else {
                        return L10n.Family.unknownGroup.string(locale: AppSettingsManager.shared.appLocale)
                    }
                    return first
                }()
                creatorBlockGroupName = groupName
                creatorBlockGroupCount = names.count
                showCreatorBlockAlert = true
            }
        } catch {
            #if DEBUG
            print("检查创建者状态失败: \(error)")
            #endif
            showDeleteAccountAlert = true
        }
        #else
        showDeleteAccountAlert = true
        #endif
    }

    func contactSupport() async {
        guard let url = await SupportMailHelper.makeSupportMailURL() else {
            presentToast(AppLocalized.localized(L10n.Common.unableToOpenSupportEmailPleaseTryAgainLa))
            return
        }
        #if canImport(UIKit)
        guard UIApplication.shared.canOpenURL(url) else {
            presentToast(AppLocalized.localized(L10n.Common.noMailAccountIsConfiguredOnThisDevicePle))
            return
        }
        await UIApplication.shared.open(url)
        #else
        presentToast(AppLocalized.localized(L10n.Common.pleaseEmail.formatted(SupportMailHelper.supportEmail)))
        #endif
    }

    func tapRow(feature: String) {
        presentToast(AppLocalized.localized(L10n.Common.comingSoon.formatted(feature)))
    }

    func showToast(_ message: String) {
        presentToast(message)
    }

    func acknowledgeToast() {
        toastMessage = nil
    }

    func acknowledgeSignOutError() {
        signOutErrorMessage = nil
    }

    func acknowledgeDeleteAccountError() {
        deleteAccountErrorMessage = nil
    }

    private func presentToast(_ message: String) {
        toastMessage = message
    }

    private static func initials(from name: String) -> String {
        let parts = name.split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "@" })
        let letters = parts.prefix(2).compactMap { $0.first }.map(String.init)
        let s = letters.joined().uppercased()
        if s.isEmpty == false { return String(s.prefix(2)) }
        return "QL"
    }

    private func displayNameFromEmail(_ mail: String) -> String {
        let local = mail.split(separator: "@").first.map(String.init) ?? mail
        let parts = local.split(whereSeparator: { $0 == "." || $0 == "_" })
        if parts.count >= 2 {
            return parts.map { p in p.capitalized }.joined(separator: " ")
        }
        return local.capitalized
    }
}

#if canImport(Supabase)
private struct CreatorMembershipRecord: Decodable {
    let households: CreatorHouseholdName?

    struct CreatorHouseholdName: Decodable {
        let name: String
    }
}
#endif

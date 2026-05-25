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
    @Published var isSigningOut = false

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

        #if canImport(Supabase)
        do {
            let supabase = SupabaseManager.shared.client
            try await supabase.auth.signOut()
            await appRouter.refreshStateFromBackend()
        } catch {
            signOutErrorMessage = error.localizedDescription
        }
        #else
        signOutErrorMessage = "当前构建环境未包含 Supabase SDK。"
        #endif
    }

    func tapUpgradeVIP() {
        presentToast("VIP 权益即将开放。")
    }

    func tapDeleteAccount() {
        presentToast("账号注销流程即将提供，请联系支持。")
    }

    func contactSupport() async {
        guard let url = await SupportMailHelper.makeSupportMailURL() else {
            presentToast("无法创建支持邮件，请稍后重试。")
            return
        }
        #if canImport(UIKit)
        guard UIApplication.shared.canOpenURL(url) else {
            presentToast("当前设备未配置邮件账户，请发送邮件至 \(SupportMailHelper.supportEmail)。")
            return
        }
        await UIApplication.shared.open(url)
        #else
        presentToast("请发送邮件至 \(SupportMailHelper.supportEmail)。")
        #endif
    }

    func tapRow(feature: String) {
        presentToast("\(feature) 即将推出。")
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

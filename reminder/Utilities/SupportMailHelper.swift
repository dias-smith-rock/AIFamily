import Foundation

#if canImport(Supabase)
import Supabase
#endif

enum SupportMailHelper {
    static let supportEmail = "music.player.250617@gmail.com"
    static let subject = "Family Link Support"

    static func makeSupportMailURL() async -> URL? {
        let body = await supportEmailBody()
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    private static func supportEmailBody() async -> String {
        let userId = await currentUserIDLine()
        return """
        Hi Family Link Team,

        Please describe your issue below:

        ---

        App Version: \(AppInfo.marketingVersion) (\(AppInfo.buildNumber))
        User ID: \(userId)
        """
    }

    private static func currentUserIDLine() async -> String {
        #if canImport(Supabase)
        if let userId = try? await SupabaseManager.shared.client.auth.session.user.id {
            return userId.uuidString
        }
        #endif
        return "Unknown"
    }
}

enum SupportLegalLinks {
    static let termsOfService = URL(string: "https://www.wefamily.ai/terms")
    static let privacyPolicy = URL(string: "https://www.wefamily.ai/privacy")

    /// 固定英文版（避免按系统语言重定向到 `/zh-CN/...`）。
    static let termsOfServiceEnglish = URL(string: "https://www.wefamily.ai/en/terms")
    static let privacyPolicyEnglish = URL(string: "https://www.wefamily.ai/en/privacy")

    static let appStoreWriteReview = URL(
        string: "https://apps.apple.com/app/id6775353963?action=write-review"
    )
}

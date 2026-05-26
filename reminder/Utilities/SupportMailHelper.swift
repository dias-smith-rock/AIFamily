import Foundation

#if canImport(Supabase)
import Supabase
#endif

enum SupportMailHelper {
    static let supportEmail = "support@wefamily.ai"
    static let subject = "WeFamily Support"

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
        Hi WeFamily Team,

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
}

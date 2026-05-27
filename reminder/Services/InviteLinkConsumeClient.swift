import Foundation

struct ConsumeInviteResult: Decodable {
    let valid: Bool
    let inviteToken: String
    let channel: String
    let nonce: String
}

enum InviteConsumeError: LocalizedError {
    case missingSignature
    case alreadyConsumed
    case expired
    case invalidOrTampered
    case unauthorized
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .missingSignature:
            return AppLocalized.localizedSync("邀请链接缺少签名参数。")
        case .alreadyConsumed:
            return AppLocalized.localizedSync("该邀请链接已被使用（409）。")
        case .expired:
            return AppLocalized.localizedSync("该邀请链接已过期（410）。")
        case .invalidOrTampered:
            return AppLocalized.localizedSync("邀请链接无效或已被篡改。")
        case .unauthorized:
            return AppLocalized.localizedSync("客户端鉴权失败，请检查 apikey。")
        case let .serverError(message):
            return message
        }
    }
}

/// iOS 端调用示例：consume-invite-link
/// - 输入：来自分享链接中的 sig 参数
/// - 输出：是否有效、inviteToken、channel、nonce
struct InviteLinkConsumeClient {
    private let baseURL: URL
    private let anonKey: String

    init(baseURL: URL = SupabaseManager.projectBaseURL, anonKey: String = SupabaseManager.publishableKey) {
        self.baseURL = baseURL
        self.anonKey = anonKey
    }

    func consume(sig: String) async throws -> ConsumeInviteResult {
        let trimmed = sig.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw InviteConsumeError.missingSignature
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("functions/v1/consume-invite-link"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["sig": trimmed])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw InviteConsumeError.serverError(AppLocalized.localizedSync("服务响应异常"))
        }

        switch http.statusCode {
        case 200:
            return try JSONDecoder().decode(ConsumeInviteResult.self, from: data)
        case 400, 404:
            throw InviteConsumeError.invalidOrTampered
        case 401:
            throw InviteConsumeError.unauthorized
        case 409:
            throw InviteConsumeError.alreadyConsumed
        case 410:
            throw InviteConsumeError.expired
        default:
            let message = String(data: data, encoding: .utf8) ?? AppLocalized.localizedSync("未知错误")
            throw InviteConsumeError.serverError(
                AppLocalized.localizedSync("消费邀请链接失败：\(message)")
            )
        }
    }
}

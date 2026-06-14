import Foundation

/// 在不切换 Supabase SDK 当前 session 的前提下，用 HTTP 刷新游客 Keychain 槽位中的 token。
enum GuestArchiveTokenRefresher {
    enum RefreshResult: Sendable {
        case skippedNoArchive
        case success(userId: UUID)
        case failed(statusCode: Int?, message: String)
    }

    private struct RefreshResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let user: UserPayload

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case user
        }
    }

    private struct UserPayload: Decodable {
        let id: UUID
    }

    private struct GoTrueErrorResponse: Decodable {
        let errorCode: String?
        let msg: String?

        enum CodingKeys: String, CodingKey {
            case errorCode = "error_code"
            case msg
        }
    }

    /// 若游客槽位有 refresh token，则向 GoTrue 换票并写回槽位（不触碰 SDK 活跃 session）。
    static func refreshArchivedGuestTokensIfNeeded() async {
        _ = await refreshArchivedGuestTokens(context: "implicit")
    }

    /// HTTP 换票；成功时更新 `GuestSessionArchive` 并返回 `.success`。
    @discardableResult
    static func refreshArchivedGuestTokens(context: String) async -> RefreshResult {
        guard let archived = GuestSessionArchive.load(),
              archived.refreshToken.isEmpty == false
        else {
            return .skippedNoArchive
        }

        return await refreshTokens(
            refreshToken: archived.refreshToken,
            expectedUserId: archived.userId,
            context: context
        )
    }

    /// 用指定 refresh token 换票并写入游客槽位（OAuth 归档时 SDK session 与 archive 对齐后调用）。
    @discardableResult
    static func refreshAndPersistGuestTokens(
        refreshToken: String,
        expectedUserId: UUID,
        context: String
    ) async -> RefreshResult {
        guard refreshToken.isEmpty == false else {
            return .failed(statusCode: nil, message: "empty refresh token")
        }
        return await refreshTokens(
            refreshToken: refreshToken,
            expectedUserId: expectedUserId,
            context: context
        )
    }

    private static func refreshTokens(
        refreshToken: String,
        expectedUserId: UUID,
        context: String
    ) async -> RefreshResult {
        var requestURL = SupabaseEnvironment.supabaseURL
            .appendingPathComponent("auth/v1/token")
        if var components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
            if let url = components.url {
                requestURL = url
            }
        }

        let attempts: [(contentType: String, body: Data?)] = [
            (
                "application/json",
                try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
            ),
            (
                "application/x-www-form-urlencoded",
                "grant_type=refresh_token&refresh_token=\(refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? refreshToken)"
                    .data(using: .utf8)
            ),
        ]

        var lastStatus: Int?
        var lastMessage = "unknown"

        for attempt in attempts {
            guard let body = attempt.body else { continue }

            var request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue(attempt.contentType, forHTTPHeaderField: "Content-Type")
            request.setValue(SupabaseEnvironment.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue(
                "Bearer \(SupabaseEnvironment.supabaseAnonKey)",
                forHTTPHeaderField: "Authorization"
            )
            request.httpBody = body

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                lastStatus = http.statusCode

                guard (200 ... 299).contains(http.statusCode) else {
                    if let goTrueError = try? JSONDecoder().decode(GoTrueErrorResponse.self, from: data) {
                        lastMessage = goTrueError.errorCode ?? goTrueError.msg ?? String(data: data, encoding: .utf8) ?? lastMessage
                    } else {
                        lastMessage = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                    }
                    continue
                }

                let decoded = try JSONDecoder().decode(RefreshResponse.self, from: data)
                guard decoded.user.id == expectedUserId else {
                    lastMessage = "userId mismatch expected=\(expectedUserId.uuidString.lowercased()) got=\(decoded.user.id.uuidString.lowercased())"
                    continue
                }

                GuestSessionArchive.save(
                    PersistedAuthSessionKeychain.Payload(
                        userId: expectedUserId,
                        accessToken: decoded.accessToken,
                        refreshToken: decoded.refreshToken
                    )
                )
                #if DEBUG
                print(
                    "[GuestArchiveTokenRefresher] refreshed context=\(context) userId=\(expectedUserId.uuidString.lowercased())"
                )
                #endif
                return .success(userId: expectedUserId)
            } catch {
                lastMessage = error.localizedDescription
            }
        }

        #if DEBUG
        print(
            "[GuestArchiveTokenRefresher] refresh failed context=\(context) userId=\(expectedUserId.uuidString.lowercased()) status=\(lastStatus.map(String.init) ?? "nil") message=\(lastMessage)"
        )
        #endif
        return .failed(statusCode: lastStatus, message: lastMessage)
    }
}

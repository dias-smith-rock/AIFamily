import Foundation
#if canImport(Supabase)
import Supabase
#endif

struct TaskVoiceRecognitionInput {
    let text: String
    let locale: Locale
    let referenceDate: Date
    let timeZone: TimeZone

    var cloudBody: [String: String] {
        [
            "text": text,
            "reference_instant": ISO8601DateFormatter().string(from: referenceDate),
            "time_zone": timeZone.identifier,
            "locale": locale.identifier(.bcp47),
        ]
    }
}

struct CloudTextTaskParserService {
    func parse(_ input: TaskVoiceRecognitionInput) async throws -> AIParsedTaskPayload {
        #if canImport(Supabase)
        let client = SupabaseManager.shared.client
        do {
            _ = try await client.auth.session
        } catch AuthError.sessionMissing {
            throw CloudTextTaskParserError.sessionExpired
        } catch is URLError {
            try Task.checkCancellation()
            throw CloudTextTaskParserError.connectionFailed
        }
        try Task.checkCancellation()
        return try await parse(input, using: client.functions)
        #else
        throw AITaskParserError.sdkUnavailable
        #endif
    }

    #if canImport(Supabase)
    func parse(_ input: TaskVoiceRecognitionInput, using functions: FunctionsClient) async throws -> AIParsedTaskPayload {
        struct Response: Decodable { let success: Bool; let task: AIParsedTaskPayload? }
        do {
            let result: Response = try await functions.invoke("parse-create-task-from-text",
                options: FunctionInvokeOptions(body: input.cloudBody))
            guard result.success, let task = result.task else { throw AITaskParserError.invalidResponse }
            return task
        } catch FunctionsError.httpError(let status, _) {
            try Task.checkCancellation()
            switch status {
            case 400: throw CloudTextTaskParserError.invalidInput
            case 401: throw CloudTextTaskParserError.sessionExpired
            case 429: throw CloudTextTaskParserError.rateLimited
            default: throw CloudTextTaskParserError.unavailable
            }
        } catch FunctionsError.relayError {
            throw CloudTextTaskParserError.unavailable
        } catch is DecodingError {
            throw AITaskParserError.invalidResponse
        } catch is URLError {
            try Task.checkCancellation()
            throw CloudTextTaskParserError.connectionFailed
        }
    }
    #endif
}

enum CloudTextTaskParserError: LocalizedError {
    case invalidInput, sessionExpired, rateLimited, unavailable, connectionFailed

    var errorDescription: String? {
        switch self {
        case .invalidInput: AppLocalized.localizedSync(L10n.Common.actionFailedPleaseTryAgainLater)
        case .sessionExpired: AppLocalized.localizedSync(L10n.Auth.yourSignInSessionExpiredPleaseSignInAgai)
        case .rateLimited: AppLocalized.localizedSync(L10n.Common.tooManyRequestsPleaseTryAgainLater)
        case .unavailable: AppLocalized.localizedSync(L10n.Common.somethingWentWrongPleaseTryAgainLater)
        case .connectionFailed: AppLocalized.localizedSync(L10n.Common.networkConnectionErrorPleaseCheckYourConne)
        }
    }
}

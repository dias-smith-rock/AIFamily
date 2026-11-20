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
        _ = try await client.auth.session
        struct Response: Decodable { let success: Bool; let task: AIParsedTaskPayload? }
        let result: Response = try await client.functions.invoke("parse-create-task-from-text",
            options: FunctionInvokeOptions(body: input.cloudBody))
        guard result.success, let task = result.task else { throw AITaskParserError.invalidResponse }
        return task
        #else
        throw AITaskParserError.sdkUnavailable
        #endif
    }
}

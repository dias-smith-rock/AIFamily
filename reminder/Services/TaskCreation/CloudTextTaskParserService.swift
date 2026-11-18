import Foundation
#if canImport(Supabase)
import Supabase
#endif

struct CloudTextTaskParserService {
    func parse(_ text: String) async throws -> AIParsedTaskPayload {
        #if canImport(Supabase)
        let client = SupabaseManager.shared.client
        _ = try await client.auth.session
        struct Response: Decodable { let success: Bool; let task: AIParsedTaskPayload? }
        let body = ["text": text, "reference_instant": ISO8601DateFormatter().string(from: Date()),
                    "time_zone": AppDisplayTimeZone.effectiveTimeZone.identifier,
                    "locale": Locale.current.identifier]
        let result: Response = try await client.functions.invoke("parse-create-task-from-text",
            options: FunctionInvokeOptions(body: body))
        guard result.success, let task = result.task else { throw AITaskParserError.invalidResponse }
        return task
        #else
        throw AITaskParserError.sdkUnavailable
        #endif
    }
}

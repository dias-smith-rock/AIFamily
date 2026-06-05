import Foundation

#if canImport(Supabase)
import Supabase
#endif

struct AIParsedTaskPayload: Decodable, Sendable {
    let title: String
    let description: String?
    let dueDate: Date?
    let spatialKeywords: String?

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case dueDate = "due_date"
        case spatialKeywords = "spatial_keywords"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        spatialKeywords = try container.decodeIfPresent(String.self, forKey: .spatialKeywords)

        if let date = try? container.decodeIfPresent(Date.self, forKey: .dueDate) {
            dueDate = date
        } else if let raw = try container.decodeIfPresent(String.self, forKey: .dueDate),
                  raw.isEmpty == false {
            dueDate = AIParsedTaskPayload.parseISO8601(raw)
        } else {
            dueDate = nil
        }
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return formatter.date(from: raw)
    }
}

private struct AIParseTaskImageResponse: Decodable {
    let success: Bool
    let task: AIParsedTaskPayload?
    let error: String?
}

enum AITaskParserError: LocalizedError {
    case sdkUnavailable
    case notAuthenticated
    case uploadFailed
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return String(localized: "当前构建环境未包含 Supabase SDK。")
        case .notAuthenticated:
            return String(localized: "请先登录后再使用 AI 识图创建任务。")
        case .uploadFailed:
            return String(localized: "图片上传失败，请检查网络后重试。")
        case .invalidResponse:
            return String(localized: "AI 返回的数据无法解析，请重试。")
        case .serverError(let message):
            return message
        }
    }
}

/// 上传识图 JPEG → 调用 Edge Function → 解析任务字段。
struct AITaskParserService: Sendable {
    static let storageBucket = "create-task-from-images"
    static let edgeFunctionName = "parse-create-task-from-images"

    func parseTask(fromJPEGData data: Data) async throws -> AIParsedTaskPayload {
        #if canImport(Supabase)
        let client = SupabaseManager.shared.client
        let session = try await client.auth.session
        let userId = session.user.id.uuidString.lowercased()
        let filePath = "tasks/\(userId)_\(UUID().uuidString.lowercased()).jpg"

        do {
            _ = try await client.storage
                .from(Self.storageBucket)
                .upload(
                    filePath,
                    data: data,
                    options: FileOptions(contentType: "image/jpeg", upsert: false)
                )
        } catch {
            #if DEBUG
            print("[AITaskParser] upload failed path=\(filePath) error=\(error.localizedDescription)")
            #endif
            throw AITaskParserError.uploadFailed
        }

        let publicURL = try client.storage
            .from(Self.storageBucket)
            .getPublicURL(path: filePath)

        struct InvokeBody: Encodable {
            let imageUrl: String

            enum CodingKeys: String, CodingKey {
                case imageUrl = "image_url"
            }
        }

        let body = InvokeBody(imageUrl: publicURL.absoluteString)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response: AIParseTaskImageResponse
        do {
            response = try await client.functions.invoke(
                Self.edgeFunctionName,
                options: FunctionInvokeOptions(body: body),
                decoder: decoder
            )
        } catch {
            #if DEBUG
            print("[AITaskParser] edge function failed error=\(error.localizedDescription)")
            #endif
            if let functionsError = error as? FunctionsError,
               case .httpError(_, let responseData) = functionsError,
               let server = try? JSONDecoder().decode(AIParseTaskImageResponse.self, from: responseData),
               let message = server.error {
                throw AITaskParserError.serverError(message)
            }
            throw error
        }

        guard response.success, let task = response.task else {
            let message = response.error ?? String(localized: "图片识别失败，请重试。")
            throw AITaskParserError.serverError(message)
        }

        return task
        #else
        _ = data
        throw AITaskParserError.sdkUnavailable
        #endif
    }
}

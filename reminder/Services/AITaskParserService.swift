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
    let ocrExtract: OcrExtractDebug?
}

private struct OcrExtractDebug: Decodable {
    let stage: String?
    let timestamp: String?
    let model: String?
    let providerBaseUrl: String?
    let charCount: Int?
    let lineCount: Int?
    let lines: [String]?
    let text: String?
}

/// Edge Function 400 响应体（不用 snake_case 转换，避免解码失败）。
private struct AIEdgeFunctionErrorBody: Decodable {
    let success: Bool?
    let error: String?
}

enum AITaskParserError: LocalizedError {
    case sdkUnavailable
    case notAuthenticated
    case uploadFailed(detail: String, isStorageRLS: Bool)
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return String(localized: "当前构建环境未包含 Supabase SDK。")
        case .notAuthenticated:
            return String(localized: "请先登录后再使用 AI 识图创建任务。")
        case .uploadFailed(_, let isStorageRLS):
            if isStorageRLS {
                return String(localized: "图片上传失败，服务器存储权限未配置。请联系管理员在 Supabase 为 create-task-from-images 桶添加写入策略。")
            }
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

        let session: Session
        do {
            session = try await client.auth.session
        } catch {
            AIPhotoTaskCreationLogger.failure(step: .authSessionReady, error: error)
            throw AITaskParserError.notAuthenticated
        }

        let userId = session.user.id.uuidString.lowercased()
        AIPhotoTaskCreationLogger.step(
            .authSessionReady,
            detail: "userId=\(userId.prefix(8))…"
        )

        let fileName = "\(UUID().uuidString.lowercased()).jpg"
        let uploadTargets: [(bucket: String, paths: [String])] = [
            (
                Self.storageBucket,
                ["\(userId)/\(fileName)"]
            ),
            (
                TaskAttachmentSupabaseSupport.bucket,
                [
                    "\(userId)/\(fileName)",
                    fileName,
                ]
            ),
        ]

        AIPhotoTaskCreationLogger.step(
            .storageUploadStarted,
            detail: "primaryBucket=\(Self.storageBucket) fallback=\(TaskAttachmentSupabaseSupport.bucket)",
            byteCount: data.count
        )

        let uploadResult = try await uploadImageData(
            data,
            client: client,
            targets: uploadTargets
        )

        AIPhotoTaskCreationLogger.step(
            .storageUploadSucceeded,
            byteCount: data.count,
            path: "\(uploadResult.bucket)/\(uploadResult.path)"
        )

        let imageAccessURL = try await client.storage
            .from(uploadResult.bucket)
            .createSignedURL(path: uploadResult.path, expiresIn: 600)

        AIPhotoTaskCreationLogger.step(
            .publicURLResolved,
            detail: "signedURL bucket=\(uploadResult.bucket)",
            path: uploadResult.path,
            url: imageAccessURL.absoluteString
        )

        struct InvokeBody: Encodable {
            let imageUrl: String

            enum CodingKeys: String, CodingKey {
                case imageUrl = "image_url"
            }
        }

        let body = InvokeBody(imageUrl: imageAccessURL.absoluteString)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        AIPhotoTaskCreationLogger.step(
            .edgeFunctionStarted,
            detail: "function=\(Self.edgeFunctionName)"
        )

        let response = try await invokeParseEdgeFunction(
            client: client,
            body: body,
            decoder: decoder
        )

        AIPhotoTaskCreationLogger.step(.edgeFunctionSucceeded)

        if let ocr = response.ocrExtract {
            AIPhotoTaskCreationLogger.logOcrExtract(
                AIPhotoTaskCreationLogger.OcrExtractDebugLog(
                    stage: ocr.stage,
                    timestamp: ocr.timestamp,
                    model: ocr.model,
                    charCount: ocr.charCount,
                    lineCount: ocr.lineCount,
                    lines: ocr.lines,
                    text: ocr.text
                )
            )
        }

        guard response.success, let task = response.task else {
            let message = response.error ?? String(localized: "图片识别失败，请重试。")
            AIPhotoTaskCreationLogger.failure(
                step: .parseResponseInvalid,
                error: AITaskParserError.serverError(message),
                detail: "success=\(response.success)"
            )
            throw AITaskParserError.serverError(message)
        }

        AIPhotoTaskCreationLogger.step(
            .parseResponseSucceeded,
            detail: "title=\(task.title.prefix(40))"
        )

        return task
        #else
        _ = data
        throw AITaskParserError.sdkUnavailable
        #endif
    }

    #if canImport(Supabase)
    private struct UploadResult {
        let bucket: String
        let path: String
    }

    private func invokeParseEdgeFunction(
        client: SupabaseClient,
        body: some Encodable,
        decoder: JSONDecoder
    ) async throws -> AIParseTaskImageResponse {
        do {
            return try await client.functions.invoke(
                Self.edgeFunctionName,
                options: FunctionInvokeOptions(body: body),
                decoder: decoder
            )
        } catch {
            if let functionsError = error as? FunctionsError,
               case .httpError(let code, let responseData) = functionsError {
                let bodyText = String(data: responseData, encoding: .utf8) ?? ""
                AIPhotoTaskCreationLogger.failure(
                    step: .edgeFunctionFailed,
                    error: error,
                    detail: "http=\(code) body=\(bodyText)"
                )

                if let parsed = try? JSONDecoder().decode(AIEdgeFunctionErrorBody.self, from: responseData),
                   let message = parsed.error?.trimmingCharacters(in: .whitespacesAndNewlines),
                   message.isEmpty == false {
                    throw AITaskParserError.serverError(message)
                }
                if bodyText.isEmpty == false {
                    throw AITaskParserError.serverError(bodyText)
                }
            } else {
                AIPhotoTaskCreationLogger.failure(
                    step: .edgeFunctionFailed,
                    error: error,
                    detail: AIPhotoTaskCreationLogger.describe(error)
                )
            }
            throw error
        }
    }

    private func uploadImageData(
        _ data: Data,
        client: SupabaseClient,
        targets: [(bucket: String, paths: [String])]
    ) async throws -> UploadResult {
        var lastError: Error?
        var sawStorageRLS = false

        for target in targets {
            for path in target.paths {
                do {
                    _ = try await client.storage
                        .from(target.bucket)
                        .upload(
                            path,
                            data: data,
                            options: FileOptions(contentType: "image/jpeg", upsert: false)
                        )
                    if target.bucket != Self.storageBucket {
                        AIPhotoTaskCreationLogger.step(
                            .storageUploadSucceeded,
                            detail: "usedFallbackBucket=\(target.bucket)"
                        )
                    }
                    return UploadResult(bucket: target.bucket, path: path)
                } catch {
                    lastError = error
                    if Self.isStorageRLSViolation(error) {
                        sawStorageRLS = true
                    }
                    AIPhotoTaskCreationLogger.failure(
                        step: .storageUploadFailed,
                        error: error,
                        detail: "bucket=\(target.bucket) path=\(path)"
                    )
                }
            }
        }

        let detail = lastError.map { AIPhotoTaskCreationLogger.describe($0) } ?? "unknown"
        throw AITaskParserError.uploadFailed(detail: detail, isStorageRLS: sawStorageRLS)
    }

    private static func isStorageRLSViolation(_ error: Error) -> Bool {
        if let storageError = error as? StorageError {
            if storageError.statusCode == "403" { return true }
            if storageError.message.localizedCaseInsensitiveContains("row-level security") {
                return true
            }
        }
        let text = String(describing: error).lowercased()
        return text.contains("403") && text.contains("row-level security")
    }
    #endif
}

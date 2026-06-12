import Foundation

#if canImport(Supabase)
import Supabase
#endif

struct AIParsedTaskPayload: Decodable, Sendable {
    let title: String
    let description: String?
    let dueDate: Date?
    let endDatetime: Date?
    let isAllDay: Bool
    let durationMinutes: Int?
    let amountYuan: Double?
    let spatialKeywords: String?
    let participantHints: [String]
    let priority: String?
    let taskTypeHint: String?

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case dueDate = "due_date"
        case endDatetime = "end_datetime"
        case isAllDay = "is_all_day"
        case durationMinutes = "duration_minutes"
        case amountYuan = "amount_yuan"
        case spatialKeywords = "spatial_keywords"
        case participantHints = "participant_hints"
        case priority
        case taskTypeHint = "task_type_hint"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        spatialKeywords = try container.decodeIfPresent(String.self, forKey: .spatialKeywords)
        isAllDay = try container.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
        amountYuan = Self.decodeAmountYuan(from: container)
        participantHints = try container.decodeIfPresent([String].self, forKey: .participantHints) ?? []
        priority = try container.decodeIfPresent(String.self, forKey: .priority)
        taskTypeHint = try container.decodeIfPresent(String.self, forKey: .taskTypeHint)
        dueDate = Self.decodeOptionalDate(from: container, forKey: .dueDate)
        endDatetime = Self.decodeOptionalDate(from: container, forKey: .endDatetime)
    }

    var isPriorityUrgent: Bool {
        guard let priority else { return false }
        return priority.lowercased() == "high"
    }

    var prefersFlexibleTask: Bool {
        taskTypeHint?.lowercased() == "flexible"
    }

    var costDisplayString: String? {
        guard let amountYuan, amountYuan > 0 else { return nil }
        if amountYuan.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", amountYuan)
        }
        return String(format: "%.2f", amountYuan)
    }

    private static func decodeAmountYuan(from container: KeyedDecodingContainer<CodingKeys>) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: .amountYuan) {
            return value
        }
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: .amountYuan) {
            return Double(intValue)
        }
        if let raw = try? container.decodeIfPresent(String.self, forKey: .amountYuan),
           let value = Double(raw.replacingOccurrences(of: ",", with: "")) {
            return value
        }
        return nil
    }

    private static func decodeOptionalDate(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Date? {
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return date
        }
        if let raw = try? container.decodeIfPresent(String.self, forKey: key),
           raw.isEmpty == false {
            return parseISO8601(raw)
        }
        return nil
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
            return L10n.Common.supabaseSdkIsNotAvailableInThisBuild.string()
        case .notAuthenticated:
            return L10n.Auth.pleaseLogInFirstBeforeUsingAiToCreateA.string()
        case .uploadFailed(_, let isStorageRLS):
            if isStorageRLS {
                return L10n.Common.uploadFailedStoragePermissionsAreNotConfig.string()
            }
            return L10n.Common.imageUploadFailedPleaseCheckTheNetworkAnd.string()
        case .invalidResponse:
            return L10n.Common.couldNotParseTheDataReturnedByAiPleaseT.string()
        case .serverError(let message):
            return AITaskParserUserMessage.mapServerRawText(message) ?? message
        }
    }
}

/// 识图流程上传到 Supabase 的临时文件位置（识别完成后应删除）。
struct AITemporaryStorageUpload: Sendable {
    let bucket: String
    let path: String
}

struct AIParseTaskResult: Sendable {
    let task: AIParsedTaskPayload
    let temporaryUpload: AITemporaryStorageUpload
}

/// 上传识图 JPEG → 调用 Edge Function → 解析任务字段。
struct AITaskParserService: Sendable {
    static let storageBucket = "create-task-from-images"
    static let edgeFunctionName = "parse-create-task-from-images"

    private static func iso8601DateString(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    func parseTask(
        fromJPEGData data: Data,
        targetDate: Date? = nil,
        recognitionRegion: NormalizedCropQuad? = nil
    ) async throws -> AIParseTaskResult {
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
        let temporaryUpload = AITemporaryStorageUpload(
            bucket: uploadResult.bucket,
            path: uploadResult.path
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
            let targetDate: String?
            let recognitionRegion: RecognitionRegionPayload?

            enum CodingKeys: String, CodingKey {
                case imageUrl = "image_url"
                case targetDate = "target_date"
                case recognitionRegion = "recognition_region"
            }
        }

        let targetDateString = targetDate.map { Self.iso8601DateString(for: $0) }
        let body = InvokeBody(
            imageUrl: imageAccessURL.absoluteString,
            targetDate: targetDateString,
            recognitionRegion: recognitionRegion?.apiPayload
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        AIPhotoTaskCreationLogger.step(
            .edgeFunctionStarted,
            detail: "function=\(Self.edgeFunctionName) targetDate=\(targetDateString ?? "nil") region=\(recognitionRegion != nil)"
        )

        let response: AIParseTaskImageResponse
        do {
            response = try await invokeParseEdgeFunction(
                client: client,
                body: body,
                decoder: decoder
            )
        } catch {
            await deleteTemporaryUpload(temporaryUpload)
            throw error
        }

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
            let message = response.error ?? L10n.Common.imageRecognitionFailedPleaseTryAgain.string()
            AIPhotoTaskCreationLogger.failure(
                step: .parseResponseInvalid,
                error: AITaskParserError.serverError(message),
                detail: "success=\(response.success)"
            )
            await deleteTemporaryUpload(temporaryUpload)
            throw AITaskParserError.serverError(message)
        }

        AIPhotoTaskCreationLogger.step(
            .parseResponseSucceeded,
            detail: "title=\(task.title.prefix(40))"
        )

        return AIParseTaskResult(task: task, temporaryUpload: temporaryUpload)
        #else
        _ = data
        throw AITaskParserError.sdkUnavailable
        #endif
    }

    func deleteTemporaryUpload(_ upload: AITemporaryStorageUpload) async {
        #if canImport(Supabase)
        await Self.deleteTemporaryUpload(
            client: SupabaseManager.shared.client,
            bucket: upload.bucket,
            path: upload.path
        )
        #else
        _ = upload
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

    private static func deleteTemporaryUpload(
        client: SupabaseClient,
        bucket: String,
        path: String
    ) async {
        do {
            _ = try await client.storage
                .from(bucket)
                .remove(paths: [path])
            AIPhotoTaskCreationLogger.step(
                .storageDeleteSucceeded,
                detail: "bucket=\(bucket)",
                path: path
            )
        } catch {
            AIPhotoTaskCreationLogger.failure(
                step: .storageDeleteFailed,
                error: error,
                detail: "bucket=\(bucket) path=\(path)"
            )
        }
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

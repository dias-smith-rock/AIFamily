import Foundation
import UIKit

#if canImport(Supabase)
import Supabase
#endif

enum TaskAttachmentSupabaseSupport {
    static let bucket = "task_attachments"
    static let mimeType = "image/jpeg"

    private static let tableSelectColumns = """
        id,\
        task_id,\
        file_url,\
        file_type,\
        file_size_bytes,\
        created_by,\
        created_at
        """

    struct UploadedFile: Sendable, Equatable {
        var fileUrl: String
        var fileSizeBytes: Int64
        var fileType: String
    }

    /// 并发上传 JPEG 至 `task_attachments` 桶。
    @MainActor
    static func uploadImages(_ images: [UIImage], householdId: UUID) async throws -> [UploadedFile] {
        let payloads = images.compactMap { image in
            image.jpegData(compressionQuality: 0.7)
        }
        guard payloads.count == images.count else {
            throw TaskAttachmentSupabaseError.imageEncodingFailed
        }
        return try await uploadJPEGData(payloads, householdId: householdId)
    }

    /// 直接上传已编码 JPEG（用于 AI 识图等已压缩的裁剪图，避免重新编码）。
    @MainActor
    static func uploadJPEGData(_ payloads: [Data], householdId: UUID) async throws -> [UploadedFile] {
        guard payloads.isEmpty == false else { return [] }

        #if canImport(Supabase)
        let client = SupabaseManager.shared.client
        let session = try await client.auth.session
        let userFolder = session.user.id.uuidString.lowercased()
        let householdFolder = householdId.uuidString.lowercased()

        return try await withThrowingTaskGroup(of: UploadedFile.self) { group in
            for data in payloads {
                group.addTask {
                    try await uploadSingleJPEG(
                        data: data,
                        client: client,
                        userFolder: userFolder,
                        householdFolder: householdFolder
                    )
                }
            }

            var uploads: [UploadedFile] = []
            uploads.reserveCapacity(payloads.count)
            for try await upload in group {
                uploads.append(upload)
            }
            return uploads
        }
        #else
        _ = payloads
        _ = householdId
        return []
        #endif
    }

    #if canImport(Supabase)
    private static func uploadSingleJPEG(
        data: Data,
        client: SupabaseClient,
        userFolder: String,
        householdFolder: String
    ) async throws -> UploadedFile {
        let fileName = "\(UUID().uuidString).jpg"
        let candidatePaths = [
            "\(userFolder)/\(fileName)",
            "\(householdFolder)/\(fileName)",
            fileName,
        ]

        var lastError: Error?
        for path in candidatePaths {
            do {
                _ = try await client.storage
                    .from(bucket)
                    .upload(
                        path,
                        data: data,
                        options: FileOptions(contentType: mimeType, upsert: false)
                    )
                let url = try client.storage
                    .from(bucket)
                    .getPublicURL(path: path)
                    .absoluteString
                return UploadedFile(
                    fileUrl: url,
                    fileSizeBytes: Int64(data.count),
                    fileType: mimeType
                )
            } catch {
                lastError = error
                #if DEBUG
                print("[TaskAttachmentUpload] failed path=\(path) error=\(error.localizedDescription)")
                #endif
            }
        }

        throw lastError ?? TaskAttachmentSupabaseError.uploadFailed
    }
    #endif

    @MainActor
    static func fetchRecords(taskId: UUID) async throws -> [TaskAttachment] {
        #if canImport(Supabase)
        let rows: [TaskAttachment] = try await SupabaseManager.shared.client
            .from("task_attachments")
            .select(tableSelectColumns)
            .eq("task_id", value: taskId.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
        return rows
        #else
        _ = taskId
        throw TaskAttachmentSupabaseError.sdkUnavailable
        #endif
    }

    @MainActor
    static func deleteRecords(ids: [UUID]) async throws {
        guard ids.isEmpty == false else { return }

        #if canImport(Supabase)
        let idStrings = ids.map { $0.uuidString.lowercased() }
        try await SupabaseManager.shared.client
            .from("task_attachments")
            .delete()
            .in("id", values: idStrings)
            .execute()
        #else
        _ = ids
        throw TaskAttachmentSupabaseError.sdkUnavailable
        #endif
    }

    @MainActor
    static func insertRecords(taskId: UUID, uploads: [UploadedFile]) async throws {
        guard uploads.isEmpty == false else { return }

        #if canImport(Supabase)
        let rows = uploads.map {
            TaskAttachmentInsertRow(
                taskId: taskId,
                fileUrl: $0.fileUrl,
                fileType: $0.fileType,
                fileSizeBytes: $0.fileSizeBytes
            )
        }
        print("👉 准备向 task_attachments 插入 \(rows.count) 条数据...")
        print("👉 关联的 Task ID 为: \(taskId.uuidString)")

        do {
            _ = try await SupabaseManager.shared.client
                .from("task_attachments")
                .insert(rows)
                .execute()
            print("✅ 附件记录写入数据库成功！")
        } catch {
            print("❌ 附件表写入彻底失败，报错详情: \(error)")
            print("❌ 报错数据的具体内容: \(rows)")
            throw error
        }
        #else
        _ = taskId
        _ = uploads
        throw TaskAttachmentSupabaseError.sdkUnavailable
        #endif
    }

    /// 兼容仅 URL 列表的写入（无 `file_size_bytes`）。
    @MainActor
    static func insertRecords(taskId: UUID, fileURLs: [String]) async throws {
        let uploads = fileURLs.map {
            UploadedFile(fileUrl: $0, fileSizeBytes: 0, fileType: mimeType)
        }
        try await insertRecords(taskId: taskId, uploads: uploads)
    }

    /// 仅上传并返回公共 URL（不写表）。
    @MainActor
    static func uploadImageURLs(_ images: [UIImage], householdId: UUID) async throws -> [String] {
        try await uploadImages(images, householdId: householdId).map(\.fileUrl)
    }
}

enum TaskAttachmentSupabaseError: LocalizedError {
    case imageEncodingFailed
    case sdkUnavailable
    case taskPayloadAssemblyFailed
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            return String(localized: "图片压缩失败，请重试。")
        case .sdkUnavailable:
            return String(localized: "当前构建环境未包含 Supabase SDK。")
        case .taskPayloadAssemblyFailed:
            return String(localized: "任务数据组装失败，请重试。")
        case .uploadFailed:
            return String(localized: "附件上传失败，请稍后重试。")
        }
    }
}

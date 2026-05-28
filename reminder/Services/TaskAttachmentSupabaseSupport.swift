import Foundation
import UIKit

#if canImport(Supabase)
import Supabase
#endif

enum TaskAttachmentSupabaseSupport {
    static let bucket = "task_attachments"
    static let mimeType = "image/jpeg"

    /// 并发上传 JPEG 至 `task_attachments` 桶，返回公共 URL 列表（顺序不保证与输入一致）。
    @MainActor
    static func uploadImages(_ images: [UIImage], householdId: UUID) async throws -> [String] {
        guard images.isEmpty == false else { return [] }

        #if canImport(Supabase)
        let client = SupabaseManager.shared.client
        let session = try await client.auth.session
        let userFolder = session.user.id.uuidString.lowercased()
        let householdFolder = householdId.uuidString.lowercased()

        return try await withThrowingTaskGroup(of: String.self) { group in
            for image in images {
                group.addTask {
                    guard let data = image.jpegData(compressionQuality: 0.7) else {
                        throw TaskAttachmentSupabaseError.imageEncodingFailed
                    }
                    let fileName = "\(UUID().uuidString).jpg"
                    let candidatePaths = [
                        "\(userFolder)/\(fileName)",
                        "\(householdFolder)/\(fileName)",
                        fileName
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
                            return try client.storage
                                .from(bucket)
                                .getPublicURL(path: path)
                                .absoluteString
                        } catch {
                            lastError = error
                            #if DEBUG
                            print("[TaskAttachmentUpload] failed path=\(path) error=\(error.localizedDescription)")
                            #endif
                        }
                    }

                    throw lastError ?? TaskAttachmentSupabaseError.uploadFailed
                }
            }

            var urls: [String] = []
            urls.reserveCapacity(images.count)
            for try await url in group {
                urls.append(url)
            }
            return urls
        }
        #else
        _ = images
        _ = householdId
        throw TaskAttachmentSupabaseError.sdkUnavailable
        #endif
    }

    @MainActor
    static func insertRecords(taskId: UUID, fileURLs: [String]) async throws {
        guard fileURLs.isEmpty == false else { return }

        #if canImport(Supabase)
        let rows = fileURLs.map {
            TaskAttachment(taskId: taskId, fileUrl: $0, fileType: mimeType)
        }
        print("👉 准备向 task_attachments 插入 \(rows.count) 条数据...")
        print("👉 关联的 Task ID 为: \(rows.first?.taskId.uuidString ?? "空")")

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
        _ = fileURLs
        throw TaskAttachmentSupabaseError.sdkUnavailable
        #endif
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

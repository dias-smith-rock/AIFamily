import Foundation

/// `public.task_attachments` 表行（与 Supabase 表结构一致）。
struct TaskAttachment: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var taskId: UUID
    var fileUrl: String
    var fileType: String
    var fileSizeBytes: Int64?
    var createdBy: UUID?
    var createdAt: Date?

    /// 与 `SupabaseCodec` 的 snake_case ↔ 驼峰策略一致，勿写 `= "task_id"`。
    enum CodingKeys: String, CodingKey {
        case id
        case taskId
        case fileUrl
        case fileType
        case fileSizeBytes
        case createdBy
        case createdAt
    }

    init(
        id: UUID = UUID(),
        taskId: UUID,
        fileUrl: String,
        fileType: String,
        fileSizeBytes: Int64? = nil,
        createdBy: UUID? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.fileUrl = fileUrl
        self.fileType = fileType
        self.fileSizeBytes = fileSizeBytes
        self.createdBy = createdBy
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try Self.decodeRequiredUUID(container: container, key: .id)
        taskId = try Self.decodeRequiredUUID(container: container, key: .taskId)
        fileUrl = try container.decode(String.self, forKey: .fileUrl)
        fileType = try container.decodeIfPresent(String.self, forKey: .fileType) ?? "image/jpeg"
        fileSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .fileSizeBytes)
        createdBy = try Self.decodeOptionalUUID(container: container, key: .createdBy)
        createdAt = try Self.decodeOptionalDate(container: container, key: .createdAt)
    }

    private static func decodeRequiredUUID(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> UUID {
        if let uuid = try? container.decode(UUID.self, forKey: key) {
            return uuid
        }
        let raw = try container.decode(String.self, forKey: key)
        guard let uuid = UUID(uuidString: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Invalid UUID: \(raw)"
            )
        }
        return uuid
    }

    private static func decodeOptionalUUID(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> UUID? {
        if let uuid = try? container.decodeIfPresent(UUID.self, forKey: key) {
            return uuid
        }
        guard let raw = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    private static func decodeOptionalDate(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> Date? {
        try container.decodeIfPresent(Date.self, forKey: key)
    }
}

extension TaskAttachment {
    var displayImageURL: URL? {
        SupabasePublicStorageURL.resolve(
            storedValue: fileUrl,
            bucket: SupabaseStorageBuckets.taskAttachments
        )
    }
}

/// 写入 `task_attachments` 时的载荷；`id` / `created_by` / `created_at` 由数据库默认生成。
struct TaskAttachmentInsertRow: Encodable, Equatable, Sendable {
    var taskId: UUID
    var fileUrl: String
    var fileType: String
    var fileSizeBytes: Int64?

    enum CodingKeys: String, CodingKey {
        case taskId
        case fileUrl
        case fileType
        case fileSizeBytes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(taskId, forKey: .taskId)
        try container.encode(fileUrl, forKey: .fileUrl)
        try container.encode(fileType, forKey: .fileType)
        if let fileSizeBytes, fileSizeBytes > 0 {
            try container.encode(fileSizeBytes, forKey: .fileSizeBytes)
        }
    }
}

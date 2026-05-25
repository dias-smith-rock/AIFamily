import Foundation

enum SupabaseStorageBuckets {
    static let voiceFeedbacks = "voice-feedbacks"
    static let avatars = "avatars"
}

enum SupabasePublicStorageURL {
    /// 将 DB 中的相对路径或完整 public URL 解析为可访问的绝对 URL。
    static func resolve(storedValue: String?, bucket: String) -> URL? {
        guard let raw = storedValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return nil
        }

        if raw.contains("://"), let absolute = URL(string: raw) {
            return absolute
        }

        var url = SupabaseEnvironment.supabaseURL
            .appendingPathComponent("storage/v1/object/public")
            .appendingPathComponent(bucket)

        for component in raw.split(separator: "/") {
            url = url.appendingPathComponent(String(component))
        }
        return url
    }
}

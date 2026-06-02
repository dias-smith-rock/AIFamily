import Foundation

/// 将 `Codable` 数据以 JSON 形式写入应用 Caches 目录，用于冷启动与离线兜底展示。
final class LocalCacheManager {
    static let shared = LocalCacheManager()

    private let ioQueue = DispatchQueue(label: "com.aifamily.localcache", qos: .utility)
    private let fileManager = FileManager.default
    /// 与 `SupabaseManager` / PostgREST 一致，避免与模型 `CodingKeys` 的 snake 策略冲突。
    private let encoder = SupabaseCodec.makeEncoder()
    private let decoder = SupabaseCodec.makeDecoder()
    private let cacheDirectoryURL: URL

    private init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = base.appendingPathComponent("AIFamilyLocalCache", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheDirectoryURL = dir
    }

    func save<T: Codable>(_ object: T, forKey key: String) {
        ioQueue.async { [encoder, fileManager, cacheDirectoryURL] in
            let url = Self.fileURL(forKey: key, directory: cacheDirectoryURL)
            do {
                let data = try encoder.encode(object)
                try data.write(to: url, options: [.atomic])
            } catch {
                #if DEBUG
                print("⚠️ [LocalCache] save failed key=\(key) error=\(error.localizedDescription)")
                #endif
            }
        }
    }

    func load<T: Codable>(forKey key: String) -> T? {
        let url = Self.fileURL(forKey: key, directory: cacheDirectoryURL)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("⚠️ [LocalCache] load failed key=\(key) error=\(error.localizedDescription)")
            #endif
            return nil
        }
    }

    func remove(forKey key: String) {
        let url = Self.fileURL(forKey: key, directory: cacheDirectoryURL)
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            #if DEBUG
            print("⚠️ [LocalCache] remove failed key=\(key) error=\(error.localizedDescription)")
            #endif
        }
    }

    func removeAll() {
        ioQueue.async { [fileManager, cacheDirectoryURL] in
            do {
                let files = try fileManager.contentsOfDirectory(
                    at: cacheDirectoryURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                for url in files {
                    try? fileManager.removeItem(at: url)
                }
            } catch {
                #if DEBUG
                print("⚠️ [LocalCache] removeAll failed error=\(error.localizedDescription)")
                #endif
            }
        }
    }

    private static func fileURL(forKey key: String, directory: URL) -> URL {
        let safeName = key
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._")))
            ?? "default"
        return directory.appendingPathComponent(safeName + ".json", isDirectory: false)
    }
}

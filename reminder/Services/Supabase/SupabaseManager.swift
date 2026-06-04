import Foundation

#if canImport(Supabase)
import Supabase
#endif

// MARK: - Environment

/// 按编译配置切换本地 / 云端，避免把本地与线上 URL、密钥混在同一套常量里。
/// - Note: 本地 REST API 端口以 `supabase/config.toml` 的 `[api].port` 为准（默认 54321）；54323 一般为 Studio。
enum SupabaseEnvironment {
    static var supabaseURL: URL {
        #if DEBUG
//        return urlOrFail("https://murkiness-gamma-sporting.ngrok-free.dev")
        return urlOrFail("https://dirgcwziayipwvwztjbb.supabase.co")
        #else
        return urlOrFail("https://dirgcwziayipwvwztjbb.supabase.co")
        #endif
    }

    static var supabaseAnonKey: String {
        #if DEBUG
        // 运行 `supabase status` 核对本地 anon key；未改动时为 CLI 默认 JWT。
//        return "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
        return "sb_publishable_j7V-u1tMxcessnU4qQZe6g_x29a4l_Y"
        #else
        return "sb_publishable_j7V-u1tMxcessnU4qQZe6g_x29a4l_Y"
        #endif
    }

    private static func urlOrFail(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid Supabase URL string: \(string)")
        }
        return url
    }
}

// MARK: - Codec Strategies

/// 全局编解码策略：
/// - 写入时把驼峰 → snake_case，匹配 PostgREST 字段命名。
/// - 读取时把 snake_case → 驼峰，让 Swift 模型直接以驼峰命名属性。
/// - 时间统一按 ISO8601 处理，兼容含/不含毫秒、含/不含时区偏移的情况。
enum SupabaseCodec {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFormatterWithFractional.string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { try decodePostgresTimestamp(from: $0) }
        return decoder
    }

    /// 模型 `CodingKeys` 已写 PostgREST 列名字面量（如 `history_location_1`）时使用，避免 snake 策略冲突。
    static func makeLiteralColumnDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .custom { try decodePostgresTimestamp(from: $0) }
        return decoder
    }

    private static func decodePostgresTimestamp(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)

        if let date = isoFormatterWithFractional.date(from: raw) {
            return date
        }
        if let date = isoFormatterPlain.date(from: raw) {
            return date
        }
        if let date = postgresFormatter.date(from: raw) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported date format: \(raw)"
        )
    }

    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Postgres `timestamp with time zone` 在 PostgREST 序列化时常见格式：
    /// `2026-04-27T08:30:00.123456+00:00`。这里覆盖六位小数 + 偏移量的兜底解析。
    private static let postgresFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        return formatter
    }()
}

// MARK: - SupabaseManager

final class SupabaseManager {
    static let shared = SupabaseManager()

    static var publishableKey: String { SupabaseEnvironment.supabaseAnonKey }

    static var projectURLString: String { SupabaseEnvironment.supabaseURL.absoluteString }

    static var projectBaseURL: URL { SupabaseEnvironment.supabaseURL }

    private init() {}

    #if canImport(Supabase)
    let client: SupabaseClient = {
        let options = SupabaseClientOptions(
            db: SupabaseClientOptions.DatabaseOptions(
                encoder: SupabaseCodec.makeEncoder(),
                decoder: SupabaseCodec.makeDecoder()
            )
        )
        return SupabaseClient(
            supabaseURL: SupabaseEnvironment.supabaseURL,
            supabaseKey: SupabaseEnvironment.supabaseAnonKey,
            options: options
        )
    }()

    /// Connectivity smoke test for Supabase. 拉取一条 households 记录验证可达性。
    func testConnection() async {
        do {
            let rows: [Household] = try await client
                .from("households")
                .select()
                .limit(1)
                .execute()
                .value

            if let first = rows.first {
                print("Supabase connected. First household: \(first.name)")
            } else {
                print("Supabase connected. `households` 可达，但当前账号尚无可见家庭。")
            }
        } catch {
            print("Supabase connection test failed: \(error.localizedDescription)")
        }
    }
    #else
    func testConnection() async {
        print("Supabase SDK is unavailable in current build environment.")
    }
    #endif
}

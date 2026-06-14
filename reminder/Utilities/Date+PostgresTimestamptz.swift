import Foundation

extension Date {
    /// Postgres `timestamptz` 兼容 ISO8601（毫秒 + `Z`）。
    var postgresTimestamptzString: String {
        Self.postgresTimestamptzFormatter.string(from: self)
    }

    private static let postgresTimestamptzFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

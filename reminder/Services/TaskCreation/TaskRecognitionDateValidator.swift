import Foundation

/// Strict local Gregorian dates: reject rollover and DST gaps/overlaps instead of guessing.
enum TaskRecognitionDateValidator {
    static func date(_ raw: String, timeZone: TimeZone, allDay: Bool = false) -> Date? {
        let pattern = allDay ? #"^\d{4}-\d{2}-\d{2}$"# : #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$"#
        guard raw.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let values = raw.split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
        guard values.count == (allDay ? 3 : 5), values[0] >= 1900 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: values[0], month: values[1], day: values[2],
                                        hour: allDay ? 0 : values[3], minute: allDay ? 0 : values[4])
        guard let result = calendar.date(from: components) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result)
        guard roundTrip == components else { return nil }
        if !allDay {
            let anchor = calendar.startOfDay(for: result).addingTimeInterval(-1)
            let clock = DateComponents(hour: values[3], minute: values[4])
            let first = calendar.nextDate(after: anchor, matching: clock, matchingPolicy: .strict, repeatedTimePolicy: .first)
            let last = calendar.nextDate(after: anchor, matching: clock, matchingPolicy: .strict, repeatedTimePolicy: .last)
            guard first == last else { return nil }
        }
        return result
    }
}

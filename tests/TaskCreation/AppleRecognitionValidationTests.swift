import Foundation

@main struct ValidationTests {
    static func main() throws {
        let zone = TimeZone(identifier: "America/New_York")!
        assert(TaskRecognitionDateValidator.date("2026-02-30T15:00", timeZone: zone) == nil)
        assert(TaskRecognitionDateValidator.date("2026-03-08T02:30", timeZone: zone) == nil)
        assert(TaskRecognitionDateValidator.date("2026-11-01T01:30", timeZone: zone) == nil)
        assert(TaskRecognitionDateValidator.date("2026-11-19T15:00", timeZone: zone) != nil)
        assert(TaskRecognitionDateValidator.date("2026-11-19", timeZone: zone) == nil)
        assert(TaskRecognitionDateValidator.date("2026-11-19", timeZone: zone, allDay: true) != nil)
        assert(TaskRecognitionDateValidator.date("2026-11-19T09:00:00Z", timeZone: zone) == nil)
        print("Apple extraction date validation: 7 checks passed")
    }
}

import Foundation

enum LocationTrailSegmentFilter {
    /// 轨迹段与半开区间 `[start, end)` 相交。
    static func segments(
        _ segments: [LocationTrailSegment],
        intersecting interval: DateInterval
    ) -> [LocationTrailSegment] {
        segments.filter { segment in
            segment.endedAt >= interval.start && segment.startedAt < interval.end
        }
    }

    static func trailFetchCutoff(
        for historyDateRange: LocationHistoryDateRange,
        now: Date = Date(),
        calendar: Calendar = AppDisplayTimeZone.calendar()
    ) -> Date {
        let interval = historyDateRange.interval(now: now, calendar: calendar)
        let retentionStart = Date().addingTimeInterval(-SupabaseLocationTrailDataService.defaultRetention)
        return max(interval.start, retentionStart)
    }
}

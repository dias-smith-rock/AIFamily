import Foundation
import CoreGraphics

/// 日程周视图切换、侧滑换周与首屏渲染性能埋点（前缀 `[WeekViewPerf]`）。
/// 仅记录日志，不改变业务逻辑。
@MainActor
enum WeekViewPerformanceTracer {
    private struct CounterSnapshot {
        var weekBodyAppearCount = 0
        var weekHeaderPageAppearCount = 0
        var timelineScrollAppearCount = 0
        var geometryLayoutPassCount = 0
        var layoutEngineCallCount = 0
        var layoutEngineTotalMs = 0
        var tasksFilterCallCount = 0
        var tasksFilterTotalMs = 0
        var gridCanvasDrawCount = 0
        var scrollToNowAttemptCount = 0
        var scrollToNowSkipCount = 0
        var scrollToNowInvokeCount = 0
        var scrollAnchorAppearCount = 0
        var timelinePlaceholderAppearCount = 0
    }

    private static var sessionActive = false
    private static var firstPaintActive = false
    private static var swipeActive = false

    private static var sessionOriginSeconds: CFAbsoluteTime?
    private static var lastMarkSeconds: CFAbsoluteTime?
    private static var sessionTraceID: String = ""
    private static var sessionEntryPath: String = ""

    private static var firstPaintFinishTask: Task<Void, Never>?
    private static var swipeFinishTask: Task<Void, Never>?

    private static var pendingWeekOffsetChangeSource: String?
    private static var swipeID: String = ""
    private static var swipeOriginSeconds: CFAbsoluteTime?
    private static var swipeFromOffset: Int?
    private static var swipeToOffset: Int?
    private static var swipeSource: String = ""
    private static var swipeBaseline = CounterSnapshot()

    private static var counters = CounterSnapshot()
    private static var weekBodyAppearOffsets: [Int] = []
    private static var weekHeaderAppearOffsets: [Int] = []

    static let logPrefix = "[WeekViewPerf]"

    static var traceIsActive: Bool { sessionActive }

    // MARK: - Session lifecycle

    static func beginTrace(
        entryPath: String,
        scheduledTaskCount: Int,
        totalTaskCount: Int
    ) {
        endSession()
        let now = nowSeconds()
        sessionEntryPath = entryPath
        sessionTraceID = String(UUID().uuidString.prefix(8)).lowercased()
        sessionOriginSeconds = now
        lastMarkSeconds = now
        sessionActive = true
        firstPaintActive = true
        resetCounters()
        log(
            phase: "session",
            label: "trace.begin",
            note: [
                "entryPath=\(entryPath)",
                "tabViewPageCount=\(ScheduleWeekCalendar.pagerSlotCount)",
                "scheduledTaskCount=\(scheduledTaskCount)",
                "totalTaskCount=\(totalTaskCount)",
                "gridHeightPt=\(Int(WeekGridMetrics.gridHeight))",
            ].joined(separator: " ")
        )
    }

    static func cancelTrace(reason: String) {
        guard sessionActive else { return }
        if swipeActive {
            finishSwipeSummary(reason: "sessionCancelled")
        }
        print("\(logPrefix) trace.cancel reason=\(reason) traceId=\(sessionTraceID) entryPath=\(sessionEntryPath)")
        endSession()
    }

    static func scheduleFinishFirstPaintSummary(after seconds: TimeInterval = 2.0) {
        guard sessionActive, firstPaintActive else { return }
        firstPaintFinishTask?.cancel()
        firstPaintFinishTask = Task {
            let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard Task.isCancelled == false, sessionActive, firstPaintActive else { return }
            finishFirstPaintSummary()
        }
    }

    static func finishFirstPaintSummary() {
        guard sessionActive, firstPaintActive else { return }
        firstPaintFinishTask?.cancel()
        firstPaintActive = false
        log(
            phase: "firstPaint",
            label: "trace.summary.firstPaint",
            note: counterSummary()
        )
        if let origin = sessionOriginSeconds {
            let totalMs = elapsedMilliseconds(since: origin, until: nowSeconds())
            print("\(logPrefix) trace.finish.firstPaint totalMs=\(totalMs) traceId=\(sessionTraceID) entryPath=\(sessionEntryPath)")
        }
    }

    // MARK: - Swipe lifecycle

    static func notePendingWeekOffsetChange(source: String) {
        pendingWeekOffsetChangeSource = source
    }

    static func recordWeekOffsetChange(from oldOffset: Int, to newOffset: Int) {
        guard sessionActive, oldOffset != newOffset else { return }

        let source = pendingWeekOffsetChangeSource ?? "tabViewSwipe"
        pendingWeekOffsetChangeSource = nil

        if source == "initialAppearSync" {
            log(
                phase: "session",
                label: "weekOffset.sync",
                note: "from=\(oldOffset) to=\(newOffset) source=\(source)"
            )
            return
        }

        if swipeActive {
            swipeToOffset = newOffset
            log(
                phase: "swipe",
                label: "swipe.update",
                note: "swipeId=\(swipeID) from=\(swipeFromOffset ?? oldOffset) to=\(newOffset) source=\(source)"
            )
            scheduleSwipeSummary()
            return
        }

        beginSwipeTrace(from: oldOffset, to: newOffset, source: source)
    }

    static func scheduleSwipeSummary(after seconds: TimeInterval = 0.45) {
        guard sessionActive, swipeActive else { return }
        swipeFinishTask?.cancel()
        swipeFinishTask = Task {
            let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard Task.isCancelled == false, sessionActive, swipeActive else { return }
            finishSwipeSummary(reason: "settled")
        }
    }

    // MARK: - Marks

    static func mark(_ label: String, note: String? = nil) {
        guard sessionActive else { return }
        log(phase: "session", label: label, note: note)
    }

    static func recordWeekBodyAppear(offset: Int) {
        guard sessionActive else { return }
        counters.weekBodyAppearCount += 1
        weekBodyAppearOffsets.append(offset)
        let note = "offset=\(offset) cumulative=\(counters.weekBodyAppearCount)"
        if swipeActive {
            log(phase: "swipe", label: "weekBody.onAppear", note: note)
        } else if counters.weekBodyAppearCount <= 8 || counters.weekBodyAppearCount % 10 == 0 {
            log(phase: "session", label: "weekBody.onAppear", note: note)
        }
    }

    static func recordWeekHeaderPageAppear(offset: Int) {
        guard sessionActive else { return }
        counters.weekHeaderPageAppearCount += 1
        weekHeaderAppearOffsets.append(offset)
        let note = "offset=\(offset) cumulative=\(counters.weekHeaderPageAppearCount)"
        if swipeActive {
            log(phase: "swipe", label: "weekHeaderPage.onAppear", note: note)
        } else if counters.weekHeaderPageAppearCount <= 8 || counters.weekHeaderPageAppearCount % 10 == 0 {
            log(phase: "session", label: "weekHeaderPage.onAppear", note: note)
        }
    }

    static func recordTimelineScrollAppear(weekOffset: Int, weekTaskCount: Int) {
        guard sessionActive else { return }
        counters.timelineScrollAppearCount += 1
        let note = "weekOffset=\(weekOffset) weekTaskCount=\(weekTaskCount) cumulative=\(counters.timelineScrollAppearCount)"
        if swipeActive {
            log(phase: "swipe", label: "timelineScrollArea.onAppear", note: note)
        } else {
            log(phase: "session", label: "timelineScrollArea.onAppear", note: note)
        }
        scheduleFinishFirstPaintSummary()
    }

    static func recordGeometryLayoutPass(columnWidth: CGFloat, weekTaskCount: Int) {
        guard sessionActive else { return }
        counters.geometryLayoutPassCount += 1
        let shouldLog = swipeActive
            || counters.geometryLayoutPassCount <= 5
            || counters.geometryLayoutPassCount % 10 == 0
        guard shouldLog else { return }
        log(
            phase: swipeActive ? "swipe" : "session",
            label: "geometryReader.layoutPass",
            note: "pass=\(counters.geometryLayoutPassCount) columnWidth=\(String(format: "%.1f", columnWidth)) weekTaskCount=\(weekTaskCount)"
        )
    }

    static func recordGridCanvasDraw() {
        guard sessionActive else { return }
        counters.gridCanvasDrawCount += 1
        let shouldLog = swipeActive
            || counters.gridCanvasDrawCount <= 5
            || counters.gridCanvasDrawCount % 20 == 0
        guard shouldLog else { return }
        log(
            phase: swipeActive ? "swipe" : "session",
            label: "weekGridCanvas.draw",
            note: "cumulative=\(counters.gridCanvasDrawCount)"
        )
    }

    static func measureLayoutEngine<T>(
        taskCount: Int,
        columnWidth: CGFloat,
        operation: () -> T
    ) -> T {
        guard sessionActive else { return operation() }
        counters.layoutEngineCallCount += 1
        let stepStart = nowSeconds()
        let result = operation()
        let stepMs = elapsedMilliseconds(since: stepStart, until: nowSeconds())
        counters.layoutEngineTotalMs += stepMs
        let shouldLog = swipeActive
            || counters.layoutEngineCallCount <= 5
            || counters.layoutEngineCallCount % 10 == 0
        if shouldLog {
            log(
                phase: swipeActive ? "swipe" : "session",
                label: "layoutEngine.run",
                note: "call=\(counters.layoutEngineCallCount) stepMs=\(stepMs) taskCount=\(taskCount) columnWidth=\(String(format: "%.1f", columnWidth)) cumulativeMs=\(counters.layoutEngineTotalMs)"
            )
        }
        return result
    }

    static func measureTasksFilter<T>(
        scheduledTaskCount: Int,
        operation: () -> T
    ) -> T {
        guard sessionActive else { return operation() }
        counters.tasksFilterCallCount += 1
        let stepStart = nowSeconds()
        let result = operation()
        let stepMs = elapsedMilliseconds(since: stepStart, until: nowSeconds())
        counters.tasksFilterTotalMs += stepMs
        let shouldLog = swipeActive
            || counters.tasksFilterCallCount <= 5
            || counters.tasksFilterCallCount % 20 == 0
        if shouldLog {
            log(
                phase: swipeActive ? "swipe" : "session",
                label: "tasksFilter.run",
                note: "call=\(counters.tasksFilterCallCount) stepMs=\(stepMs) scheduledTaskCount=\(scheduledTaskCount) cumulativeMs=\(counters.tasksFilterTotalMs)"
            )
        }
        return result
    }

    // MARK: - Scroll to now (diagnostics only)

    static func recordTimelinePlaceholderAppear(
        displayedWeekOffset: Int,
        isCenterPage: Bool,
        isCurrentWeekTimelineReady: Bool
    ) {
        guard sessionActive else { return }
        counters.timelinePlaceholderAppearCount += 1
        log(
            phase: "scrollToNow",
            label: "timeline.placeholder.onAppear",
            note: [
                "displayedWeekOffset=\(displayedWeekOffset)",
                "isCenterPage=\(isCenterPage)",
                "isCurrentWeekTimelineReady=\(isCurrentWeekTimelineReady)",
                "cumulative=\(counters.timelinePlaceholderAppearCount)",
            ].joined(separator: " ")
        )
    }

    static func recordScrollAnchorAppear(
        displayedWeekOffset: Int,
        nowY: CGFloat?,
        anchorOffsetY: CGFloat?,
        anchorID: String,
        anchorParent: String = "hourRow"
    ) {
        guard sessionActive else { return }
        counters.scrollAnchorAppearCount += 1
        log(
            phase: "scrollToNow",
            label: "scrollAnchor.onAppear",
            note: [
                "anchorID=\(anchorID)",
                "displayedWeekOffset=\(displayedWeekOffset)",
                "nowY=\(formatCGFloat(nowY))",
                "anchorOffsetY=\(formatCGFloat(anchorOffsetY))",
                "anchorParent=\(anchorParent)",
                "cumulative=\(counters.scrollAnchorAppearCount)",
            ].joined(separator: " ")
        )
    }

    static func recordScrollToNowAttempt(
        source: String,
        displayedWeekOffset: Int,
        weekOffset: Int,
        pagerSlot: Int,
        isCurrentWeekTimelineReady: Bool,
        isAdjacentWeekPagesReady: Bool,
        containsToday: Bool,
        isDisplayingCurrentWeek: Bool,
        nowY: CGFloat?,
        anchorID: String,
        animated: Bool
    ) {
        guard sessionActive else { return }
        counters.scrollToNowAttemptCount += 1
        log(
            phase: "scrollToNow",
            label: "scrollToNow.attempt",
            note: [
                "source=\(source)",
                "displayedWeekOffset=\(displayedWeekOffset)",
                "weekOffset=\(weekOffset)",
                "offsetMatches=\(displayedWeekOffset == weekOffset)",
                "pagerSlot=\(pagerSlot)",
                "isCurrentWeekTimelineReady=\(isCurrentWeekTimelineReady)",
                "isAdjacentWeekPagesReady=\(isAdjacentWeekPagesReady)",
                "containsToday=\(containsToday)",
                "isDisplayingCurrentWeek=\(isDisplayingCurrentWeek)",
                "nowY=\(nowY.map(formatCGFloat) ?? "nil")",
                "anchorID=\(anchorID)",
                "scrollAnchorViewportAnchor=0.34",
                "animated=\(animated)",
                "cumulative=\(counters.scrollToNowAttemptCount)",
            ].joined(separator: " ")
        )
    }

    static func recordScrollToNowSkipped(source: String, reason: String) {
        guard sessionActive else { return }
        counters.scrollToNowSkipCount += 1
        log(
            phase: "scrollToNow",
            label: "scrollToNow.skipped",
            note: "source=\(source) reason=\(reason) cumulative=\(counters.scrollToNowSkipCount)"
        )
    }

    static func recordScrollToNowInvoked(
        source: String,
        anchorID: String,
        anchorOffsetY: CGFloat?,
        animated: Bool
    ) {
        guard sessionActive else { return }
        counters.scrollToNowInvokeCount += 1
        log(
            phase: "scrollToNow",
            label: "scrollToNow.invoked",
            note: [
                "source=\(source)",
                "anchorID=\(anchorID)",
                "anchorOffsetY=\(anchorOffsetY.map(formatCGFloat) ?? "nil")",
                "scrollAnchorViewportAnchor=0.34",
                "animated=\(animated)",
                "cumulative=\(counters.scrollToNowInvokeCount)",
            ].joined(separator: " ")
        )
    }

    static func recordFirstPaintExpandScrollContext(
        weekOffset: Int,
        isDisplayingCurrentWeek: Bool,
        isCurrentWeekTimelineReadyBefore: Bool
    ) {
        guard sessionActive else { return }
        log(
            phase: "scrollToNow",
            label: "firstPaint.expand.scrollContext",
            note: [
                "weekOffset=\(weekOffset)",
                "isDisplayingCurrentWeek=\(isDisplayingCurrentWeek)",
                "isCurrentWeekTimelineReadyBefore=\(isCurrentWeekTimelineReadyBefore)",
            ].joined(separator: " ")
        )
    }

    private static func formatCGFloat(_ value: CGFloat?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.1f", value)
    }

    // MARK: - Swipe internals

    private static func beginSwipeTrace(from oldOffset: Int, to newOffset: Int, source: String) {
        swipeFinishTask?.cancel()
        swipeActive = true
        swipeID = String(UUID().uuidString.prefix(6)).lowercased()
        swipeOriginSeconds = nowSeconds()
        swipeFromOffset = oldOffset
        swipeToOffset = newOffset
        swipeSource = source
        swipeBaseline = counters
        log(
            phase: "swipe",
            label: "swipe.begin",
            note: "swipeId=\(swipeID) from=\(oldOffset) to=\(newOffset) source=\(source)"
        )
        scheduleSwipeSummary()
    }

    private static func finishSwipeSummary(reason: String) {
        guard sessionActive, swipeActive else { return }
        swipeFinishTask?.cancel()
        let delta = counterDelta(since: swipeBaseline)
        let from = swipeFromOffset.map(String.init) ?? "nil"
        let to = swipeToOffset.map(String.init) ?? "nil"
        log(
            phase: "swipe",
            label: "swipe.summary",
            note: [
                "reason=\(reason)",
                "swipeId=\(swipeID)",
                "from=\(from)",
                "to=\(to)",
                "source=\(swipeSource)",
                delta,
            ].joined(separator: " ")
        )
        if let origin = swipeOriginSeconds {
            let swipeMs = elapsedMilliseconds(since: origin, until: nowSeconds())
            print("\(logPrefix) swipe.finish swipeMs=\(swipeMs) swipeId=\(swipeID) from=\(from) to=\(to) source=\(swipeSource) traceId=\(sessionTraceID)")
        }
        swipeActive = false
        swipeID = ""
        swipeOriginSeconds = nil
        swipeFromOffset = nil
        swipeToOffset = nil
        swipeSource = ""
    }

    // MARK: - Logging

    private static func log(phase: String, label: String, note: String?) {
        let now = nowSeconds()
        var parts: [String] = [
            logPrefix,
            "phase=\(phase)",
            "traceId=\(sessionTraceID)",
            "entryPath=\(sessionEntryPath)",
            "label=\(label)",
        ]
        if let origin = sessionOriginSeconds {
            parts.append("sessionMs=\(elapsedMilliseconds(since: origin, until: now))")
        }
        if swipeActive, let swipeOrigin = swipeOriginSeconds {
            parts.append("swipeMs=\(elapsedMilliseconds(since: swipeOrigin, until: now))")
            parts.append("swipeId=\(swipeID)")
        }
        if let last = lastMarkSeconds {
            parts.append("deltaMs=\(elapsedMilliseconds(since: last, until: now))")
        }
        if let note, note.isEmpty == false {
            parts.append("note=\(note)")
        }
        print(parts.joined(separator: " "))
        lastMarkSeconds = now
    }

    private static func counterSummary() -> String {
        let bodyOffsetSample = summarizedOffsets(weekBodyAppearOffsets)
        let headerOffsetSample = summarizedOffsets(weekHeaderAppearOffsets)
        return [
            "weekBodyAppearCount=\(counters.weekBodyAppearCount)",
            "weekHeaderPageAppearCount=\(counters.weekHeaderPageAppearCount)",
            "timelineScrollAppearCount=\(counters.timelineScrollAppearCount)",
            "geometryLayoutPassCount=\(counters.geometryLayoutPassCount)",
            "layoutEngineCallCount=\(counters.layoutEngineCallCount)",
            "layoutEngineTotalMs=\(counters.layoutEngineTotalMs)",
            "tasksFilterCallCount=\(counters.tasksFilterCallCount)",
            "tasksFilterTotalMs=\(counters.tasksFilterTotalMs)",
            "gridCanvasDrawCount=\(counters.gridCanvasDrawCount)",
            "scrollToNowAttemptCount=\(counters.scrollToNowAttemptCount)",
            "scrollToNowSkipCount=\(counters.scrollToNowSkipCount)",
            "scrollToNowInvokeCount=\(counters.scrollToNowInvokeCount)",
            "scrollAnchorAppearCount=\(counters.scrollAnchorAppearCount)",
            "timelinePlaceholderAppearCount=\(counters.timelinePlaceholderAppearCount)",
            "weekBodyOffsetSample=\(bodyOffsetSample)",
            "weekHeaderOffsetSample=\(headerOffsetSample)",
        ].joined(separator: " ")
    }

    private static func counterDelta(since baseline: CounterSnapshot) -> String {
        [
            "deltaWeekBodyAppear=\(counters.weekBodyAppearCount - baseline.weekBodyAppearCount)",
            "deltaWeekHeaderPageAppear=\(counters.weekHeaderPageAppearCount - baseline.weekHeaderPageAppearCount)",
            "deltaTimelineScrollAppear=\(counters.timelineScrollAppearCount - baseline.timelineScrollAppearCount)",
            "deltaGeometryLayoutPass=\(counters.geometryLayoutPassCount - baseline.geometryLayoutPassCount)",
            "deltaLayoutEngineCall=\(counters.layoutEngineCallCount - baseline.layoutEngineCallCount)",
            "deltaLayoutEngineMs=\(counters.layoutEngineTotalMs - baseline.layoutEngineTotalMs)",
            "deltaTasksFilterCall=\(counters.tasksFilterCallCount - baseline.tasksFilterCallCount)",
            "deltaTasksFilterMs=\(counters.tasksFilterTotalMs - baseline.tasksFilterTotalMs)",
            "deltaGridCanvasDraw=\(counters.gridCanvasDrawCount - baseline.gridCanvasDrawCount)",
        ].joined(separator: " ")
    }

    private static func summarizedOffsets(_ offsets: [Int]) -> String {
        guard offsets.isEmpty == false else { return "none" }
        let prefix = offsets.prefix(8).map(String.init).joined(separator: ",")
        if offsets.count > 8 {
            return "\(prefix),...(\(offsets.count) total)"
        }
        return prefix
    }

    private static func nowSeconds() -> CFAbsoluteTime {
        CFAbsoluteTimeGetCurrent()
    }

    private static func elapsedMilliseconds(
        since start: CFAbsoluteTime,
        until end: CFAbsoluteTime
    ) -> Int {
        Int((end - start) * 1000)
    }

    private static func resetCounters() {
        counters = CounterSnapshot()
        weekBodyAppearOffsets = []
        weekHeaderAppearOffsets = []
    }

    private static func endSession() {
        firstPaintFinishTask?.cancel()
        swipeFinishTask?.cancel()
        firstPaintFinishTask = nil
        swipeFinishTask = nil
        sessionActive = false
        firstPaintActive = false
        swipeActive = false
        sessionOriginSeconds = nil
        lastMarkSeconds = nil
        sessionTraceID = ""
        sessionEntryPath = ""
        pendingWeekOffsetChangeSource = nil
        swipeID = ""
        swipeOriginSeconds = nil
        swipeFromOffset = nil
        swipeToOffset = nil
        swipeSource = ""
        swipeBaseline = CounterSnapshot()
        resetCounters()
    }
}

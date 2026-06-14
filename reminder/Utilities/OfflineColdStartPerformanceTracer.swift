import Foundation

/// 离线 + 已登录冷启动 → 主界面 的性能埋点（前缀 `[OfflineColdStartPerf]`）。
/// 仅记录日志，不改变业务逻辑。
@MainActor
enum OfflineColdStartPerformanceTracer {
    private static var traceOriginSeconds: CFAbsoluteTime?
    private static var lastMarkSeconds: CFAbsoluteTime?
    private static var traceID: String = ""
    private static var isActive = false

    static let logPrefix = "[OfflineColdStartPerf]"

    static var traceIsActive: Bool { isActive }

    // MARK: - Trace lifecycle

    /// 冷启动且已登录、首帧网络为离线时开启追踪链。
    static func beginTrace(networkConnectedAtStart: Bool) {
        guard isActive == false else { return }
        let now = nowSeconds()
        traceID = String(UUID().uuidString.prefix(8)).lowercased()
        traceOriginSeconds = now
        lastMarkSeconds = now
        isActive = true
        log(
            label: "trace.begin",
            note: "path=offlineColdStartLoggedIn networkConnectedAtStart=\(networkConnectedAtStart)"
        )
    }

    static func finishMainPageReached(appRouter: AppRouter?) {
        guard isActive else { return }
        log(
            label: "trace.finish.mainPage",
            note: routerSummary(appRouter),
            appRouter: appRouter
        )
        if let origin = traceOriginSeconds {
            let totalMs = elapsedMilliseconds(since: origin, until: nowSeconds())
            print("\(logPrefix) trace.finish totalMs=\(totalMs) traceId=\(traceID)")
        }
        resetTrace()
    }

    static func cancelTrace(reason: String) {
        guard isActive else { return }
        print("\(logPrefix) trace.cancel reason=\(reason) traceId=\(traceID)")
        resetTrace()
    }

    // MARK: - Marks

    static func mark(
        _ label: String,
        note: String? = nil,
        appRouter: AppRouter? = nil
    ) {
        guard isActive else { return }
        log(label: label, note: note, appRouter: appRouter)
    }

    static func measure<T>(
        _ label: String,
        note: String? = nil,
        appRouter: AppRouter? = nil,
        operation: () async throws -> T
    ) async rethrows -> T {
        mark("\(label).begin", note: note, appRouter: appRouter)
        let stepStart = nowSeconds()
        let result = try await operation()
        let stepMs = elapsedMilliseconds(since: stepStart, until: nowSeconds())
        mark("\(label).end", note: joinNote(note, "stepMs=\(stepMs)"), appRouter: appRouter)
        return result
    }

    static func measure<T>(
        _ label: String,
        note: String? = nil,
        appRouter: AppRouter? = nil,
        operation: () async -> T
    ) async -> T {
        mark("\(label).begin", note: note, appRouter: appRouter)
        let stepStart = nowSeconds()
        let result = await operation()
        let stepMs = elapsedMilliseconds(since: stepStart, until: nowSeconds())
        mark("\(label).end", note: joinNote(note, "stepMs=\(stepMs)"), appRouter: appRouter)
        return result
    }

    // MARK: - Logging

    private static func log(
        label: String,
        note: String?,
        appRouter: AppRouter? = nil
    ) {
        let now = nowSeconds()
        var parts: [String] = [
            logPrefix,
            "traceId=\(traceID)",
            "label=\(label)",
        ]
        if let origin = traceOriginSeconds {
            parts.append("totalMs=\(elapsedMilliseconds(since: origin, until: now))")
        }
        if let last = lastMarkSeconds {
            parts.append("deltaMs=\(elapsedMilliseconds(since: last, until: now))")
        }
        if let appRouter {
            parts.append(contentsOf: routerFields(appRouter))
        }
        if let note, note.isEmpty == false {
            parts.append("note=\(note)")
        }
        print(parts.joined(separator: " "))
        lastMarkSeconds = now
    }

    private static func routerFields(_ appRouter: AppRouter) -> [String] {
        [
            "appState=\(appRouter.appState.perfTraceName)",
            "authUserId=\(uuidString(appRouter.authUserId))",
            "isAnonymous=\(appRouter.isAnonymousUser)",
            "householdId=\(uuidString(appRouter.selectedHouseholdId))",
            "selectableCount=\(appRouter.selectableHouseholds.count)",
            "hasCompletedBootstrap=\(appRouter.hasCompletedAuthBootstrap)",
            "isResolvingRouting=\(appRouter.isResolvingHouseholdRouting)",
        ]
    }

    private static func routerSummary(_ appRouter: AppRouter?) -> String {
        guard let appRouter else { return "router=nil" }
        return [
            "appState=\(appRouter.appState.perfTraceName)",
            "householdId=\(uuidString(appRouter.selectedHouseholdId))",
            "isAnonymous=\(appRouter.isAnonymousUser)",
        ].joined(separator: " ")
    }

    private static func uuidString(_ id: UUID?) -> String {
        id?.uuidString.lowercased() ?? "nil"
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

    private static func joinNote(_ lhs: String?, _ rhs: String) -> String {
        guard let lhs, lhs.isEmpty == false else { return rhs }
        return "\(lhs) \(rhs)"
    }

    private static func resetTrace() {
        isActive = false
        traceOriginSeconds = nil
        lastMarkSeconds = nil
        traceID = ""
    }
}

/// 冷启动 Splash / launchBootstrap 埋点：同时写入 `[AutoLoginPerf]` 与 `[OfflineColdStartPerf]`（后者仅离线 trace 活跃时输出）。
@MainActor
enum LaunchBootstrapPerformanceTracing {
    static func beginColdStartTraceIfNeeded(isUserLoggedIn: Bool) {
        AutoLoginPerformanceTracer.beginColdStartTraceIfNeeded(isUserLoggedIn: isUserLoggedIn)
    }

    static func mark(
        _ label: String,
        note: String? = nil,
        appRouter: AppRouter? = nil
    ) {
        AutoLoginPerformanceTracer.mark(label, note: note, appRouter: appRouter)
        OfflineColdStartPerformanceTracer.mark(label, note: note, appRouter: appRouter)
    }

    static func cancelTrace(reason: String) {
        AutoLoginPerformanceTracer.cancelTrace(reason: reason)
        OfflineColdStartPerformanceTracer.cancelTrace(reason: reason)
    }

    static func measure<T>(
        _ label: String,
        note: String? = nil,
        appRouter: AppRouter? = nil,
        operation: () async throws -> T
    ) async rethrows -> T {
        if OfflineColdStartPerformanceTracer.traceIsActive {
            return try await OfflineColdStartPerformanceTracer.measure(
                label,
                note: note,
                appRouter: appRouter,
                operation: operation
            )
        }
        return try await AutoLoginPerformanceTracer.measure(
            label,
            note: note,
            appRouter: appRouter,
            operation: operation
        )
    }

    static func measure<T>(
        _ label: String,
        note: String? = nil,
        appRouter: AppRouter? = nil,
        operation: () async -> T
    ) async -> T {
        if OfflineColdStartPerformanceTracer.traceIsActive {
            return await OfflineColdStartPerformanceTracer.measure(
                label,
                note: note,
                appRouter: appRouter,
                operation: operation
            )
        }
        return await AutoLoginPerformanceTracer.measure(
            label,
            note: note,
            appRouter: appRouter,
            operation: operation
        )
    }
}

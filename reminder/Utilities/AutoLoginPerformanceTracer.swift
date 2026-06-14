import Foundation

/// 冷启动 Google / 正式账号自动登录 → 主界面 的性能埋点（前缀 `[AutoLoginPerf]`）。
/// 仅记录日志，不改变业务逻辑。
@MainActor
enum AutoLoginPerformanceTracer {
    private static var traceOriginSeconds: CFAbsoluteTime?
    private static var lastMarkSeconds: CFAbsoluteTime?
    private static var traceID: String = ""
    private static var isActive = false

    static let logPrefix = "[AutoLoginPerf]"

    // MARK: - Trace lifecycle

    /// 冷启动且 `isUserLoggedIn == true` 时开启一条追踪链（自动恢复 Google / 正式账号）。
    static func beginColdStartTraceIfNeeded(isUserLoggedIn: Bool) {
        guard isUserLoggedIn, isActive == false else { return }
        let now = nowSeconds()
        traceID = String(UUID().uuidString.prefix(8)).lowercased()
        traceOriginSeconds = now
        lastMarkSeconds = now
        isActive = true
        log(label: "trace.begin", note: "path=coldStartAutoLogin")
    }

    /// 主界面（Tab 根）已展示，结束追踪并输出总耗时。
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

    /// 无活跃 trace 时也输出（网络门闩、云同步等全局埋点）。
    static func logAlways(
        _ label: String,
        note: String? = nil,
        appRouter: AppRouter? = nil
    ) {
        if isActive {
            log(label: label, note: note, appRouter: appRouter)
        } else {
            var parts: [String] = [logPrefix, "label=\(label)"]
            if let appRouter {
                parts.append(contentsOf: routerFields(appRouter))
            }
            if let note, note.isEmpty == false {
                parts.append("note=\(note)")
            }
            print(parts.joined(separator: " "))
        }
    }

    /// 包裹异步步骤，自动打 begin / end 及耗时。
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

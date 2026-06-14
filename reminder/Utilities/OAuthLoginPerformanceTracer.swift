import Foundation

/// Google / OAuth 手动登录 → 主界面 的性能埋点（前缀 `[GoogleOAuthPerf]`）。
/// 仅记录日志，不改变业务逻辑。
@MainActor
enum OAuthLoginPerformanceTracer {
    private static var traceOriginSeconds: CFAbsoluteTime?
    private static var lastMarkSeconds: CFAbsoluteTime?
    private static var traceID: String = ""
    private static var provider: String = ""
    private static var isActive = false

    static let logPrefix = "[GoogleOAuthPerf]"

    static var traceIsActive: Bool { isActive }

    // MARK: - Trace lifecycle

    static func beginTrace(provider: String) {
        guard isActive == false else { return }
        let now = nowSeconds()
        self.provider = provider
        traceID = String(UUID().uuidString.prefix(8)).lowercased()
        traceOriginSeconds = now
        lastMarkSeconds = now
        isActive = true
        log(label: "trace.begin", note: "provider=\(provider) path=manualOAuthLogin")
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
            print("\(logPrefix) trace.finish totalMs=\(totalMs) traceId=\(traceID) provider=\(provider)")
        }
        resetTrace()
    }

    static func cancelTrace(reason: String) {
        guard isActive else { return }
        print("\(logPrefix) trace.cancel reason=\(reason) traceId=\(traceID) provider=\(provider)")
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
            "provider=\(provider)",
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
        provider = ""
    }
}

/// 冷启动 `[AutoLoginPerf]` 与手动 OAuth `[GoogleOAuthPerf]` 共用埋点入口；inactive 的 tracer 自动跳过。
@MainActor
enum LoginFlowPerformanceTracing {
    static func mark(
        _ label: String,
        note: String? = nil,
        appRouter: AppRouter? = nil
    ) {
        AutoLoginPerformanceTracer.mark(label, note: note, appRouter: appRouter)
        OAuthLoginPerformanceTracer.mark(label, note: note, appRouter: appRouter)
    }

    static func logAlways(
        _ label: String,
        note: String? = nil,
        appRouter: AppRouter? = nil
    ) {
        AutoLoginPerformanceTracer.logAlways(label, note: note, appRouter: appRouter)
        OAuthLoginPerformanceTracer.mark(label, note: note, appRouter: appRouter)
    }

    static func measure<T>(
        _ label: String,
        note: String? = nil,
        appRouter: AppRouter? = nil,
        operation: () async throws -> T
    ) async rethrows -> T {
        if OAuthLoginPerformanceTracer.traceIsActive {
            return try await OAuthLoginPerformanceTracer.measure(
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
        if OAuthLoginPerformanceTracer.traceIsActive {
            return await OAuthLoginPerformanceTracer.measure(
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

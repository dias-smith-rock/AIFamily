import CoreLocation
import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// 前台/退后台位置入库编排：统一跳过原因日志，退后台时用 `beginBackgroundTask` 争取完成 GPS + 网络。
@MainActor
enum LocationPersistSession {
    private static let logPrefix = "[LocationPersist]"

    struct Context: Sendable {
        let isUserLoggedIn: Bool
        let isUnlockedForLocation: Bool
        let appState: AppRouter.AppState
        let householdId: UUID?
        let profileId: UUID?
        let backgroundLocationEnabled: Bool
    }

    static func logSkip(trigger: LocationPersistTrigger, reason: String, context: Context) {
        let household = context.householdId?.uuidString.prefix(8) ?? "none"
        let profile = context.profileId?.uuidString.prefix(8) ?? "none"
        print(
            "\(logPrefix) trigger=\(trigger.rawValue) skipped reason=\(reason) "
                + "household=\(household) profile=\(profile) "
                + "backgroundMode=\(context.backgroundLocationEnabled) appState=\(context.appState)"
        )
    }

    static func perform(
        trigger: LocationPersistTrigger,
        context: Context,
        locationStateService: LocationStateDataService,
        allowWhenBackgroundLocationEnabled: Bool = false
    ) async {
        print(
            "\(logPrefix) trigger=\(trigger.rawValue) begin "
                + "backgroundMode=\(context.backgroundLocationEnabled) "
                + "allowWhenBackgroundMode=\(allowWhenBackgroundLocationEnabled)"
        )

        if allowWhenBackgroundLocationEnabled == false, context.backgroundLocationEnabled {
            logSkip(
                trigger: trigger,
                reason: "backgroundLocationEnabled (foreground-only path; enable Always or turn off toggle)",
                context: context
            )
            return
        }

        guard context.isUserLoggedIn else {
            logSkip(trigger: trigger, reason: "notLoggedIn", context: context)
            return
        }

        guard context.isUnlockedForLocation else {
            logSkip(trigger: trigger, reason: "lockedByFaceID", context: context)
            return
        }

        guard context.appState == .activeMember else {
            logSkip(trigger: trigger, reason: "appStateNotActiveMember", context: context)
            return
        }

        guard context.householdId != nil, context.profileId != nil else {
            logSkip(trigger: trigger, reason: "missingHouseholdOrProfile", context: context)
            return
        }

        if trigger == .appEnteringBackground {
            await runWithBackgroundTaskIfAvailable(name: "LocationPersist.appEnteringBackground") {
                await LocationStartupReporter.report(
                    trigger: trigger,
                    householdId: context.householdId,
                    profileId: context.profileId,
                    locationStateService: locationStateService
                )
            }
        } else {
            await LocationStartupReporter.report(
                trigger: trigger,
                householdId: context.householdId,
                profileId: context.profileId,
                locationStateService: locationStateService
            )
        }

        print("\(logPrefix) trigger=\(trigger.rawValue) end")
    }

    private static func runWithBackgroundTaskIfAvailable(
        name: String,
        operation: @escaping @MainActor () async -> Void
    ) async {
        #if canImport(UIKit)
        let application = UIApplication.shared
        var taskIdentifier: UIBackgroundTaskIdentifier = .invalid
        taskIdentifier = application.beginBackgroundTask(withName: name) {
            print("\(logPrefix) backgroundTask expired name=\(name)")
            if taskIdentifier != .invalid {
                application.endBackgroundTask(taskIdentifier)
                taskIdentifier = .invalid
            }
        }

        if taskIdentifier == .invalid {
            print("\(logPrefix) backgroundTask unavailable name=\(name) running inline")
            await operation()
            return
        }

        print("\(logPrefix) backgroundTask began id=\(taskIdentifier.rawValue) name=\(name)")
        let completed = await runOperationWithTimeout(seconds: 25, operation: operation)
        application.endBackgroundTask(taskIdentifier)
        print(
            "\(logPrefix) backgroundTask ended id=\(taskIdentifier.rawValue) name=\(name) "
                + "completed=\(completed)"
        )
        #else
        await operation()
        #endif
    }

    @MainActor
    private static func runOperationWithTimeout(
        seconds: TimeInterval,
        operation: @escaping @MainActor () async -> Void
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await operation()
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                print("\(logPrefix) backgroundTask operation timed out after \(Int(seconds))s")
                return false
            }
            let finished = await group.next() ?? false
            group.cancelAll()
            return finished
        }
    }
}

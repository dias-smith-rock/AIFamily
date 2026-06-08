import Foundation

#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

/// 非致命错误与 Crashlytics 上下文；崩溃采集由 SDK 自动处理。
enum CrashReporting {
    static func configureAfterFirebaseStartup() {
        #if canImport(FirebaseCrashlytics)
        #if DEBUG
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        #else
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        #endif
        #if DEBUG
        print("[Crashlytics] collection enabled: false (DEBUG)")
        #endif
        #endif
    }

    static func record(_ error: Error, context: [String: String] = [:]) {
        #if canImport(FirebaseCrashlytics)
        let nsError = error as NSError
        var userInfo = nsError.userInfo
        for (key, value) in context {
            userInfo[key] = value
        }
        let recorded = NSError(domain: nsError.domain, code: nsError.code, userInfo: userInfo)
        Crashlytics.crashlytics().record(error: recorded)
        #endif
        #if DEBUG
        print("[Crashlytics] record: \(error.localizedDescription)")
        #endif
    }

    static func log(_ message: String) {
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().log(message)
        #endif
    }

    static func setUserID(_ id: String?) {
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().setUserID(id)
        #endif
    }
}

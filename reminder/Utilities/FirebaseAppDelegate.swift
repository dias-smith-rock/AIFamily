import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(FirebaseCore)
import FirebaseCore
#endif

/// 在 App 启动时配置 Firebase（Analytics、Crashlytics 等模块依赖此初始化）。
#if canImport(UIKit)
final class FirebaseAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Self.configureFirebaseIfNeeded()
        return true
    }

    static func configureFirebaseIfNeeded() {
        #if canImport(FirebaseCore)
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
        CrashReporting.configureAfterFirebaseStartup()
        #if DEBUG
        print("[Firebase] FirebaseApp.configure() completed")
        #endif
        #endif
    }
}
#else
enum FirebaseAppDelegate {
    static func configureFirebaseIfNeeded() {}
}
#endif

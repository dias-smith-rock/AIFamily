import Foundation

enum AppInfo {
    /// App Store Connect 中的 Apple ID（非 Bundle ID）。
    static let appStoreAppleID = "6775353963"

    /// 跳转 App Store 撰写评价页。
    static var appStoreWriteReviewURL: URL? {
        URL(string: "https://apps.apple.com/app/id\(appStoreAppleID)?action=write-review")
    }

    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var versionDisplayString: String {
        "Version \(marketingVersion) (\(buildNumber))"
    }

    static var copyrightLine: String {
        "Copyright © 2026 WeSync. All rights reserved."
    }
}

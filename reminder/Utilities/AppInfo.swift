import Foundation

enum AppInfo {
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

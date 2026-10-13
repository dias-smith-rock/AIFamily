import Foundation

#if canImport(FirebaseRemoteConfig)
import FirebaseRemoteConfig
#endif

/// 供非主线程限额判断读取。只由 `VIPFeatureRemoteConfig` 在主线程写入。
enum VIPFeatureGate {
    nonisolated(unsafe) static var isEnabled = true
}

/// Firebase Remote Config `enable_vip`。
/// true：VIP 功能显示角标，触发限额时弹出购买页。
/// false：不显示角标，功能不做 VIP 限制。
@MainActor
final class VIPFeatureRemoteConfig: ObservableObject {
    static let shared = VIPFeatureRemoteConfig()
    static let remoteKey = "enable_vip"

    @Published private(set) var enableVIP = true

    private var didStart = false
    #if canImport(FirebaseRemoteConfig)
    private var configUpdateListener: ConfigUpdateListenerRegistration?
    #endif

    private init() {}

    func start() {
        guard didStart == false else { return }
        didStart = true
        #if canImport(FirebaseRemoteConfig)
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        #if DEBUG
        settings.minimumFetchInterval = 0
        #else
        settings.minimumFetchInterval = 60 * 60
        #endif
        remoteConfig.configSettings = settings
        remoteConfig.setDefaults([Self.remoteKey: NSNumber(value: true)])
        apply(remoteConfig)

        configUpdateListener = remoteConfig.addOnConfigUpdateListener { [weak self] update, error in
            guard error == nil, let update, update.updatedKeys.contains(Self.remoteKey) else { return }
            remoteConfig.activate { _, _ in
                Task { @MainActor in
                    self?.apply(remoteConfig)
                }
            }
        }

        remoteConfig.fetchAndActivate { [weak self] _, error in
            Task { @MainActor in
                #if DEBUG
                if let error {
                    print("[RemoteConfig] enable_vip fetch failed: \(error.localizedDescription)")
                }
                #endif
                self?.apply(remoteConfig)
            }
        }
        #endif
    }

    #if canImport(FirebaseRemoteConfig)
    private func apply(_ remoteConfig: RemoteConfig) {
        let value = remoteConfig.configValue(forKey: Self.remoteKey)
        let enabled = value.boolValue
        VIPFeatureGate.isEnabled = enabled
        if enableVIP != enabled {
            enableVIP = enabled
        }
        #if DEBUG
        print("[RemoteConfig] enable_vip=\(enabled) source=\(String(describing: value.source))")
        #endif
    }
    #endif
}

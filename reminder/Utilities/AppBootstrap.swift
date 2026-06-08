import Foundation
import Combine

enum AppServiceMode: String {
    case liveSupabase
    case guestLocal
    case mockPreview
    case mockFallback
}

@MainActor
final class AppBootstrap: ObservableObject {
    private(set) var services: ReminderServiceContainer
    private(set) var viewModelFactory: ViewModelFactory
    private(set) var mode: AppServiceMode
    let featureFlags: FeatureFlags
    /// 切换 Live / Guest 服务后递增，用于重建 Tab 内 `@StateObject` ViewModel。
    @Published private(set) var sessionRevision = UUID()

    init() {
        if Self.isRunningPreview {
            mode = .mockPreview
            featureFlags = .basic
            services = .mock()
            viewModelFactory = ViewModelFactory(services: services)
            AppViewModels.configure(with: viewModelFactory)
            return
        }

        mode = .liveSupabase
        featureFlags = Self.isProMode ? .pro : .basic
        services = .live()

        viewModelFactory = ViewModelFactory(services: services)
        AppViewModels.configure(with: viewModelFactory)
    }

    func enterGuestMode() {
        let snapshot = GuestSessionStore.loadOrCreate()
        Task {
            await GuestWorkspaceStore.shared.replace(snapshot)
        }
        mode = .guestLocal
        services = .guest()
        viewModelFactory = ViewModelFactory(services: services)
        AppViewModels.configure(with: viewModelFactory)
        sessionRevision = UUID()
    }

    func enterLiveMode() {
        mode = .liveSupabase
        services = .live()
        viewModelFactory = ViewModelFactory(services: services)
        AppViewModels.configure(with: viewModelFactory)
        sessionRevision = UUID()
    }

    func exitGuestMode() {
        enterLiveMode()
    }

    private static var isRunningPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private static var isProMode: Bool {
        ProcessInfo.processInfo.environment["APP_PLAN"] == "PRO"
    }
}

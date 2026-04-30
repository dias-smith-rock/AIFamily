import Foundation
import Combine

enum AppServiceMode: String {
    case liveSupabase
    case mockPreview
    case mockFallback
}

@MainActor
final class AppBootstrap: ObservableObject {
    let services: ReminderServiceContainer
    let viewModelFactory: ViewModelFactory
    let mode: AppServiceMode
    let featureFlags: FeatureFlags

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

    private static var isRunningPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private static var isProMode: Bool {
        ProcessInfo.processInfo.environment["APP_PLAN"] == "PRO"
    }
}

import SwiftUI
import Combine

enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var settingsTitle: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色模式"
        case .dark: return "深色模式"
        }
    }

    var listValueTitle: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppSettingsManager: ObservableObject {
    static let shared = AppSettingsManager()

    static let textSizeSteps: [DynamicTypeSize] = [
        .small,
        .medium,
        .large,
        .xLarge,
        .xxLarge,
        .xxxLarge,
        .accessibility1,
        .accessibility2,
        .accessibility3
    ]

    static let defaultTextSizeIndex = 2

    @AppStorage("app_appearance")
    private var appearanceStorage = AppAppearance.system.rawValue

    @AppStorage("app_text_size_index")
    private var textSizeIndexStorage = AppSettingsManager.defaultTextSizeIndex

    var appearance: AppAppearance {
        get { AppAppearance(rawValue: appearanceStorage) ?? .system }
        set {
            objectWillChange.send()
            appearanceStorage = newValue.rawValue
        }
    }

    var textSizeIndex: Int {
        get { Self.clampTextSizeIndex(textSizeIndexStorage) }
        set {
            objectWillChange.send()
            textSizeIndexStorage = Self.clampTextSizeIndex(newValue)
        }
    }

    var colorScheme: ColorScheme? {
        appearance.colorScheme
    }

    var dynamicTypeSize: DynamicTypeSize {
        Self.textSizeSteps[textSizeIndex]
    }

    var textSizePreviewLabel: String {
        switch textSizeIndex {
        case 0: return "较小"
        case Self.textSizeSteps.count - 1: return "最大"
        default: return "标准"
        }
    }

    private init() {}

    private static func clampTextSizeIndex(_ index: Int) -> Int {
        min(max(index, 0), max(textSizeSteps.count - 1, 0))
    }
}

#if canImport(UIKit)
import UIKit

enum SystemSettingsHelper {
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
#endif

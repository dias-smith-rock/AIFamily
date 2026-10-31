import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// 日程页个人背景模式（本机偏好，不共享）。
enum ScheduleBackgroundMode: String, CaseIterable, Identifiable {
    case systemDefault = "default"
    case solidColor = "color"
    case image = "image"

    var id: String { rawValue }
}

/// 背景图片适配方式。
enum ScheduleBackgroundImageFit: String, CaseIterable, Identifiable {
    /// 等比裁切铺满（默认）。
    case fill = "fill"
    /// 等比完整显示（可能留边）。
    case fit = "fit"
    /// 拉伸铺满，可能变形。
    case stretch = "stretch"
    /// 原尺寸平铺重复。
    case tile = "tile"

    var id: String { rawValue }

    var titleKey: L10n.Entry {
        switch self {
        case .fill: L10n.Schedule.backgroundImageFitFill
        case .fit: L10n.Schedule.backgroundImageFitFit
        case .stretch: L10n.Schedule.backgroundImageFitStretch
        case .tile: L10n.Schedule.backgroundImageFitTile
        }
    }
}

/// 适合做整页背景的预设纯色（偏中性，含深/浅）。
enum ScheduleBackgroundColorPreset: String, CaseIterable, Identifiable {
    case black = "#000000"
    case charcoal = "#1C1C1E"
    case navy = "#0A1628"
    case forest = "#0F1F17"
    case plum = "#1A1024"
    case slate = "#2C2C2E"
    case mist = "#F2F2F7"
    case paper = "#FFFFFF"

    var id: String { rawValue }

    var color: Color {
        Color.taskCardCustomColor(fromHex: rawValue) ?? .black
    }
}

/// 日程背景图片本地文件读写。
enum ScheduleBackgroundStore {
    private static let directoryName = "ScheduleBackground"
    private static let fileName = "wallpaper.jpg"
    private static let maxLongEdge: CGFloat = 2048
    private static let jpegQuality: CGFloat = 0.82

    static var imageFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(directoryName, isDirectory: true)
        return dir.appendingPathComponent(fileName, isDirectory: false)
    }

    static var hasSavedImage: Bool {
        FileManager.default.fileExists(atPath: imageFileURL.path)
    }

    #if canImport(UIKit)
    static func loadUIImage() -> UIImage? {
        guard hasSavedImage else { return nil }
        return UIImage(contentsOfFile: imageFileURL.path)
    }

    @discardableResult
    static func saveImageData(_ data: Data) -> Bool {
        guard let image = UIImage(data: data) else { return false }
        return saveUIImage(image)
    }

    @discardableResult
    static func saveUIImage(_ image: UIImage) -> Bool {
        let prepared = downsampled(image)
        guard let jpeg = prepared.jpegData(compressionQuality: jpegQuality) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: imageFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try jpeg.write(to: imageFileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
    #endif

    static func clearImage() {
        let url = imageFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    #if canImport(UIKit)
    private static func downsampled(_ image: UIImage) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxLongEdge, longest > 0 else { return image }
        let scale = maxLongEdge / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
    #endif
}

/// 日程页根层 / 各模式共用的背景填充。
struct SchedulePageBackgroundFill: View {
    @EnvironmentObject private var appSettings: AppSettingsManager

    var body: some View {
        Group {
            switch appSettings.scheduleBackgroundMode {
            case .systemDefault:
                AppTheme.ColorToken.background
            case .solidColor:
                solidColor
            case .image:
                imageFill
            }
        }
        .id(appSettings.scheduleBackgroundRevision)
    }

    private var solidColor: Color {
        let hex = appSettings.scheduleBackgroundColorHex
        return Color.taskCardCustomColor(fromHex: hex) ?? AppTheme.ColorToken.background
    }

    @ViewBuilder
    private var imageFill: some View {
        #if canImport(UIKit)
        if let uiImage = ScheduleBackgroundStore.loadUIImage() {
            ZStack {
                AppTheme.ColorToken.background
                fittedBackgroundImage(uiImage)
                // 压暗蒙层，保证顶栏/周条/时间轴等浅色文字可读。
                Color.black.opacity(0.48)
            }
        } else {
            AppTheme.ColorToken.background
        }
        #else
        AppTheme.ColorToken.background
        #endif
    }

    #if canImport(UIKit)
    @ViewBuilder
    private func fittedBackgroundImage(_ uiImage: UIImage) -> some View {
        switch appSettings.scheduleBackgroundImageFit {
        case .fill:
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        case .fit:
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .stretch:
            Image(uiImage: uiImage)
                .resizable()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .tile:
            Image(uiImage: uiImage)
                .resizable(resizingMode: .tile)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    #endif
}

extension View {
    /// 日程页背景（跟随个人偏好：默认 / 纯色 / 图片）。
    func schedulePageBackground() -> some View {
        background {
            SchedulePageBackgroundFill()
                .ignoresSafeArea()
        }
    }
}

import Foundation
import Kingfisher
#if canImport(UIKit)
import UIKit
#endif

/// 任务附件图片：列表缩略图走磁盘/内存缓存 + 降采样；全屏预览再拉原图。
enum TaskAttachmentImageLoading {
    static let thumbnailLength: CGFloat = 80

    private static let thumbnailCache: ImageCache = {
        let cache = ImageCache(name: "task.attachment.thumbnails")
        cache.memoryStorage.config.totalCostLimit = 48 * 1024 * 1024
        cache.diskStorage.config.sizeLimit = 200 * 1024 * 1024
        return cache
    }()

    static var thumbnailImageCache: ImageCache { thumbnailCache }

    static var thumbnailProcessor: any ImageProcessor {
        DownsamplingImageProcessor(size: thumbnailPixelSize)
    }

    static var thumbnailOptions: KingfisherOptionsInfo {
        [
            .processor(thumbnailProcessor),
            .targetCache(thumbnailCache),
            .backgroundDecode,
            .scaleFactor(displayScale),
        ]
    }

    static func prefetchThumbnails(for attachments: [TaskAttachment]) {
        let urls = attachments.compactMap(\.displayImageURL)
        guard urls.isEmpty == false else { return }
        ImagePrefetcher(urls: urls, options: thumbnailOptions).start()
    }

    #if canImport(UIKit)
    /// 全屏 Live Text 预览用原图（优先 Kingfisher 缓存）。
    static func loadFullImage(from url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: url, options: [.backgroundDecode]) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value.image)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    #endif

    private static var thumbnailPixelSize: CGSize {
        let side = thumbnailLength * displayScale
        return CGSize(width: side, height: side)
    }

    private static var displayScale: CGFloat {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first?.screen.scale ?? 2
        #else
        2
        #endif
    }
}

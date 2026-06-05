import UIKit

enum CameraImageCompression {
    private static let maxByteCount = 400 * 1024
    private static let initialJPEGQuality: CGFloat = 0.3

    /// 将相机原图（含 HEIC）缩放并压缩为 JPEG，目标小于 400KB。
    static func compressForUpload(_ image: UIImage) -> Data? {
        var working = downscaleIfNeeded(image, maxPixel: 2048)
        if let data = jpegData(for: working, quality: initialJPEGQuality),
           data.count <= maxByteCount {
            return data
        }

        for maxPixel in [1600.0, 1280.0, 1024.0, 800.0] {
            working = downscaleIfNeeded(image, maxPixel: maxPixel)
            if let data = jpegData(for: working, quality: initialJPEGQuality),
               data.count <= maxByteCount {
                return data
            }
        }

        var quality = initialJPEGQuality
        while quality > 0.1 {
            quality -= 0.05
            if let data = jpegData(for: working, quality: quality),
               data.count <= maxByteCount {
                return data
            }
        }

        return jpegData(for: working, quality: 0.1)
    }

    private static func downscaleIfNeeded(_ image: UIImage, maxPixel: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxPixel, longest > 0 else { return image }

        let scale = maxPixel / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private static func jpegData(for image: UIImage, quality: CGFloat) -> Data? {
        image.jpegData(compressionQuality: quality)
    }
}

import UIKit

enum CameraImageCompression {
    private static let maxByteCount = 400 * 1024
    private static let initialJPEGQuality: CGFloat = 0.3
    private static let croppedMinPixel: CGFloat = 640
    private static let croppedInitialQuality: CGFloat = 0.85

    /// 裁剪图 OCR 上传：保证最短边 ≥640px，优先较高 JPEG 质量，避免小图糊化导致 OCR 空结果。
    static func compressCroppedForOCR(_ image: UIImage) -> Data? {
        var working = upscaleIfNeeded(image, minPixel: croppedMinPixel)
        working = downscaleIfNeeded(working, maxPixel: 2048)

        var quality = croppedInitialQuality
        while quality >= 0.35 {
            if let data = jpegData(for: working, quality: quality),
               data.count <= maxByteCount {
                return data
            }
            quality -= 0.1
        }

        for maxPixel in [1600.0, 1280.0, 1024.0] {
            working = downscaleIfNeeded(working, maxPixel: maxPixel)
            quality = croppedInitialQuality
            while quality >= 0.35 {
                if let data = jpegData(for: working, quality: quality),
                   data.count <= maxByteCount {
                    return data
                }
                quality -= 0.1
            }
        }

        return jpegData(for: working, quality: 0.35)
    }

    /// 将相机原图（含 HEIC）缩放并压缩为 JPEG，目标小于 400KB。
    static func compressForUpload(_ image: UIImage) -> Data? {
        compress(image, maxPixel: 2048, maxByteCount: maxByteCount, initialQuality: initialJPEGQuality)
    }

    /// Pro 上传：更高分辨率与 JPEG 质量，目标小于 2MB。
    static func compressForUploadPremium(_ image: UIImage) -> Data? {
        compress(image, maxPixel: 4096, maxByteCount: 2 * 1024 * 1024, initialQuality: 0.85)
    }

    private static func compress(
        _ image: UIImage,
        maxPixel: CGFloat,
        maxByteCount: Int,
        initialQuality: CGFloat
    ) -> Data? {
        var working = downscaleIfNeeded(image, maxPixel: maxPixel)
        if let data = jpegData(for: working, quality: initialQuality),
           data.count <= maxByteCount {
            return data
        }

        for scaledMaxPixel in [maxPixel * 0.75, maxPixel * 0.5, maxPixel * 0.35] {
            working = downscaleIfNeeded(image, maxPixel: scaledMaxPixel)
            if let data = jpegData(for: working, quality: initialQuality),
               data.count <= maxByteCount {
                return data
            }
        }

        var quality = initialQuality
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
        let pixelSize = image.pixelSize
        let longest = max(pixelSize.width, pixelSize.height)
        guard longest > maxPixel, longest > 0 else { return image }

        let scale = maxPixel / longest
        let target = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        return render(image, pixelSize: target)
    }

    private static func upscaleIfNeeded(_ image: UIImage, minPixel: CGFloat) -> UIImage {
        let pixelSize = image.pixelSize
        let shortest = min(pixelSize.width, pixelSize.height)
        guard shortest < minPixel, shortest > 0 else { return image }

        let scale = minPixel / shortest
        let target = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        return render(image, pixelSize: target)
    }

    private static func render(_ image: UIImage, pixelSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }

    private static func jpegData(for image: UIImage, quality: CGFloat) -> Data? {
        image.jpegData(compressionQuality: quality)
    }
}

private extension UIImage {
    var pixelSize: CGSize {
        if let cgImage {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

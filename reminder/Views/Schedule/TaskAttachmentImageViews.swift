import Kingfisher
import SwiftUI

/// 附件条 / 详情区使用的缩略图（缓存 + 降采样，不下载原图）。
struct TaskAttachmentThumbnailView: View {
    let url: URL
    var length: CGFloat = TaskAttachmentImageLoading.thumbnailLength

    var body: some View {
        KFImage.url(url)
            .setProcessor(TaskAttachmentImageLoading.thumbnailProcessor)
            .targetCache(TaskAttachmentImageLoading.thumbnailImageCache)
            .cacheOriginalImage(false)
            .backgroundDecode(true)
            .placeholder {
                thumbnailPlaceholder(showProgress: true)
            }
            .onFailureView {
                thumbnailPlaceholder(systemName: "photo.badge.exclamationmark", showProgress: false)
            }
            .fade(duration: 0.15)
            .resizable()
            .scaledToFill()
            .frame(width: length, height: length)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func thumbnailPlaceholder(
        systemName: String = "photo",
        showProgress: Bool
    ) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .frame(width: length, height: length)
            .overlay {
                if showProgress {
                    ProgressView()
                } else {
                    Image(systemName: systemName)
                        .foregroundStyle(.secondary)
                }
            }
    }
}

/// 全屏画廊使用的原图（点击后加载，与缩略图分缓存）。
struct TaskAttachmentFullImageView: View {
    let url: URL

    var body: some View {
        KFImage.url(url)
            .cacheOriginalImage(true)
            .backgroundDecode(true)
            .placeholder {
                ProgressView()
                    .tint(.white)
            }
            .onFailureView {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("图片加载失败")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .fade(duration: 0.2)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

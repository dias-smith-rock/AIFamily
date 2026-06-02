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

/// 全屏画廊使用的原图（点击后加载，与缩略图分缓存）；支持双指缩放、拖动与双击放大。
struct TaskAttachmentFullImageView: View {
    let url: URL
    @Binding var isZoomed: Bool

    init(url: URL, isZoomed: Binding<Bool> = .constant(false)) {
        self.url = url
        self._isZoomed = isZoomed
    }

    var body: some View {
        AttachmentImageZoomContainer(isZoomed: $isZoomed) {
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
                        Text("图片加载中")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .fade(duration: 0.2)
                .resizable()
                .scaledToFit()
        }
    }
}

/// 包裹附件原图的缩放容器：未放大时保留外层横向分页手势。
private struct AttachmentImageZoomContainer<Content: View>: View {
    @Binding var isZoomed: Bool
    @ViewBuilder let content: () -> Content

    @State private var steadyScale: CGFloat = 1
    @State private var steadyOffset: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1
    @GestureState private var dragOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 4
    private let doubleTapScale: CGFloat = 2.5

    var body: some View {
        GeometryReader { geometry in
            content()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(currentScale)
                .offset(currentOffset)
                .gesture(doubleTapGesture)
                .gesture(magnificationGesture)
                .gesture(isPanEnabled ? panGesture : nil)
                .animation(.spring(response: 0.28, dampingFraction: 0.86), value: steadyScale)
                .animation(.spring(response: 0.28, dampingFraction: 0.86), value: steadyOffset)
        }
    }

    private var isPanEnabled: Bool {
        currentScale > minScale + 0.01
    }

    private var currentScale: CGFloat {
        clampScale(steadyScale * pinchScale)
    }

    private var currentOffset: CGSize {
        CGSize(
            width: steadyOffset.width + dragOffset.width,
            height: steadyOffset.height + dragOffset.height
        )
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                applyPinchEnded(value)
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                steadyOffset = offsetAfterDrag(value.translation)
            }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                toggleDoubleTapZoom()
            }
    }

    private func applyPinchEnded(_ value: CGFloat) {
        let nextScale = clampScale(steadyScale * value)
        steadyScale = nextScale
        if nextScale <= minScale + 0.01 {
            resetZoom(animated: true)
        } else {
            steadyOffset = offsetAfterDrag(.zero, scale: nextScale)
            publishZoomState(for: nextScale)
        }
    }

    private func toggleDoubleTapZoom() {
        if steadyScale > minScale + 0.01 {
            resetZoom(animated: true)
            return
        }

        let nextScale = min(doubleTapScale, maxScale)
        steadyScale = nextScale
        steadyOffset = .zero
        publishZoomState(for: nextScale)
    }

    private func resetZoom(animated: Bool) {
        let updates = {
            steadyScale = minScale
            steadyOffset = .zero
            publishZoomState(for: minScale)
        }
        if animated {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                updates()
            }
        } else {
            updates()
        }
    }

    private func offsetAfterDrag(_ translation: CGSize, scale: CGFloat? = nil) -> CGSize {
        let activeScale = scale ?? currentScale
        let proposed = CGSize(
            width: steadyOffset.width + translation.width,
            height: steadyOffset.height + translation.height
        )
        let horizontalLimit = max((activeScale - 1) * 120, 0)
        let verticalLimit = max((activeScale - 1) * 160, 0)
        return CGSize(
            width: min(max(proposed.width, -horizontalLimit), horizontalLimit),
            height: min(max(proposed.height, -verticalLimit), verticalLimit)
        )
    }

    private func clampScale(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }

    private func publishZoomState(for scale: CGFloat) {
        isZoomed = scale > minScale + 0.01
    }
}

import Kingfisher
import SwiftUI
import VisionKit
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
/// 视图进入窗口后再安装 Live Text，避免 `makeUIView` 时 `window == nil` 导致交互未挂上。
private final class LiveTextImageScrollView: UIScrollView {
    var onDidEnterWindow: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        onDidEnterWindow?()
    }
}

/// 支持双指缩放与 Live Text 选字复制的全屏图片查看（`ImageAnalysisInteraction`）。
struct LiveTextZoomableImageView: UIViewRepresentable {
    let image: UIImage
    @Binding var isZoomed: Bool

    init(image: UIImage, isZoomed: Binding<Bool> = .constant(false)) {
        self.image = image
        self._isZoomed = isZoomed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isZoomed: $isZoomed)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = LiveTextImageScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView
        context.coordinator.currentImage = image

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        scrollView.onDidEnterWindow = { [weak coordinator = context.coordinator] in
            coordinator?.installLiveTextIfNeeded()
        }
        if scrollView.window != nil {
            context.coordinator.installLiveTextIfNeeded()
        }

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.scrollView = scrollView
        guard context.coordinator.isTearingDown == false else { return }

        let imageChanged = context.coordinator.currentImage !== image
        context.coordinator.currentImage = image
        context.coordinator.imageView?.image = image

        if imageChanged {
            scrollView.zoomScale = 1
            scrollView.contentOffset = .zero
            context.coordinator.installLiveTextIfNeeded(force: true)
        }
    }

    static func dismantleUIView(_ scrollView: UIScrollView, coordinator: Coordinator) {
        coordinator.teardown(scrollView: scrollView)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        @Binding var isZoomed: Bool
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        fileprivate var currentImage: UIImage?
        fileprivate var isTearingDown = false
        private var analysisTask: Task<Void, Never>?
        private var liveTextInteraction: ImageAnalysisInteraction?

        init(isZoomed: Binding<Bool>) {
            _isZoomed = isZoomed
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard isTearingDown == false, scrollView.window != nil else { return }
            let scale = scrollView.zoomScale
            guard scale.isFinite, scale > 0 else { return }
            isZoomed = scale > 1.01
        }

        func installLiveTextIfNeeded(force: Bool = false) {
            guard isTearingDown == false else { return }
            guard let imageView, let image = currentImage else { return }
            if force == false, liveTextInteraction != nil, imageView.interactions.contains(where: { $0 === liveTextInteraction }) {
                return
            }
            attachLiveText(to: imageView, image: image)
        }

        private func attachLiveText(to imageView: UIImageView, image: UIImage) {
            removeLiveTextInteraction(from: imageView)
            analysisTask?.cancel()

            let interaction = ImageAnalysisInteraction()
            interaction.preferredInteractionTypes = [.textSelection]
            imageView.addInteraction(interaction)
            liveTextInteraction = interaction

            analysisTask = Task { @MainActor in
                let analyzer = ImageAnalyzer()
                let configuration = ImageAnalyzer.Configuration([.text])
                guard Task.isCancelled == false, isTearingDown == false else { return }
                guard let analysis = try? await analyzer.analyze(
                    image,
                    orientation: image.imageOrientation,
                    configuration: configuration
                ) else {
                    return
                }
                guard Task.isCancelled == false, isTearingDown == false else { return }
                guard imageView.window != nil, liveTextInteraction === interaction else { return }
                interaction.analysis = analysis
            }
        }

        func teardown(scrollView: UIScrollView) {
            isTearingDown = true
            analysisTask?.cancel()
            analysisTask = nil
            scrollView.delegate = nil
            (scrollView as? LiveTextImageScrollView)?.onDidEnterWindow = nil

            if scrollView.zoomScale.isFinite, scrollView.zoomScale > 0 {
                scrollView.setZoomScale(1, animated: false)
            }
            scrollView.contentOffset = .zero

            if let imageView {
                removeLiveTextInteraction(from: imageView)
            }
            liveTextInteraction = nil
            imageView = nil
            self.scrollView = nil
            currentImage = nil
            isZoomed = false
        }

        private func removeLiveTextInteraction(from imageView: UIImageView) {
            if let liveTextInteraction {
                liveTextInteraction.analysis = nil
                imageView.removeInteraction(liveTextInteraction)
                self.liveTextInteraction = nil
            }
            imageView.interactions
                .filter { $0 is ImageAnalysisInteraction }
                .forEach { interaction in
                    if let textInteraction = interaction as? ImageAnalysisInteraction {
                        textInteraction.analysis = nil
                    }
                    imageView.removeInteraction(interaction)
                }
        }
    }
}

enum TaskAttachmentGalleryDismissal {
    /// 关闭前结束 Live Text 选区与键盘，避免 `ImageAnalysisInteraction` 在 dismantle 时写出 NaN frame。
    @MainActor
    static func prepareForDismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

/// 远程附件原图：加载完成后启用 Live Text 预览。
struct LiveTextZoomableRemoteImageView: View {
    let url: URL
    @Binding var isZoomed: Bool
    @State private var image: UIImage?
    @State private var loadFailed = false

    init(url: URL, isZoomed: Binding<Bool> = .constant(false)) {
        self.url = url
        self._isZoomed = isZoomed
    }

    var body: some View {
        Group {
            if let image {
                LiveTextZoomableImageView(image: image, isZoomed: $isZoomed)
            } else if loadFailed {
                galleryFailurePlaceholder
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private var galleryFailurePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.6))
            Text("图片加载失败")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func loadImage() async {
        image = nil
        loadFailed = false
        image = await TaskAttachmentImageLoading.loadFullImage(from: url)
        loadFailed = image == nil
    }
}
#endif

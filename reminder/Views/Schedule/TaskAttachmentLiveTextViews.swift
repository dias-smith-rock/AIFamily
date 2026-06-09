import Kingfisher
import SwiftUI
import VisionKit
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
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
        let scrollView = UIScrollView()
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

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        context.coordinator.attachLiveText(to: imageView, image: image)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard context.coordinator.imageView?.image !== image else { return }
        context.coordinator.imageView?.image = image
        scrollView.zoomScale = 1
        scrollView.contentOffset = .zero
        context.coordinator.attachLiveText(to: context.coordinator.imageView, image: image)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        @Binding var isZoomed: Bool
        weak var imageView: UIImageView?
        private var analysisTask: Task<Void, Never>?

        init(isZoomed: Binding<Bool>) {
            _isZoomed = isZoomed
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            isZoomed = scrollView.zoomScale > 1.01
        }

        func attachLiveText(to imageView: UIImageView?, image: UIImage) {
            guard let imageView else { return }
            analysisTask?.cancel()
            imageView.interactions
                .filter { $0 is ImageAnalysisInteraction }
                .forEach { imageView.removeInteraction($0) }

            analysisTask = Task { @MainActor in
                let interaction = ImageAnalysisInteraction()
                interaction.preferredInteractionTypes = [.textSelection]
                imageView.addInteraction(interaction)

                let analyzer = ImageAnalyzer()
                let configuration = ImageAnalyzer.Configuration([.text])
                guard Task.isCancelled == false else { return }
                if let analysis = try? await analyzer.analyze(
                    image,
                    orientation: image.imageOrientation,
                    configuration: configuration
                ) {
                    guard Task.isCancelled == false else { return }
                    interaction.analysis = analysis
                }
            }
        }
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

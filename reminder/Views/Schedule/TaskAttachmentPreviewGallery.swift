import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct TaskAttachmentPreviewItem: Identifiable {
    enum Source {
        case local(UIImage)
        case remote(URL)
    }

    let id: UUID
    let source: Source
}

/// 创建/编辑任务时的附件全屏预览：分页滑动 + Live Text 选字复制。
struct TaskAttachmentPreviewGallery: View {
    let items: [TaskAttachmentPreviewItem]
    @State private var currentIndex: Int
    @State private var isCurrentImageZoomed = false
    @State private var isClosing = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    init(items: [TaskAttachmentPreviewItem], startIndex: Int) {
        self.items = items
        let lastIndex = max(items.count - 1, 0)
        let clamped = min(max(startIndex, 0), lastIndex)
        _currentIndex = State(initialValue: clamped)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isClosing == false {
                if items.isEmpty {
                    emptyPlaceholder
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            galleryPage(item, isActive: index == currentIndex)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(
                        .page(indexDisplayMode: items.count > 1 ? .automatic : .never)
                    )
                    .scrollDisabled(isCurrentImageZoomed)
                    .onChange(of: currentIndex) { _, _ in
                        isCurrentImageZoomed = false
                    }
                }

                overlayChrome
            }
        }
        .interactiveDismissDisabled(true)
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.6))
            Text(L10n.Common.noAttachmentsAvailableForPreview.localized)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var overlayChrome: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    closeGallery()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white.opacity(0.95), .white.opacity(0.25))
                }
                .accessibilityLabel(L10n.Common.close)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            bottomBar
        }
    }

    private var bottomBar: some View {
        ZStack {
            HStack {
                Text(L10n.Common.dragAndSelectTextToCopy.localized)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
            }

            if items.count > 1 {
                Text("\(currentIndex + 1) / \(items.count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.12), in: Capsule())
                    .accessibilityLabel(L10n.Common.n1Lld2Lld.formatted(locale: locale, currentIndex + 1, items.count))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }

    private func closeGallery() {
        guard isClosing == false else { return }
        #if canImport(UIKit)
        TaskAttachmentGalleryDismissal.beginClose(
            isClosing: { isClosing = $0 },
            isZoomed: { isCurrentImageZoomed = $0 },
            dismiss: { dismiss() }
        )
        #else
        dismiss()
        #endif
    }

    @ViewBuilder
    private func galleryPage(_ item: TaskAttachmentPreviewItem, isActive: Bool) -> some View {
        #if canImport(UIKit)
        switch item.source {
        case .local(let image):
            LiveTextZoomableImageView(
                image: image,
                isZoomed: isActive ? $isCurrentImageZoomed : .constant(false)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 48)
        case .remote(let url):
            LiveTextZoomableRemoteImageView(
                url: url,
                isZoomed: isActive ? $isCurrentImageZoomed : .constant(false)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 48)
        }
        #else
        Text(L10n.Common.imagePreviewUnavailable.localized)
            .foregroundStyle(.white.opacity(0.7))
        #endif
    }
}

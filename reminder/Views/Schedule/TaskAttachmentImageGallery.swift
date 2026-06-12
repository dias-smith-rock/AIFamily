import SwiftUI

/// 任务附件全屏预览：横向分页滑动切换。
struct TaskAttachmentImageGallery: View {
    let attachments: [TaskAttachment]
    @State private var currentIndex: Int
    @State private var isCurrentImageZoomed = false
    @State private var isSavingToAlbum = false
    @State private var isShowingSaveSuccessAlert = false
    @State private var isShowingSaveErrorAlert = false
    @State private var saveErrorMessage = ""
    @State private var isClosing = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    init(attachments: [TaskAttachment], startIndex: Int) {
        self.attachments = attachments
        let lastIndex = max(attachments.count - 1, 0)
        let clamped = min(max(startIndex, 0), lastIndex)
        _currentIndex = State(initialValue: clamped)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isClosing == false {
                TabView(selection: $currentIndex) {
                    ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                        galleryPage(attachment, isActive: index == currentIndex)
                            .tag(index)
                    }
                }
                .tabViewStyle(
                    .page(indexDisplayMode: attachments.count > 1 ? .automatic : .never)
                )
                .scrollDisabled(isCurrentImageZoomed)
                .onChange(of: currentIndex) { _, _ in
                    isCurrentImageZoomed = false
                }
            }

            if isClosing == false {
                overlayChrome
            }
        }
        .interactiveDismissDisabled(true)
        .alert(L10n.Common.savedToPhotos, isPresented: $isShowingSaveSuccessAlert) {
            Button(L10n.Common.ok, role: .cancel) {}
        }
        .alert(L10n.Common.couldnTSave, isPresented: $isShowingSaveErrorAlert) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    private var currentImageURL: URL? {
        guard attachments.indices.contains(currentIndex) else { return nil }
        return attachments[currentIndex].displayImageURL
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
                if currentImageURL != nil {
                    saveToAlbumButton
                }
                Text(L10n.Common.dragAndSelectTextToCopy.localized)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
            }

            if attachments.count > 1 {
                Text("\(currentIndex + 1) / \(attachments.count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.12), in: Capsule())
                    .accessibilityLabel(
                        L10n.Schedule.attachmentPageIndicator.formatted(locale: locale, currentIndex + 1, attachments.count)
                    )
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

    private var saveToAlbumButton: some View {
        Button {
            saveCurrentImageToAlbum()
        } label: {
            Group {
                if isSavingToAlbum {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 22, weight: .semibold))
                }
            }
            .frame(width: 44, height: 44)
            .background(.white.opacity(0.12), in: Circle())
            .foregroundStyle(.white)
        }
        .disabled(isSavingToAlbum)
        .accessibilityLabel(L10n.Common.saveToPhotos)
    }

    private func saveCurrentImageToAlbum() {
        guard let url = currentImageURL else { return }
        guard isSavingToAlbum == false else { return }

        isSavingToAlbum = true
        Task {
            defer { isSavingToAlbum = false }
            do {
                try await PhotoLibrarySaving.saveImage(from: url)
                isShowingSaveSuccessAlert = true
            } catch {
                saveErrorMessage = error.localizedDescription
                isShowingSaveErrorAlert = true
            }
        }
    }

    @ViewBuilder
    private func galleryPage(_ attachment: TaskAttachment, isActive: Bool) -> some View {
        if let url = attachment.displayImageURL {
            TaskAttachmentFullImageView(
                url: url,
                isZoomed: isActive ? $isCurrentImageZoomed : .constant(false)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 48)
        } else {
            galleryFailurePlaceholder
        }
    }

    private var galleryFailurePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.6))
            Text(L10n.Common.loadingImage.localized)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview {
    TaskAttachmentImageGallery(
        attachments: [
            TaskAttachment(
                taskId: UUID(),
                fileUrl: "https://picsum.photos/800/600",
                fileType: "image/jpeg"
            ),
            TaskAttachment(
                taskId: UUID(),
                fileUrl: "https://picsum.photos/801/601",
                fileType: "image/jpeg"
            ),
        ],
        startIndex: 0
    )
}
#endif

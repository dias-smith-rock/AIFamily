import SwiftUI

/// 任务附件全屏预览：横向分页滑动切换。
struct TaskAttachmentImageGallery: View {
    let attachments: [TaskAttachment]
    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(attachments: [TaskAttachment], startIndex: Int) {
        self.attachments = attachments
        let lastIndex = max(attachments.count - 1, 0)
        let clamped = min(max(startIndex, 0), lastIndex)
        _currentIndex = State(initialValue: clamped)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    galleryPage(attachment)
                        .tag(index)
                }
            }
            .tabViewStyle(
                .page(indexDisplayMode: attachments.count > 1 ? .automatic : .never)
            )

            overlayChrome
        }
    }

    private var overlayChrome: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white.opacity(0.95), .white.opacity(0.25))
                }
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            if attachments.count > 1 {
                Text("\(currentIndex + 1) / \(attachments.count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.12), in: Capsule())
                    .padding(.bottom, 28)
                    .accessibilityLabel(
                        "第 \(currentIndex + 1) 张，共 \(attachments.count) 张"
                    )
            }
        }
    }

    @ViewBuilder
    private func galleryPage(_ attachment: TaskAttachment) -> some View {
        if let url = attachment.displayImageURL {
            TaskAttachmentFullImageView(url: url)
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
            Text("图片加载失败")
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

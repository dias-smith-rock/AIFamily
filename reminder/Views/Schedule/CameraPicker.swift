import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 相机拍照 + 相册选图；完成后返回原图与压缩 JPEG（<400KB，用于 AI 上传）。
struct CameraPicker: View {
    let onImageCaptured: (_ source: AIPhotoTaskCreationLogger.CaptureSource, _ originalImage: UIImage, _ compressedJPEG: Data) -> Void
    let onCancel: () -> Void

    @State private var selectedPhotoItem: PhotosPickerItem?

    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if Self.isCameraAvailable {
                    SystemCameraPicker(
                        onImageCaptured: onImageCaptured,
                        onCancel: onCancel
                    )
                } else {
                    cameraUnavailablePlaceholder
                }
            }
            .ignoresSafeArea()

            albumImportBar
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                await importPhotoFromLibrary(item)
            }
        }
    }

    private var cameraUnavailablePlaceholder: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("此设备无法使用相机")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("请从下方相册选择图片")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var albumImportBar: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            HStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle")
                    .font(.body.weight(.semibold))
                Text("相册")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
            }
        }
        .accessibilityLabel("相册")
    }

    @MainActor
    private func importPhotoFromLibrary(_ item: PhotosPickerItem) async {
        defer { selectedPhotoItem = nil }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }

        CameraPickerImageProcessing.deliver(
            image,
            source: .photoLibrary,
            onImageCaptured: onImageCaptured,
            onCancel: onCancel
        )
    }
}

// MARK: - System camera

private struct SystemCameraPicker: UIViewControllerRepresentable {
    let onImageCaptured: (_ source: AIPhotoTaskCreationLogger.CaptureSource, _ originalImage: UIImage, _ compressedJPEG: Data) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImageCaptured: (_ source: AIPhotoTaskCreationLogger.CaptureSource, _ originalImage: UIImage, _ compressedJPEG: Data) -> Void
        let onCancel: () -> Void

        init(
            onImageCaptured: @escaping (_ source: AIPhotoTaskCreationLogger.CaptureSource, _ originalImage: UIImage, _ compressedJPEG: Data) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onImageCaptured = onImageCaptured
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                onCancel()
                return
            }

            CameraPickerImageProcessing.deliver(
                image,
                source: .camera,
                onImageCaptured: onImageCaptured,
                onCancel: onCancel
            )
        }
    }
}

// MARK: - Image processing

private enum CameraPickerImageProcessing {
    static func deliver(
        _ image: UIImage,
        source: AIPhotoTaskCreationLogger.CaptureSource,
        onImageCaptured: @escaping (_ source: AIPhotoTaskCreationLogger.CaptureSource, _ originalImage: UIImage, _ compressedJPEG: Data) -> Void,
        onCancel: @escaping () -> Void
    ) {
        AIPhotoTaskCreationLogger.step(.imageCaptured, source: source)

        Task.detached(priority: .userInitiated) {
            guard let data = CameraImageCompression.compressForUpload(image) else {
                AIPhotoTaskCreationLogger.failure(
                    step: .compressionFailed,
                    error: AITaskParserError.invalidResponse,
                    source: source
                )
                await MainActor.run { onCancel() }
                return
            }
            await MainActor.run {
                AIPhotoTaskCreationLogger.step(.compressionDone, source: source, byteCount: data.count)
                onImageCaptured(source, image, data)
            }
        }
    }
}

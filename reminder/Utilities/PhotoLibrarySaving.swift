import Foundation
import Kingfisher
import Photos
#if canImport(UIKit)
import UIKit
#endif

enum PhotoLibrarySaving {
    enum SaveError: LocalizedError {
        case accessDenied
        case imageUnavailable
        case system(Error)

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                AppLocalized.localizedSync("无法访问相册，请在系统设置中允许保存照片。")
            case .imageUnavailable:
                AppLocalized.localizedSync("图片尚未加载完成，请稍后再试。")
            case .system(let error):
                error.localizedDescription
            }
        }
    }

    static func saveImage(from url: URL) async throws {
        #if canImport(UIKit)
        let image = try await loadUIImage(from: url)
        try await authorizeAddOnlyAccess()
        try await writeToPhotoLibrary(image)
        #else
        throw SaveError.imageUnavailable
        #endif
    }

    #if canImport(UIKit)
    private static func loadUIImage(from url: URL) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: url) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value.image)
                case .failure(let error):
                    continuation.resume(throwing: SaveError.system(error))
                }
            }
        }
    }

    private static func authorizeAddOnlyAccess() async throws {
        let status = await requestAddOnlyAuthorization()
        switch status {
        case .authorized, .limited:
            return
        case .denied, .restricted, .notDetermined:
            throw SaveError.accessDenied
        @unknown default:
            throw SaveError.accessDenied
        }
    }

    private static func requestAddOnlyAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func writeToPhotoLibrary(_ image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: SaveError.system(error))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SaveError.imageUnavailable)
                }
            }
        }
    }
    #endif
}

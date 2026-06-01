#if canImport(AuthenticationServices) && canImport(UIKit)
import AuthenticationServices
import UIKit

/// 使用 `ASAuthorizationController` 拉起 Sign in with Apple，便于 UI 使用自定义 SwiftUI 按钮。
@MainActor
final class AppleSignInPresenter: NSObject {
    private(set) var currentRawNonce: String?
    var onComplete: ((Result<ASAuthorization, Error>) -> Void)?

    func performRequests() {
        let raw = AppleSignInHelper.generateRawNonce()
        currentRawNonce = raw

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleSignInHelper.sha256Hex(of: raw)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
}

extension AppleSignInPresenter: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        onComplete?(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onComplete?(.failure(error))
    }
}

extension AppleSignInPresenter: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }
        if let firstWindow = scenes.first?.windows.first {
            return firstWindow
        }
        if let firstScene = scenes.first {
            return ASPresentationAnchor(windowScene: firstScene)
        }
        if
            let anyScene = UIApplication.shared.connectedScenes.first,
            let windowScene = anyScene as? UIWindowScene
        {
            return ASPresentationAnchor(windowScene: windowScene)
        }
        fatalError("Unable to resolve presentation anchor for Apple Sign-In.")
    }
}
#endif

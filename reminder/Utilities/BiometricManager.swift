import SwiftUI
import Combine
import LocalAuthentication

@MainActor
final class BiometricManager: ObservableObject {
    @AppStorage("requireFaceID") var requireFaceID: Bool = false
    @Published var isUnlocked: Bool = false
    @Published private(set) var isAuthenticating = false

    func authenticate() {
        guard isAuthenticating == false else { return }
        guard requireFaceID else {
            withAnimation(.easeInOut) {
                isUnlocked = true
            }
            return
        }

        isAuthenticating = true
        Task {
            defer { isAuthenticating = false }
            let context = LAContext()
            context.localizedCancelTitle = String(localized: "稍后")
            let reason = String(localized: "请验证身份以访问同圈中的群组日程与任务。")
            let policy: LAPolicy = .deviceOwnerAuthentication

            var authError: NSError?
            guard context.canEvaluatePolicy(policy, error: &authError) else {
                isUnlocked = false
                return
            }

            let success = await withCheckedContinuation { continuation in
                context.evaluatePolicy(policy, localizedReason: reason) { ok, _ in
                    continuation.resume(returning: ok)
                }
            }

            withAnimation(.easeInOut) {
                isUnlocked = success
            }
        }
    }

    func lockIfNeeded() {
        guard requireFaceID else { return }
        isUnlocked = false
    }
}

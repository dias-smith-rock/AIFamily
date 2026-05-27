import Foundation
import Combine

/// 登出过程中的全局「消音」标志，避免子 ViewModel 在 Session 清空时误弹登录 Sheet。
@MainActor
final class AuthSessionGuard: ObservableObject {
    static let shared = AuthSessionGuard()

    @Published private(set) var isLoggingOut = false

    private init() {}

    func beginLoggingOut() {
        isLoggingOut = true
    }

    func endLoggingOut(after delaySeconds: Double = 1.0) async {
        if delaySeconds > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        }
        isLoggingOut = false
    }
}

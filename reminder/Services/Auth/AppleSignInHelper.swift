import CryptoKit
import Foundation
import Security

/// Sign in with Apple：生成 **raw nonce** 及其 **SHA256（十六进制小写）**，供 `ASAuthorizationAppleIDRequest` 与 Supabase `signInWithIdToken` 校验。
enum AppleSignInHelper {

    /// 生成 URL-safe 随机字符串作为 raw nonce（防重放）。
    static func generateRawNonce(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            return UUID().uuidString + UUID().uuidString
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// 对 raw nonce 做 SHA256，输出 **64 位十六进制小写字符串**（写入 `request.nonce`）。
    static func sha256Hex(of rawNonce: String) -> String {
        let data = Data(rawNonce.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

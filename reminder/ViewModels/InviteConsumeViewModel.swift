import Foundation
import Combine

@MainActor
final class InviteConsumeViewModel: ObservableObject {
    @Published var sigInput = ""
    @Published private(set) var isSubmitting = false
    @Published private(set) var statusMessage = AppLocalized.localized("请输入分享链接中的 sig 参数")
    @Published private(set) var consumeResult: ConsumeInviteResult?

    private let client: InviteLinkConsumeClient

    init(client: InviteLinkConsumeClient = InviteLinkConsumeClient()) {
        self.client = client
    }

    func consume() async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let result = try await client.consume(sig: sigInput)
            consumeResult = result
            statusMessage = AppLocalized.localized("消费成功：链接有效且已标记一次性使用")
        } catch {
            consumeResult = nil
            statusMessage = error.localizedDescription
        }
    }

    func reset() {
        sigInput = ""
        consumeResult = nil
        statusMessage = AppLocalized.localized("请输入分享链接中的 sig 参数")
    }
}

import Foundation
import Combine

@MainActor
final class InviteConsumeViewModel: ObservableObject {
    @Published var sigInput = ""
    @Published private(set) var isSubmitting = false
    @Published private(set) var statusMessage = AppLocalized.localized(L10n.Common.enterTheSigParameterFromTheShareLink)
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
            statusMessage = AppLocalized.localized(L10n.Common.successLinkIsValidAndMarkedAsOneTimeUse)
        } catch {
            consumeResult = nil
            statusMessage = error.localizedDescription
        }
    }

    func reset() {
        sigInput = ""
        consumeResult = nil
        statusMessage = AppLocalized.localized(L10n.Common.enterTheSigParameterFromTheShareLink)
    }
}

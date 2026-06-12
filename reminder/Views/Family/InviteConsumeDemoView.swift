import SwiftUI

struct InviteConsumeDemoView: View {
    @Environment(\.locale) private var locale
    @StateObject private var viewModel = InviteConsumeViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                sigInputField
                actionButtons
                statusCard

                if let result = viewModel.consumeResult {
                    resultCard(result)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(AppLocalized.string(L10n.Family.consumptionInvitationLink, locale: locale))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppLocalized.string(L10n.Common.executionSideDebuggingEntrance, locale: locale))
                .font(.system(size: 22, weight: .bold))
            Text(AppLocalized.string(L10n.Common.afterPastingSigCallConsumeInviteLinkToQu, locale: locale))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var sigInputField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SIG")
                .font(.system(size: 14, weight: .semibold))
            TextEditor(text: $viewModel.sigInput)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(minHeight: 120)
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await viewModel.consume()
                }
            } label: {
                if viewModel.isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                } else {
                    Text(AppLocalized.string(L10n.Common.startConsuming, locale: locale))
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isSubmitting)

            Button(AppLocalized.string(L10n.Common.reset, locale: locale)) {
                viewModel.reset()
            }
            .buttonStyle(.bordered)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalized.string(L10n.Common.callStatus, locale: locale))
                .font(.system(size: 14, weight: .semibold))
            Text(viewModel.statusMessage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func resultCard(_ result: ConsumeInviteResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalized.string(L10n.Common.returnResults, locale: locale))
                .font(.system(size: 14, weight: .semibold))
            Label("valid: \(result.valid ? "true" : "false")", systemImage: "checkmark.shield")
            Label("channel: \(result.channel)", systemImage: "dot.radiowaves.left.and.right")
            Label("nonce: \(result.nonce)", systemImage: "number")
            Label("token: \(result.inviteToken)", systemImage: "key")
        }
        .font(.system(size: 13, weight: .medium))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        InviteConsumeDemoView()
    }
}

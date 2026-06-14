import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let primaryActionTitle: LocalizedStringResource
    let primaryAction: () -> Void
    let secondaryActionTitle: LocalizedStringResource?
    let secondaryAction: (() -> Void)?

    init(
        systemImage: String,
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        primaryActionTitle: LocalizedStringResource,
        primaryAction: @escaping () -> Void,
        secondaryActionTitle: LocalizedStringResource? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.primaryActionTitle = primaryActionTitle
        self.primaryAction = primaryAction
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 20, weight: .bold))

            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                Button(action: primaryAction) {
                    Text(primaryActionTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)

                if let secondaryActionTitle, let secondaryAction {
                    Button(action: secondaryAction) {
                        Text(secondaryActionTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    EmptyStateView(
        systemImage: "calendar.badge.exclamationmark",
        title: L10n.Schedule.noTasksYet.localized,
        message: L10n.Schedule.aiCreateTaskHint.localized,
        primaryActionTitle: L10n.Schedule.letAiCreateForMe.localized,
        primaryAction: {},
        secondaryActionTitle: L10n.Schedule.createManually.localized,
        secondaryAction: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

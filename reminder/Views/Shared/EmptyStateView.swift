import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let primaryActionTitle: LocalizedStringKey
    let primaryAction: () -> Void
    let secondaryActionTitle: LocalizedStringKey?
    let secondaryAction: (() -> Void)?

    init(
        systemImage: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        primaryActionTitle: LocalizedStringKey,
        primaryAction: @escaping () -> Void,
        secondaryActionTitle: LocalizedStringKey? = nil,
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
        title: L10n.Common.noTasksYet,
        message: L10n.Schedule.aiCreateTaskHint,
        primaryActionTitle: L10n.Schedule.letAiCreateForMe,
        primaryAction: {},
        secondaryActionTitle: L10n.Schedule.createManually,
        secondaryAction: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}

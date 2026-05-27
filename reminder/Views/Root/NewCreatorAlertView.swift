import SwiftUI

struct NewCreatorAlertView: View {
    @Environment(\.locale) private var locale
    let householdName: String
    let onViewTapped: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text(AppLocalized.string("权限变更通知", locale: locale))
                    .font(.headline)

                Text(
                    String(
                        format: AppLocalized.string("您已成为「%@」的创建者，拥有该群组的最高管理权限。", locale: locale),
                        householdName
                    )
                )
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Button(action: onViewTapped) {
                    Text(AppLocalized.string("立即查看", locale: locale))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(radius: 20)
            .padding(.horizontal, 40)
        }
    }
}

#Preview {
    NewCreatorAlertView(
        householdName: "王家小院",
        onViewTapped: {},
        onClose: {}
    )
}

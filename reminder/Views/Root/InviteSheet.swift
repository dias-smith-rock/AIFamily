import SwiftUI

struct InviteSheet: View {
    private let inviteCode = "8X9A2M"

    var body: some View {
        VStack(spacing: 16) {
            Text("邀请家人加入")
                .font(.system(size: 24, weight: .bold))

            Image(systemName: "qrcode")
                .font(.system(size: 140, weight: .regular))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)

            Text(inviteCode)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .textSelection(.enabled)

            Button {
            } label: {
                Text("分享给微信家人")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    InviteSheet()
}

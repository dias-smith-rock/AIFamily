import SwiftUI

struct AssistantSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        aiHintCard
                        Spacer(minLength: 360)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                composer
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI助理")
                        .font(.title2.weight(.bold))
                    Text("智能解析任务")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    private var aiHintCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 8) {
                Text("你好!我可以帮你快速创建任务。你可以：")
                Text("• 粘贴微信通知文字")
                Text("• 上传学校通知截图")
                Text("• 直接语音说出需求")
            }
            .font(.headline)
            .foregroundStyle(.primary)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.14), lineWidth: 1)
        )
    }

    private var composer: some View {
        HStack(spacing: 8) {
            iconButton("photo.badge.plus")
            iconButton("mic")

            TextField("粘贴通知或说出需求", text: $inputText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
            } label: {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .background(Color(.systemBackground))
    }

    private func iconButton(_ systemName: String) -> some View {
        Button {
        } label: {
            Image(systemName: systemName)
                .foregroundStyle(.secondary)
                .frame(width: 42, height: 42)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AssistantSheetView()
}

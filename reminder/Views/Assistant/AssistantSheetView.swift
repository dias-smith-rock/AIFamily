import SwiftUI

struct AssistantSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appRouter: AppRouter
    @StateObject private var viewModel = AppViewModels.makeAssistantViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        aiHintCard
                        stateContent
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

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
        case .parsing:
            ProgressView("正在解析任务...")
                .padding(12)
        case let .preview(draft):
            TaskPreviewCard(
                draft: draft,
                onConfirm: {
                    guard
                        let householdId = appRouter.selectedHouseholdId,
                        let creatorMembershipId = appRouter.selectedMembershipId
                    else {
                        return
                    }
                    let assignee = HouseholdMembership.mockMembers.first(where: { $0.householdId == householdId && $0.id != creatorMembershipId })
                    await viewModel.confirmSend(
                        householdId: householdId,
                        creatorMembershipId: creatorMembershipId,
                        involvedMemberIds: assignee.map { [$0.id] } ?? []
                    )
                },
                onCorrection: { correction in
                    await viewModel.applyNaturalLanguageCorrection(correction)
                }
            )
        case .sending:
            ProgressView("正在写入任务...")
                .padding(12)
        case let .sent(task):
            ContentUnavailableView(
                "已发送：\(task.title)",
                systemImage: "checkmark.circle.fill",
                description: Text("任务已写入日程，可返回查看。")
            )
        case let .failed(message):
            ContentUnavailableView(
                "解析失败",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            iconButton("photo.badge.plus")
            iconButton("mic")

            TextField("粘贴通知或说出需求", text: $viewModel.inputText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                Task {
                    await viewModel.parseInput()
                }
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

private struct TaskPreviewCard: View {
    let draft: TaskDraft
    let onConfirm: () async -> Void
    let onCorrection: (String) async -> Void
    @State private var correction = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("任务确认预检卡片")
                .font(.system(size: 16, weight: .bold))
            Label(draft.title, systemImage: "checklist")
            Label(draft.dueDate.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
            if let location = draft.locationName {
                Label(location, systemImage: "location")
            }
            if let subject = draft.targetSubject {
                Label(subject, systemImage: "person")
            }
            TextField("自然语言修正：例如“时间改成明天下午”", text: $correction)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("应用修正") {
                    Task {
                        await onCorrection(correction)
                    }
                }
                .buttonStyle(.bordered)

                Button("确认发送") {
                    Task {
                        await onConfirm()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    AssistantSheetView()
        .environmentObject(AppRouter())
}

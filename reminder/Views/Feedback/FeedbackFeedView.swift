import SwiftUI

struct FeedbackFeedView: View {
    @EnvironmentObject private var appBootstrap: AppBootstrap
    @EnvironmentObject private var appRouter: AppRouter
    @StateObject private var viewModel = AppViewModels.makeFeedbackFeedViewModel()
    @State private var filter: FeedbackFilter = .all

    private enum FeedbackFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case unread = "未读"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GlobalHeaderView {
                    Text("消息")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                } trailing: {
                    Button {
                        // 预留：全部已读
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.ColorToken.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("全部已读")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        filterBar
                        simulateVoiceButton
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 96)
                }
                .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
        }
        .task {
            viewModel.setHouseholdContext(appRouter.selectedHouseholdId)
            await viewModel.loadFeedbacks()
            await viewModel.startRealtime()
        }
        .onChange(of: appRouter.selectedHouseholdId) { _, newValue in
            viewModel.setHouseholdContext(newValue)
            Task {
                await viewModel.loadFeedbacks()
            }
        }
        .onDisappear {
            Task {
                await viewModel.stopRealtime()
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(FeedbackFilter.allCases) { option in
                Button {
                    filter = option
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(filter == option ? .blue : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(filter == option ? Color(.systemBackground) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(AppTheme.ColorToken.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var simulateVoiceButton: some View {
        Button {
            Task {
                guard
                    let householdId = appRouter.selectedHouseholdId,
                    let task = FamilyTask.mockTasks.first(where: { $0.householdId == householdId }) ?? FamilyTask.mockTasks.first,
                    let sender = HouseholdMembership.mockMembers.first
                else {
                    return
                }
                let audioData = Data(repeating: 0x10, count: 2048)
                await viewModel.uploadVoiceFeedback(
                    taskId: task.id,
                    senderId: sender.id,
                    audioData: audioData
                )
            }
        } label: {
            Label("模拟执行端语音回传", systemImage: "waveform.badge.mic")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.hasLoadedOnce == false {
            ProgressView("正在加载反馈...")
                .frame(maxWidth: .infinity, minHeight: 220)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView {
                Label("加载失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("重新加载") {
                    Task {
                        await viewModel.loadFeedbacks()
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else if filteredFeedbacks.isEmpty {
            feedbackEmptyState
        } else {
            ForEach(filteredFeedbacks) { feedback in
                FeedbackCardView(
                    feedback: feedback,
                    task: FamilyTask.mockTasks.first(where: { $0.id == feedback.taskId }),
                    showTranscription: appBootstrap.featureFlags.enableAITranscription,
                    onMarkRead: {
                        guard let firstMember = HouseholdMembership.mockMembers.first else { return }
                        await viewModel.markAsRead(feedback.id, readerId: firstMember.id)
                    }
                )
            }
        }
    }

    private var filteredFeedbacks: [Feedback] {
        switch filter {
        case .all:
            return viewModel.feedbacks
        case .unread:
            // 当前阅读者粗略以"是否在 readBy 数组里"判断；先用第一个 mock 成员作为占位的"我"。
            let me = HouseholdMembership.mockMembers.first?.id
            return viewModel.feedbacks.filter { feedback in
                guard let me else { return true }
                return (feedback.readBy ?? []).contains(me) == false
            }
        }
    }

    private var feedbackEmptyState: some View {
        let isFirstEmpty = viewModel.feedbacks.isEmpty
        return EmptyStateView(
            systemImage: isFirstEmpty ? "bubble.left.and.bubble.right" : "line.3.horizontal.decrease.circle",
            title: isFirstEmpty ? "还没有反馈消息" : "筛选后暂无消息",
            message: isFirstEmpty
                ? "家人提交语音反馈后会出现在这里。"
                : "当前筛选条件下没有匹配项，试试切换到“全部”。",
            primaryActionTitle: isFirstEmpty ? "重新加载" : "查看全部消息",
            primaryAction: {
                if isFirstEmpty {
                    Task {
                        await viewModel.loadFeedbacks()
                    }
                } else {
                    filter = .all
                }
            },
            secondaryActionTitle: isFirstEmpty ? nil : "仅看未读",
            secondaryAction: isFirstEmpty ? nil : {
                filter = .unread
            }
        )
    }
}

// MARK: - Card

private struct FeedbackCardView: View {
    let feedback: Feedback
    let task: FamilyTask?
    let showTranscription: Bool
    let onMarkRead: () async -> Void
    @State private var progress: Double = 0
    @State private var isPlaying = false

    private var isReadByMe: Bool {
        guard let me = HouseholdMembership.mockMembers.first?.id else { return false }
        return (feedback.readBy ?? []).contains(me)
    }

    private var senderName: String {
        guard let senderId = feedback.senderId else { return "系统" }
        return MemberDisplayName.displayName(
            forMembershipId: senderId,
            members: HouseholdMembership.mockMembers,
            profiles: FamilyProfile.mockProfiles
        ) ?? "成员"
    }

    private var taskScheduledAt: Date? {
        task.flatMap { $0.dueDate ?? $0.originalDueDate }
    }

    private var taskLocationLabel: String? {
        task?.locationData?.name ?? task?.locationData?.address
    }

    var body: some View {
        Group {
            if feedback.isSystemMessage {
                Text(feedback.content ?? "系统消息")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                regularMessageCard
            }
        }
    }

    private var regularMessageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let task {
                VStack(alignment: .leading, spacing: 4) {
                    Label("引用任务", systemImage: "quote.opening")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        if let taskScheduledAt {
                            Text(taskScheduledAt.formatted(date: .omitted, time: .shortened))
                        }
                        Text(task.title)
                    }
                    .font(.system(size: 20, weight: .semibold))
                    Text(taskLocationLabel ?? "未设置地点")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 34, height: 34)
                    .overlay(Text(String(senderName.prefix(1))).font(.headline))
                VStack(alignment: .leading, spacing: 2) {
                    Text(senderName)
                        .font(.system(size: 20, weight: .semibold))
                    HStack(spacing: 6) {
                        Text(feedback.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        if feedback.showsEditedBadge {
                            Text("(已编辑)")
                                .font(.system(size: 10))
                                .foregroundStyle(.gray.opacity(0.6))
                        }
                    }
                }
            }

            if feedback.hasVoiceAttachment {
                HStack(spacing: 12) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .foregroundStyle(.blue)
                        .frame(width: 36, height: 36)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Circle())
                        .onTapGesture {
                            Task {
                                await togglePlayback()
                            }
                        }

                    Capsule()
                        .fill(Color.blue.opacity(0.25))
                        .frame(height: 6)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.blue)
                                .frame(width: CGFloat(max(0.06, progress)) * 165, height: 6)
                                .animation(.linear(duration: 0.15), value: progress)
                        }

                    Text("语音")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let text = feedback.content,
               text.isEmpty == false,
               showTranscription || feedback.hasVoiceAttachment == false {
                Label {
                    Text(text)
                        .font(.system(size: 16, weight: .medium))
                } icon: {
                    Image(systemName: feedback.hasVoiceAttachment ? "sparkles" : "text.bubble")
                        .foregroundStyle(.blue)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.gray.opacity(0.2), lineWidth: 2)
        )
        .opacity(isReadByMe ? 0.56 : 1)
        .animation(.easeInOut(duration: 0.25), value: isReadByMe)
        .onTapGesture {
            if isReadByMe == false {
                Task {
                    await onMarkRead()
                }
            }
        }
    }

    private func togglePlayback() async {
        if isPlaying {
            isPlaying = false
            return
        }

        guard feedback.absoluteVoiceURL() != nil else { return }

        isPlaying = true
        progress = 0
        let playbackDuration = 3
        let steps = playbackDuration * 10

        for step in 1...steps {
            if isPlaying == false { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
            progress = Double(step) / Double(steps)
        }

        isPlaying = false
        progress = 0
    }
}

#Preview {
    FeedbackFeedView()
        .environmentObject(AppBootstrap())
        .environmentObject(AppRouter())
}

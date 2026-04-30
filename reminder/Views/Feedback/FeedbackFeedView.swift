import SwiftUI

struct FeedbackFeedView: View {
    @EnvironmentObject private var appBootstrap: AppBootstrap
    @StateObject private var viewModel = AppViewModels.makeFeedbackFeedViewModel()
    @State private var filter: FeedbackFilter = .all

    private enum FeedbackFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case unread = "未读"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    filterBar
                    simulateVoiceButton
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 96)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
        }
        .task {
            await viewModel.loadFeedbacks()
            await viewModel.startRealtime()
        }
        .onDisappear {
            _Concurrency.Task {
                await viewModel.stopRealtime()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("消息中心")
                .font(.system(size: 36, weight: .bold))
            Text("异步反馈与提醒")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
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
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var simulateVoiceButton: some View {
        Button {
            _Concurrency.Task {
                guard
                    let task = Task.mockTasks.first,
                    let sender = FamilyMember.mockMembers.first
                else {
                    return
                }
                let audioData = Data(repeating: 0x10, count: 2048)
                await viewModel.uploadVoiceFeedback(
                    taskId: task.id,
                    senderId: sender.id,
                    audioData: audioData,
                    duration: 4
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
                    _Concurrency.Task {
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
                    task: Task.mockTasks.first(where: { $0.id == feedback.taskId }),
                    showTranscription: appBootstrap.featureFlags.enableAITranscription,
                    onMarkRead: {
                        await viewModel.markAsRead(feedback.id)
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
            return viewModel.feedbacks.filter { $0.isRead == false }
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
                    _Concurrency.Task {
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

private struct FeedbackCardView: View {
    let feedback: Feedback
    let task: Task?
    let showTranscription: Bool
    let onMarkRead: () async -> Void
    @State private var progress: Double = 0
    @State private var isPlaying = false

    private var borderColor: Color {
        feedback.type == .system ? .red.opacity(0.4) : .gray.opacity(0.2)
    }

    private var senderName: String {
        FamilyMember.mockMembers.first(where: { $0.id == feedback.senderId })?.displayName ?? "系统"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let task {
                VStack(alignment: .leading, spacing: 4) {
                    Label("引用任务", systemImage: "quote.opening")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(task.scheduledAt.formatted(date: .omitted, time: .shortened)) \(task.title)")
                        .font(.system(size: 20, weight: .semibold))
                    Text(task.location ?? "未设置地点")
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
                    Text(feedback.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if feedback.type == .voice || feedback.audioDurationSeconds != nil {
                HStack(spacing: 12) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .foregroundStyle(.blue)
                        .frame(width: 36, height: 36)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Circle())
                        .onTapGesture {
                            _Concurrency.Task {
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

                    Text("0:\(String(format: "%02d", feedback.audioDurationSeconds ?? 0))")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let text = feedback.text, showTranscription || feedback.type != .voice {
                Label {
                    Text(text)
                        .font(.system(size: 16, weight: .medium))
                } icon: {
                    Image(systemName: "sparkles")
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
                .stroke(borderColor, lineWidth: 2)
        )
        .opacity(feedback.isRead ? 0.56 : 1)
        .animation(.easeInOut(duration: 0.25), value: feedback.isRead)
        .onTapGesture {
            if feedback.isRead == false {
                _Concurrency.Task {
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

        isPlaying = true
        progress = 0
        let duration = max(1, feedback.audioDurationSeconds ?? 3)
        let steps = duration * 10

        for step in 1...steps {
            if isPlaying == false { break }
            try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
            progress = Double(step) / Double(steps)
        }

        isPlaying = false
        progress = 0
    }
}

#Preview {
    FeedbackFeedView()
        .environmentObject(AppBootstrap())
}

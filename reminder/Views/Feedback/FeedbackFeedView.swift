import SwiftUI

struct FeedbackFeedView: View {
    @StateObject private var viewModel = AppViewModels.makeFeedbackFeedViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    ForEach(viewModel.feedbacks) { feedback in
                        FeedbackCardView(
                            feedback: feedback,
                            task: Task.mockTasks.first(where: { $0.id == feedback.taskId }),
                            onMarkRead: {
                                await viewModel.markAsRead(feedback.id)
                            }
                        )
                    }
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
}

private struct FeedbackCardView: View {
    let feedback: Feedback
    let task: Task?
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

            if let text = feedback.text {
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
}

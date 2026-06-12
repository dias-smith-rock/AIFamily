import SwiftUI

struct AssistantSheetView: View {
    /// Aligns with the schedule week calendar anchor day (`startOfDay`) for parsing relative dates like "tomorrow".
    let scheduleAnchorDay: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @StateObject private var viewModel = AppViewModels.makeAssistantViewModel()
    @FocusState private var isComposerFocused: Bool

    init(scheduleAnchorDay: Date = Calendar.current.startOfDay(for: Date())) {
        self.scheduleAnchorDay = scheduleAnchorDay
    }

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
            .onAppear {
                viewModel.setReferenceCalendarDay(scheduleAnchorDay)
            }
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
                    Text(L10n.Common.aiAssistant.localized)
                        .font(.title2.weight(.bold))
                    Text(L10n.Schedule.intelligentParsingTasks.localized)
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
                Text(L10n.Schedule.helloICanHelpYouCreateTasksQuicklyYouCa.localized)
                Text(L10n.Common.pasteWechatNotificationText.localized)
                Text(L10n.Common.uploadScreenshotsOfSchoolNotifications.localized)
                Text(L10n.Assistant.speakTheRequirementsDirectlyByVoice.localized)
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
            ProgressView(L10n.Schedule.parsingTask.localized)
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
                    await viewModel.confirmSend(
                        householdId: householdId,
                        creatorMembershipId: creatorMembershipId,
                        involvedMemberIds: nil
                    )
                },
                onCorrection: { correction in
                    await viewModel.applyNaturalLanguageCorrection(correction)
                }
            )
        case .sending:
            ProgressView(L10n.Schedule.writingTask.localized)
                .padding(12)
        case let .sent(task):
            ContentUnavailableView {
                Text(L10n.Common.sent.formatted(locale: locale, task.title))
            } description: {
                Text(L10n.Schedule.theTaskHasBeenWrittenIntoTheScheduleAnd.localized)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
        case let .failed(message):
            ContentUnavailableView(
                L10n.Common.parsingFailed,
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            iconButton("photo.badge.plus")
            iconButton("mic")

            TextField(L10n.Common.pasteANotificationOrSayARequest.localized, text: $viewModel.inputText)
                .textFieldStyle(.plain)
                .focused($isComposerFocused)
                .clipboardPasteOnFocus(when: isComposerFocused, text: $viewModel.inputText)
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
    @FocusState private var isCorrectionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Schedule.taskConfirmationPreflightCard.localized)
                .font(.system(size: 16, weight: .bold))
            Label(draft.title, systemImage: "checklist")
            Label(
                "\(draft.dueDate.formatted(date: .abbreviated, time: .omitted)) \(ScheduleTimeFormatting.timelineClockTime(draft.dueDate))",
                systemImage: "clock"
            )
            if let location = draft.locationName {
                Label(location, systemImage: "location")
            }
            if let profileIds = draft.targetProfileIds, profileIds.isEmpty == false {
                Label("\(profileIds.count)", systemImage: "person")
            }
            TextField(L10n.Common.naturalLanguageCorrectionEGChangeTheTime.localized, text: $correction)
                .textFieldStyle(.roundedBorder)
                .focused($isCorrectionFocused)
                .clipboardPasteOnFocus(when: isCorrectionFocused, text: $correction)
            HStack {
                Button(L10n.Common.applyCorrection) {
                    Task {
                        await onCorrection(correction)
                    }
                }
                .buttonStyle(.bordered)

                Button(L10n.Common.confirmSending) {
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

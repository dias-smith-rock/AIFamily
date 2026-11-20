import SwiftUI

struct VoiceTaskDraftContext: Equatable {
    let userID: UUID?
    let householdID: UUID?
    let membershipID: UUID?
}

struct VoiceTaskDraftResult {
    let task: AIParsedTaskPayload
    let sourceText: String
    let context: VoiceTaskDraftContext
}

struct VoiceTaskDraftHandoff {
    var pending: VoiceTaskDraftResult?

    mutating func take(for context: VoiceTaskDraftContext) -> VoiceTaskDraftResult? {
        let result = pending
        pending = nil
        guard result?.context == context else { return nil }
        return result
    }
}

@MainActor private extension AppRouter {
    var voiceTaskDraftContext: VoiceTaskDraftContext {
        VoiceTaskDraftContext(userID: authUserId, householdID: selectedHouseholdId, membershipID: selectedMembershipId)
    }
}

extension View {
    func taskVoiceDraftSheet(isPresented: Binding<Bool>, onDraft: @escaping (AIParsedTaskPayload, String) -> Void) -> some View {
        modifier(TaskVoiceDraftPresentation(isPresented: isPresented, onDraft: onDraft))
    }
}

private struct TaskVoiceDraftPresentation: ViewModifier {
    var isPresented: Binding<Bool>
    var onDraft: (AIParsedTaskPayload, String) -> Void
    @EnvironmentObject private var appRouter: AppRouter
    @State private var handoff = VoiceTaskDraftHandoff()

    func body(content: Content) -> some View {
        content.sheet(isPresented: isPresented, onDismiss: {
            guard let result = handoff.take(for: appRouter.voiceTaskDraftContext) else { return }
            onDraft(result.task, result.sourceText)
        }) {
            TaskVoiceDraftSheet { result in handoff.pending = result }
        }
        .onChange(of: appRouter.voiceTaskDraftContext) { _, _ in handoff.pending = nil }
    }
}

/// Recognition never saves a task. The caller presents the existing editable form.
private struct TaskVoiceDraftSheet: View {
    var onDraft: (VoiceTaskDraftResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appRouter: AppRouter
    @State private var submittedInput: TaskVoiceRecognitionInput?
    @State private var processing = false
    @State private var error: String?
    @State private var showCloudChoice = false
    @State private var request: Task<Void, Never>?
    var body: some View {
        VStack {
            if processing {
                ProgressView("Preparing task draft…")
                Button("Cancel", role: .cancel) { request?.cancel(); dismiss() }
            }
            if let error { Text(error).foregroundStyle(.red).padding() }
            VoiceTaskCreationSheet { text, locale in
                let input = TaskVoiceRecognitionInput(
                    text: text, locale: locale, referenceDate: Date(),
                    timeZone: AppDisplayTimeZone.effectiveTimeZone
                )
                submittedInput = input
                recognize(input, cloud: false)
            }
            .disabled(processing)
        }
        .alert("Use cloud recognition?", isPresented: $showCloudChoice) {
            Button("Upload text and recognize") {
                guard let submittedInput else { return }
                recognize(submittedInput, cloud: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only the confirmed text will be sent to the cloud service. Audio is not uploaded.")
        }
        .onDisappear { request?.cancel() }
        .onChange(of: appRouter.voiceTaskDraftContext) { _, _ in request?.cancel(); dismiss() }
    }
    private func recognize(_ input: TaskVoiceRecognitionInput, cloud: Bool) {
        guard !processing, PremiumLimits.canUseAIPhotoTaskCreation(hasPremium: appRouter.hasPremiumAccess) else { return }
        let context = appRouter.voiceTaskDraftContext
        error = nil
        processing = true
        request = Task { @MainActor in
            defer { processing = false }
            do {
                let draft: AIParsedTaskPayload
                if cloud {
                    draft = try await CloudTextTaskParserService().parse(input)
                } else {
                    draft = try await AppleTaskRecognitionService().parseText(input.text, referenceDate: input.referenceDate,
                        timeZone: input.timeZone, locale: input.locale)
                }
                try Task.checkCancellation()
                guard context == appRouter.voiceTaskDraftContext else { return }
                onDraft(VoiceTaskDraftResult(task: draft, sourceText: input.text, context: context))
                dismiss()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                if !cloud { showCloudChoice = true }
            }
        }
    }
}

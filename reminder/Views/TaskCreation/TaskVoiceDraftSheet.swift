import SwiftUI

/// Recognition never saves a task. The caller presents the existing editable form.
struct TaskVoiceDraftSheet: View {
    var onDraft: (AIParsedTaskPayload, String) -> Void
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
        .onChange(of: appRouter.selectedHouseholdId) { _, _ in request?.cancel(); dismiss() }
        .onChange(of: appRouter.selectedMembershipId) { _, _ in request?.cancel(); dismiss() }
    }
    private func recognize(_ input: TaskVoiceRecognitionInput, cloud: Bool) {
        guard !processing, PremiumLimits.canUseAIPhotoTaskCreation(hasPremium: appRouter.hasPremiumAccess) else { return }
        let household = appRouter.selectedHouseholdId
        let membership = appRouter.selectedMembershipId
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
                guard household == appRouter.selectedHouseholdId, membership == appRouter.selectedMembershipId else { return }
                dismiss()
                // Let the recording sheet dismiss before the parent presents the draft.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard household == appRouter.selectedHouseholdId, membership == appRouter.selectedMembershipId else { return }
                    onDraft(draft, input.text)
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                if !cloud { showCloudChoice = true }
            }
        }
    }
}

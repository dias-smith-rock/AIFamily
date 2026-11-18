import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

/// Recognition never saves a task. The caller presents the existing editable form.
struct TaskVoiceDraftSheet: View {
    var onDraft: (AIParsedTaskPayload) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appRouter: AppRouter
    @State private var text = ""
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
            VoiceTaskCreationSheet { input in
                text = input
                recognize(cloud: false)
            }
            .disabled(processing)
        }
        .alert("Use cloud recognition?", isPresented: $showCloudChoice) {
            Button("Upload text and recognize") { recognize(cloud: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only the confirmed text will be sent to the cloud service. Audio is not uploaded.")
        }
        .onDisappear { request?.cancel() }
    }
    private func recognize(cloud: Bool) {
        guard !processing, PremiumLimits.canUseAIPhotoTaskCreation(hasPremium: appRouter.hasPremiumAccess) else { return }
        let household = appRouter.selectedHouseholdId
        let input = text
        error = nil
        processing = true
        request = Task { @MainActor in
            defer { processing = false }
            do {
                let draft: AIParsedTaskPayload
                if cloud {
                    draft = try await CloudTextTaskParserService().parse(input)
                } else {
                    draft = try await AppleTaskRecognitionService().parseText(input, referenceDate: Date(),
                        timeZone: AppDisplayTimeZone.effectiveTimeZone, locale: Locale.current)
                }
                try Task.checkCancellation()
                guard household == appRouter.selectedHouseholdId else { return }
                dismiss()
                // Let the recording sheet dismiss before the parent presents the draft.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard household == appRouter.selectedHouseholdId else { return }
                    onDraft(draft)
                }
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
                if !cloud { showCloudChoice = true }
            }
        }
    }
}

struct CloudTextTaskParserService {
    func parse(_ text: String) async throws -> AIParsedTaskPayload {
        #if canImport(Supabase)
        let client = SupabaseManager.shared.client
        _ = try await client.auth.session
        struct Response: Decodable { let success: Bool; let task: AIParsedTaskPayload? }
        let body = ["text": text, "reference_instant": ISO8601DateFormatter().string(from: Date()),
                    "time_zone": AppDisplayTimeZone.effectiveTimeZone.identifier,
                    "locale": Locale.current.identifier]
        let result: Response = try await client.functions.invoke("parse-create-task-from-text",
            options: FunctionInvokeOptions(body: body))
        guard result.success, let task = result.task else { throw AITaskParserError.invalidResponse }
        return task
        #else
        throw AITaskParserError.sdkUnavailable
        #endif
    }
}

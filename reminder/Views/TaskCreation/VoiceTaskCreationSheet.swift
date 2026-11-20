import SwiftUI
import Combine
import AVFoundation

@MainActor
private final class VoiceCaptureModel: ObservableObject {
    @Published var text = ""
    @Published private var lifecycle = VoiceCaptureSessionState()
    @Published var message: String?
    var busy: Bool { lifecycle.busy }
    var recording: Bool { lifecycle.recording }
    private var service: (any SpeechTaskTranscribing)?
    private var work: Task<Void, Never>?
    private var deadline: Task<Void, Never>?

    func start(locale: Locale) {
        guard let token = lifecycle.begin() else { return }
        message = "正在检查本地语音资源，首次使用可能需要下载语言模型…"
        work = Task { [self] in
            do {
                let allowed = await AVAudioApplication.requestRecordPermission()
                guard allowed else { throw TaskSpeechError.permission }
                try Task.checkCancellation()
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
                try session.setActive(true)
                let transcriber = makeTaskSpeechTranscriber()
                service = transcriber
                try await transcriber.start(locale: locale, onText: { [weak self] text in
                    guard let self, self.lifecycle.acceptsResults(token) else { return }
                    self.text = text
                }, onFailure: { [weak self] _ in
                    guard let self, self.lifecycle.acceptsResults(token) else { return }
                    Task {
                        // Recheck after scheduling: cancellation may already have occurred.
                        guard self.lifecycle.acceptsResults(token) else { return }
                        await self.cancel()
                        self.message = "语音识别已停止，请编辑已有文字或重试。"
                    }
                })
                try Task.checkCancellation()
                guard lifecycle.markRecording(token) else { return }
                message = "正在本地识别，最长 60 秒。"
                deadline = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled, let self,
                          self.lifecycle.shouldStop(token, elapsed: 60) else { return }
                    await self.stop()
                }
            } catch {
                guard lifecycle.acceptsResults(token) else { return }
                let reason = error.localizedDescription
                await cancel()
                message = reason
            }
        }
    }
    func stop() async {
        let token = lifecycle.token
        guard lifecycle.beginFinishing(token) else { return }
        deadline?.cancel(); deadline = nil
        message = "正在完成转写…"
        let active = service
        await active?.stop()
        guard lifecycle.complete(token) else { return }
        service = nil
        message = text.isEmpty ? "未识别到文字，可以重试或直接输入。" : "请核对文字后生成草稿。"
        releaseAudio()
    }
    func cancel() async {
        guard let cancellation = lifecycle.beginCancelling() else { return }
        work?.cancel(); work = nil
        deadline?.cancel(); deadline = nil
        let active = service; service = nil
        await active?.cancel()
        guard lifecycle.complete(cancellation) else { return }
        releaseAudio()
    }
    private func releaseAudio() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Collects text only. The caller owns parsing, cloud consent, and draft presentation.
struct VoiceTaskCreationSheet: View {
    let onText: (String, Locale) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = VoiceCaptureModel()
    @State private var language = Locale.current.identifier
    @FocusState private var isEditingTranscript: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("识别语言", selection: $language) {
                        Text("系统语言").tag(Locale.current.identifier)
                        if Locale.current.identifier != "zh-CN" { Text("普通话").tag("zh-CN") }
                        if Locale.current.identifier != "zh-TW" { Text("繁體中文").tag("zh-TW") }
                        if Locale.current.identifier != "en-US" { Text("English").tag("en-US") }
                    }
                    .disabled(model.busy || model.recording)
                    Button {
                        if model.recording { Task { await model.stop() } }
                        else { model.start(locale: Locale(identifier: language)) }
                    } label: {
                        Label(model.recording ? "停止录音" : "开始说话", systemImage: model.recording ? "stop.circle.fill" : "mic.fill")
                    }
                    .disabled(model.busy)
                    if model.busy { ProgressView() }
                    if let message = model.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                } footer: {
                    Text("语音在设备上识别，不上传录音。不支持的语言可直接输入文字。")
                }
                Section("核对并编辑文字") {
                    TextEditor(text: $model.text)
                        .frame(minHeight: 180)
                        .focused($isEditingTranscript)
                        .disabled(model.recording || model.busy)
                }
            }
            .navigationTitle("说话创建任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { Task { await model.cancel(); dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("生成草稿") {
                        let text = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        isEditingTranscript = false
                        onText(text, Locale(identifier: language))
                    }
                    .disabled(model.busy || model.recording || model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onDisappear { Task { await model.cancel() } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await model.cancel() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
            Task { await model.cancel() }
        }
    }
}

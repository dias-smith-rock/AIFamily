import SwiftUI
import AVFoundation

@MainActor
private final class VoiceCaptureModel: ObservableObject {
    @Published var text = ""
    @Published var busy = false
    @Published var recording = false
    @Published var message: String?
    private var service: (any SpeechTaskTranscribing)?
    private var work: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var generation = UUID()

    func start(locale: Locale) {
        guard !busy, !recording else { return }
        busy = true
        message = "正在检查本地语音资源，首次使用可能需要下载语言模型…"
        let token = UUID(); generation = token
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
                    guard let self, self.generation == token else { return }
                    self.text = text
                }, onFailure: { [weak self] error in
                    guard let self, self.generation == token else { return }
                    Task {
                        await self.cancel()
                        self.message = "语音识别已停止，请编辑已有文字或重试。"
                    }
                })
                try Task.checkCancellation()
                guard generation == token else { return }
                busy = false; recording = true; message = "正在本地识别，最长 60 秒。"
                deadline = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled else { return }
                    await self?.stop()
                }
            } catch {
                guard generation == token else { return }
                message = error.localizedDescription
                busy = false; recording = false
                await service?.cancel(); service = nil
                releaseAudio()
            }
        }
    }
    func stop() async {
        guard recording else { return }
        recording = false; busy = true
        deadline?.cancel(); deadline = nil
        message = "正在完成转写…"
        await service?.stop(); service = nil
        busy = false; message = text.isEmpty ? "未识别到文字，可以重试或直接输入。" : "请核对文字后生成草稿。"
        releaseAudio()
    }
    func cancel() async {
        generation = UUID()
        work?.cancel(); work = nil
        deadline?.cancel(); deadline = nil
        let active = service; service = nil
        await active?.cancel()
        recording = false; busy = false
        releaseAudio()
    }
    private func releaseAudio() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Collects text only. The caller owns parsing, cloud consent, and draft presentation.
struct VoiceTaskCreationSheet: View {
    let onText: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = VoiceCaptureModel()
    @State private var language = Locale.current.identifier

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
                        .disabled(model.recording || model.busy)
                }
                Section {
                    Button("生成草稿") {
                        let text = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        onText(text)
                    }
                    .disabled(model.busy || model.recording || model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("说话创建任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { Task { await model.cancel(); dismiss() } }
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

import AVFoundation
import Speech

/// All implementations are local-only. There is intentionally no online fallback.
@MainActor
protocol SpeechTaskTranscribing: AnyObject {
    func start(locale: Locale, onText: @escaping (String) -> Void, onFailure: @escaping (Error) -> Void) async throws
    func stop() async
    func cancel() async
}

enum TaskSpeechError: LocalizedError {
    case unavailable, permission, audioFormat
    var errorDescription: String? {
        switch self {
        case .unavailable: return "此设备或语言暂不支持本地语音识别，请尝试其他语言或输入文字。"
        case .permission: return "请在系统设置中允许麦克风和语音识别，或直接输入文字。"
        case .audioFormat: return "无法使用当前麦克风，请检查音频设备后重试。"
        }
    }
}

@MainActor
func makeTaskSpeechTranscriber() -> any SpeechTaskTranscribing {
    if #available(iOS 26, *) { return ModernSpeechTaskTranscriber() }
    return LegacySpeechTaskTranscriber()
}

@MainActor
final class LegacySpeechTaskTranscriber: SpeechTaskTranscribing {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var tapped = false
    private var generation = UUID()
    private var finished = false

    func start(locale: Locale, onText: @escaping (String) -> Void, onFailure: @escaping (Error) -> Void) async throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else { throw TaskSpeechError.unavailable }
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard authorization == .authorized else { throw TaskSpeechError.permission }
        try Task.checkCancellation()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        let token = generation
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if let result { onText(result.bestTranscription.formattedString) }
                if result?.isFinal == true || error != nil { self.finished = true }
                if let error { onFailure(error) }
            }
        }
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw TaskSpeechError.audioFormat }
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        tapped = true
        engine.prepare()
        try engine.start()
    }
    private func stopCapture() {
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio()
    }
    func stop() async {
        stopCapture()
        // Give the recognizer a bounded window to finalize the last hypothesis.
        for _ in 0..<30 {
            if finished || Task.isCancelled { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        await cancel()
    }
    func cancel() async {
        generation = UUID()
        stopCapture()
        recognition?.cancel(); recognition = nil; request = nil
    }
}

import AVFoundation
import Speech

@available(iOS 26, *)
@MainActor
final class ModernSpeechTaskTranscriber: SpeechTaskTranscribing {
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var tapped = false
    private var fallback: LegacySpeechTaskTranscriber?

    func start(locale: Locale, onText: @escaping (String) -> Void, onFailure: @escaping (Error) -> Void) async throws {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            let fallback = LegacySpeechTaskTranscriber()
            self.fallback = fallback
            try await fallback.start(locale: locale, onText: onText, onFailure: onFailure)
            return
        }
        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        if let download = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await download.downloadAndInstall()
        }
        try Task.checkCancellation()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TaskSpeechError.audioFormat
        }
        let source = engine.inputNode.outputFormat(forBus: 0)
        guard source.sampleRate > 0, source.channelCount > 0,
              let converter = AVAudioConverter(from: source, to: format) else { throw TaskSpeechError.audioFormat }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        input = continuation
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        resultsTask = Task {
            var finalText = ""
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else { return }
                    // This preset emits finalized, nonoverlapping segments only.
                    finalText += String(result.text.characters)
                    onText(finalText)
                }
            } catch {
                if !Task.isCancelled { onFailure(error) }
            }
        }
        try await analyzer.start(inputSequence: stream)
        try Task.checkCancellation()
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: source) { buffer, _ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / source.sampleRate) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, state in
                if supplied { state.pointee = .noDataNow; return nil }
                supplied = true; state.pointee = .haveData; return buffer
            }
            if status != .error, converted.frameLength > 0 {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
        tapped = true
        engine.prepare()
        try engine.start()
    }
    private func stopCapture() {
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        input?.finish(); input = nil
    }
    func stop() async {
        if let fallback { await fallback.stop(); return }
        stopCapture()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        resultsTask = nil; analyzer = nil
    }
    func cancel() async {
        if let fallback { await fallback.cancel(); self.fallback = nil }
        stopCapture()
        resultsTask?.cancel(); resultsTask = nil
        await analyzer?.cancelAndFinishNow(); analyzer = nil
    }
}

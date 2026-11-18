import Foundation

/// Pure lifecycle policy shared by capture UI and its executable regression harness.
/// Cancellation invalidates callbacks immediately, while keeping controls locked until
/// microphone cleanup completes. A stale completion can never finish a newer session.
struct VoiceCaptureSessionState {
    enum Phase { case idle, preparing, recording, finishing, cancelling }
    private(set) var phase: Phase = .idle
    private(set) var token = UUID()
    var busy: Bool { phase == .preparing || phase == .finishing || phase == .cancelling }
    var recording: Bool { phase == .recording }

    mutating func begin() -> UUID? {
        guard phase == .idle else { return nil }
        token = UUID(); phase = .preparing
        return token
    }
    func acceptsResults(_ candidate: UUID) -> Bool {
        token == candidate && (phase == .preparing || phase == .recording || phase == .finishing)
    }
    mutating func markRecording(_ candidate: UUID) -> Bool {
        guard token == candidate, phase == .preparing else { return false }
        phase = .recording; return true
    }
    mutating func beginFinishing(_ candidate: UUID) -> Bool {
        guard token == candidate, phase == .recording else { return false }
        phase = .finishing; return true
    }
    mutating func beginCancelling() -> UUID? {
        guard phase != .idle, phase != .cancelling else { return nil }
        token = UUID(); phase = .cancelling
        return token
    }
    mutating func complete(_ candidate: UUID) -> Bool {
        guard token == candidate, phase != .idle else { return false }
        phase = .idle; return true
    }
    func shouldStop(_ candidate: UUID, elapsed: TimeInterval) -> Bool {
        token == candidate && phase == .recording && elapsed >= 60
    }
}

/// Volatile revisions replace one segment. Finalized segments are immutable and
/// deduplicated by their audio-range identity, including repeated final callbacks.
struct SpeechTranscriptAccumulator {
    private var order: [String] = []
    private var texts: [String: String] = [:]
    private var finalized: Set<String> = []
    var text: String { order.compactMap { texts[$0] }.joined() }
    var finalText: String { order.filter { finalized.contains($0) }.compactMap { texts[$0] }.joined() }
    mutating func update(segment: String, text: String, isFinal: Bool) {
        guard !finalized.contains(segment) else { return }
        if texts[segment] == nil { order.append(segment) }
        texts[segment] = text
        if isFinal { finalized.insert(segment) }
    }
}

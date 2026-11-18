import Foundation

@main
struct VoiceCaptureStateHarness {
    static func main() {
        var state = VoiceCaptureSessionState()
        let first = state.begin()!
        precondition(state.begin() == nil, "Double start must not create another recording")
        precondition(state.markRecording(first))
        precondition(!state.shouldStop(first, elapsed: 59.9))
        precondition(state.shouldStop(first, elapsed: 60))
        precondition(state.beginFinishing(first))
        precondition(state.acceptsResults(first), "Final result must be accepted during stop")
        let cancellation = state.beginCancelling()!
        precondition(state.beginCancelling() == nil, "Repeated cleanup must not unlock an active cancellation")
        precondition(!state.acceptsResults(first), "Cancel must immediately reject late results")
        precondition(state.begin() == nil, "Do not reactivate audio until cleanup finishes")
        precondition(!state.complete(first), "Old stop must not finish cancellation")
        precondition(state.complete(cancellation))
        let second = state.begin()!
        precondition(!state.complete(first), "Late stop must not release the next recording")
        precondition(!state.acceptsResults(first))
        precondition(state.acceptsResults(second))
        precondition(!state.shouldStop(first, elapsed: 100), "Old timer must not stop new capture")
        precondition(state.markRecording(second))
        precondition(state.beginFinishing(second))
        precondition(state.complete(second))
        precondition(!state.acceptsResults(second), "Completed capture must reject callbacks")

        var permissionWait = VoiceCaptureSessionState()
        let pending = permissionWait.begin()!
        precondition(!permissionWait.beginFinishing(pending), "Cannot stop before microphone capture starts")
        let interrupted = permissionWait.beginCancelling()!
        precondition(!permissionWait.markRecording(pending), "Late permission approval must not restart interrupted capture")
        precondition(permissionWait.complete(interrupted))
        precondition(permissionWait.begin() != nil, "Permission denial or interruption must allow retry")

        var transcript = SpeechTranscriptAccumulator()
        transcript.update(segment: "a", text: "明", isFinal: false)
        transcript.update(segment: "a", text: "明天", isFinal: false)
        precondition(transcript.text == "明天", "Partial hypotheses replace, never append")
        transcript.update(segment: "a", text: "明天下午", isFinal: true)
        transcript.update(segment: "a", text: "明天下午", isFinal: true)
        transcript.update(segment: "a", text: "迟到的临时结果", isFinal: false)
        transcript.update(segment: "b", text: "三点", isFinal: false)
        precondition(transcript.text == "明天下午三点")
        precondition(transcript.finalText == "明天下午")
        transcript.update(segment: "b", text: "三点见面", isFinal: true)
        precondition(transcript.finalText == "明天下午三点见面", "Final segments submit once")
        print("Voice capture lifecycle and transcript regression checks passed")
    }
}

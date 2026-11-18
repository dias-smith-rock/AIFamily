import XCTest
@testable import Calendly

@MainActor
final class TaskRecognitionTests: XCTestCase {
    func testLocalDatesRejectRolloverAndDSTAmbiguity() {
        let zone = TimeZone(identifier: "America/New_York")!
        XCTAssertNil(TaskRecognitionDateValidator.date("2026-02-30T15:00", timeZone: zone))
        XCTAssertNil(TaskRecognitionDateValidator.date("2026-03-08T02:30", timeZone: zone))
        XCTAssertNil(TaskRecognitionDateValidator.date("2026-11-01T01:30", timeZone: zone))
        XCTAssertNotNil(TaskRecognitionDateValidator.date("2026-11-19T15:00", timeZone: zone))
        XCTAssertNil(TaskRecognitionDateValidator.date("2026-11-19", timeZone: zone))
        XCTAssertNotNil(TaskRecognitionDateValidator.date("2026-11-19", timeZone: zone, allDay: true))
    }

    func testCancellationRejectsLateCallbacksAndWaitsForCleanup() throws {
        var state = VoiceCaptureSessionState()
        let first = try XCTUnwrap(state.begin())
        XCTAssertNil(state.begin())
        XCTAssertTrue(state.markRecording(first))
        XCTAssertFalse(state.shouldStop(first, elapsed: 59.9))
        XCTAssertTrue(state.shouldStop(first, elapsed: 60))
        XCTAssertTrue(state.beginFinishing(first))
        XCTAssertTrue(state.acceptsResults(first))
        let cancellation = try XCTUnwrap(state.beginCancelling())
        XCTAssertFalse(state.acceptsResults(first))
        XCTAssertNil(state.begin())
        XCTAssertFalse(state.complete(first))
        XCTAssertTrue(state.complete(cancellation))
        let second = try XCTUnwrap(state.begin())
        XCTAssertFalse(state.complete(first))
        XCTAssertFalse(state.shouldStop(first, elapsed: 100))
        XCTAssertTrue(state.acceptsResults(second))
    }

    func testTranscriptRevisionsReplaceAndFinalSegmentsDeduplicate() {
        var transcript = SpeechTranscriptAccumulator()
        transcript.update(segment: "first", text: "明", isFinal: false)
        transcript.update(segment: "first", text: "明天", isFinal: false)
        XCTAssertEqual(transcript.text, "明天")
        XCTAssertEqual(transcript.finalText, "")
        transcript.update(segment: "first", text: "明天下午", isFinal: true)
        transcript.update(segment: "first", text: "过期结果", isFinal: false)
        transcript.update(segment: "first", text: "重复结果", isFinal: true)
        transcript.update(segment: "second", text: "三点见面", isFinal: true)
        XCTAssertEqual(transcript.finalText, "明天下午三点见面")
    }

    func testCloudPayloadSnakeCaseFieldsAndNoTimeDefaults() throws {
        let json = #"{"title":"Meeting","due_date":"2027-01-01T15:00:00Z","end_datetime":"2027-01-01T17:00:00Z","is_all_day":false,"duration_minutes":120,"amount_yuan":12.5,"participant_hints":["Dad"],"task_type_hint":"scheduled"}"#
        let task = try JSONDecoder().decode(AIParsedTaskPayload.self, from: Data(json.utf8))
        XCTAssertNotNil(task.dueDate)
        XCTAssertEqual(try XCTUnwrap(task.endDatetime).timeIntervalSince(try XCTUnwrap(task.dueDate)), 7200)
        XCTAssertEqual(task.durationMinutes, 120)
        XCTAssertEqual(task.amountYuan, 12.5)
        XCTAssertEqual(task.participantHints, ["Dad"])
        let untimed = try JSONDecoder().decode(AIParsedTaskPayload.self, from: Data(#"{"title":"Buy milk"}"#.utf8))
        XCTAssertNil(untimed.dueDate)
        XCTAssertNil(untimed.endDatetime)
        XCTAssertFalse(untimed.isAllDay)
        XCTAssertTrue(untimed.participantHints.isEmpty)
    }

    func testParticipantNamesMustMatchUniquelyUsingActualProfiles() {
        let household = UUID()
        let first = FamilyProfile(id: UUID(), householdId: household, name: "小明", userId: nil)
        let second = FamilyProfile(id: UUID(), householdId: household, name: "小明", userId: nil)
        XCTAssertEqual(AIParticipantHintMatcher.match(hints: ["小明"], profiles: [first], memberships: []).targetProfileIds, [first.id])
        XCTAssertTrue(AIParticipantHintMatcher.match(hints: ["小明"], profiles: [first, second], memberships: []).targetProfileIds.isEmpty)
        XCTAssertTrue(AIParticipantHintMatcher.match(hints: ["小"], profiles: [first], memberships: []).targetProfileIds.isEmpty)
    }
    func testEnglishNamesContainingAllAreNotEveryoneHints() {
        let sally = FamilyProfile(id: UUID(), householdId: UUID(), name: "Sally", userId: nil)
        XCTAssertEqual(AIParticipantHintMatcher.match(hints: ["Sally"], profiles: [sally], memberships: []).targetProfileIds, [sally.id])
        XCTAssertTrue(AIParticipantHintMatcher.match(hints: ["Sally", "whole family"], profiles: [sally], memberships: []).targetProfileIds.isEmpty)
    }

}

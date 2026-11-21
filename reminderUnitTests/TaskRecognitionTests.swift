import XCTest
import UIKit
import Supabase
@testable import Calendly

@MainActor
final class TaskRecognitionTests: XCTestCase {
    func testCloudTextSDKInvokesExpectedRouteWithTextOnly() async throws {
        let input = TaskVoiceRecognitionInput(text: "Pick up the parcel", locale: Locale(identifier: "en-US"),
            referenceDate: Date(timeIntervalSince1970: 1_800_000_000), timeZone: TimeZone(secondsFromGMT: 0)!)
        let expectedBody = ["text": input.text, "locale": "en-US", "time_zone": "GMT",
            "reference_instant": ISO8601DateFormatter().string(from: input.referenceDate)]
        let client = FunctionsClient(url: URL(string: "https://example.invalid/functions/v1")!,
            headers: ["Authorization": "Bearer fixture-token"], fetch: { request in
                XCTAssertEqual(request.url?.path, "/functions/v1/parse-create-task-from-text")
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
                let body = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(request.httpBody))
                XCTAssertEqual(body, expectedBody)
                let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200,
                    httpVersion: nil, headerFields: nil)!
                return (Data(#"{"success":true,"task":{"title":"Pick up the parcel"}}"#.utf8), response)
            })
        let task = try await CloudTextTaskParserService().parse(input, using: client)
        XCTAssertEqual(task.title, input.text)
        XCTAssertNil(task.dueDate)
    }

    func testCloudTextSDKMapsServerErrorsWithoutShowingResponseBody() async throws {
        let input = TaskVoiceRecognitionInput(text: "Synthetic note", locale: .current,
            referenceDate: Date(), timeZone: .current)
        let failures: [(Int, CloudTextTaskParserError)] = [(400, .invalidInput), (401, .sessionExpired),
            (429, .rateLimited), (502, .unavailable)]
        for (status, expected) in failures {
            let client = FunctionsClient(url: URL(string: "https://example.invalid/functions/v1")!, fetch: { request in
                let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: status,
                    httpVersion: nil, headerFields: nil)!
                return (Data("synthetic internal detail".utf8), response)
            })
            do {
                _ = try await CloudTextTaskParserService().parse(input, using: client)
                XCTFail("Expected HTTP \(status) to fail")
            } catch let error as CloudTextTaskParserError {
                XCTAssertEqual(error, expected)
                XCTAssertFalse(error.localizedDescription.contains("synthetic internal detail"))
            }
        }
    }

    func testVoiceDraftHandoffConsumesOnceAfterDismissalAndRejectsStaleAccount() throws {
        let original = VoiceTaskDraftContext(userID: UUID(), householdID: UUID(), membershipID: UUID())
        let otherAccount = VoiceTaskDraftContext(userID: UUID(), householdID: original.householdID, membershipID: original.membershipID)
        let payload = try JSONDecoder().decode(AIParsedTaskPayload.self, from: Data(#"{"title":"Pick up the parcel"}"#.utf8))
        let result = VoiceTaskDraftResult(task: payload, sourceText: "Pick up the parcel tomorrow", context: original)
        var handoff = VoiceTaskDraftHandoff()
        XCTAssertNil(handoff.take(for: original))
        handoff.pending = result
        XCTAssertNil(handoff.take(for: otherAccount))
        XCTAssertNil(handoff.take(for: original))
        handoff.pending = result
        let ready = try XCTUnwrap(handoff.take(for: original))
        XCTAssertEqual(ready.task.title, payload.title)
        XCTAssertEqual(ready.sourceText, result.sourceText)
        XCTAssertNil(handoff.take(for: original))
    }

    func testCroppedPhotoTextForManualTaskPreservesOnlyReadableText() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 430)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 430))
            let style: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 36), .foregroundColor: UIColor.black]
            ("Pick up the parcel" as NSString).draw(at: CGPoint(x: 80, y: 90), withAttributes: style)
            ("Outside crop" as NSString).draw(at: CGPoint(x: 80, y: 340), withAttributes: style)
        }
        let region = NormalizedCropQuad(
            topLeft: CGPoint(x: 0.04, y: 0.05), topRight: CGPoint(x: 0.96, y: 0.05),
            bottomLeft: CGPoint(x: 0.04, y: 0.62), bottomRight: CGPoint(x: 0.96, y: 0.62)
        )
        let text = try await AppleTaskRecognitionService().editableImageText(image, region: region, locale: Locale(identifier: "en-US"))
        XCTAssertEqual(text, "Pick up the parcel")
    }

    func testEditablePhotoTextRejectsBlankCrop() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        }
        do {
            _ = try await AppleTaskRecognitionService().editableImageText(
                image, region: .defaultCentered(), locale: Locale(identifier: "en-US")
            )
            XCTFail("The blank crop should not produce editable text")
        } catch AppleTaskRecognitionError.noText {
            // The same error is shown by the photo failure panel.
        }
    }

    func testCloudFallbackKeepsSubmittedLanguageAndReferenceInstant() throws {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let input = TaskVoiceRecognitionInput(
            text: "Pick up the parcel tomorrow",
            locale: Locale(identifier: "en_US"),
            referenceDate: reference,
            timeZone: zone
        )
        let body = input.cloudBody
        XCTAssertEqual(body["text"], input.text)
        XCTAssertEqual(body["locale"], "en-US")
        XCTAssertEqual(body["time_zone"], "Asia/Shanghai")
        XCTAssertEqual(ISO8601DateFormatter().date(from: try XCTUnwrap(body["reference_instant"])), reference)
    }

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

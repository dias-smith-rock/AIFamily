import UIKit
import Foundation
import FoundationModels

// Standalone fixture harness supplies the app's DTO and crop shape without app dependencies.
struct AIParsedTaskPayload: Decodable {
    let due_date: String?
    let end_datetime: String?
    let duration_minutes: Int?
    let task_type_hint: String?
}
struct NormalizedCropQuad {
    var topLeft: CGPoint; var topRight: CGPoint; var bottomLeft: CGPoint; var bottomRight: CGPoint
    var isValidRegion: Bool { true } // Service additionally validates bounded convex geometry.
}

@main struct ImageValidationTests {
    @MainActor static func main() async throws {
        let service = AppleTaskRecognitionService()
        let locale = Locale(identifier: "en-US")
        for (input, expected) in [("   ", "empty"), (String(repeating: "a", count: 6001), "long")] {
            do {
                _ = try await service.parseText(input, referenceDate: Date(), timeZone: .gmt, locale: locale)
                fatalError("Expected input rejection")
            } catch AppleTaskRecognitionError.emptyInput { precondition(expected == "empty") }
            catch AppleTaskRecognitionError.inputTooLong { precondition(expected == "long") }
        }
        if #available(iOS 26.0, *) {
            func fields(start: String? = nil, end: String? = nil, duration: Int? = nil,
                        scheduled: Bool = false, explicitTime: Bool = true) -> AppleExtractedTask {
                AppleExtractedTask(actionable: true, urgent: false, title: "Submit tuition",
                    notes: nil, localStart: start, localEnd: end, hasExplicitTime: explicitTime,
                    isScheduledEvent: scheduled, durationMinutes: duration, isAllDay: false,
                    amountYuan: nil, location: nil, participantHints: [])
            }
            let deadline = try service.payload(fields(end: "2026-11-20T17:00"), timeZone: .gmt)
            precondition(deadline.due_date == nil && deadline.end_datetime == "2026-11-20T17:00:00Z")
            precondition(deadline.task_type_hint == "flexible")
            let event = try service.payload(fields(start: "2026-11-20T15:00", duration: 120, scheduled: true), timeZone: .gmt)
            precondition(event.duration_minutes == 120 && event.task_type_hint == "scheduled")
            let undated = try service.payload(fields(explicitTime: false), timeZone: .gmt)
            precondition(undated.due_date == nil && undated.task_type_hint == "flexible")
            for value in [fields(end: "2026-02-30T17:00"), fields(scheduled: true, explicitTime: false),
                          fields(duration: 0), fields(duration: -1), fields(duration: 10081),
                          fields(start: "2026-11-20T15:00", end: "2026-11-20T14:00")] {
                do { _ = try service.payload(value, timeZone: .gmt); fatalError("Invalid extracted fields accepted") }
                catch AppleTaskRecognitionError.invalidDate {}
            }
            print("PASS: deadline-only flexible task, duration, missing event time, invalid dates/durations, end-before-start")
        }
        let canceled = Task { @MainActor in
            try await service.parseText("Dentist tomorrow at 3 pm", referenceDate: Date(), timeZone: .gmt, locale: locale)
        }
        canceled.cancel()
        do { _ = try await canceled.value; fatalError("Cancellation ignored") }
        catch is CancellationError {}
        if #available(iOS 26.0, *), case .unavailable = SystemLanguageModel.default.availability {
            do {
                _ = try await service.parseText("Dentist tomorrow at 3 pm", referenceDate: Date(), timeZone: .gmt, locale: locale)
                fatalError("Unavailable model was invoked")
            } catch AppleTaskRecognitionError.unavailable {}
            print("PASS: unavailable local model surfaces explicit choice error")
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let size = CGSize(width: 1000, height: 700)
        let fixture = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.black]
            ("OUTSIDE SECRET" as NSString).draw(at: CGPoint(x: 90, y: 30), withAttributes: attributes)
            ("DENTIST TOMORROW" as NSString).draw(at: CGPoint(x: 160, y: 350), withAttributes: attributes)
        }
        let full = NormalizedCropQuad(topLeft: .zero, topRight: CGPoint(x: 1, y: 0), bottomLeft: CGPoint(x: 0, y: 1), bottomRight: CGPoint(x: 1, y: 1))
        let bottom = NormalizedCropQuad(topLeft: CGPoint(x: 0.05, y: 0.40), topRight: CGPoint(x: 0.95, y: 0.40), bottomLeft: CGPoint(x: 0.05, y: 0.90), bottomRight: CGPoint(x: 0.95, y: 0.90))
        let crop = try AppleTaskRecognitionService.correctedImage(fixture, region: bottom)
        let text = try await AppleTaskRecognitionService.recognizeText(crop, locale: locale)
        precondition(text.contains("DENTIST"), text)
        precondition(!text.contains("OUTSIDE") && !text.contains("SECRET"), text)
        precondition(text.contains("[x=") && text.contains(",y="), "OCR must preserve bounding boxes")

        // Non-axis-aligned quadrilateral must retain the selected center content.
        let skew = NormalizedCropQuad(topLeft: CGPoint(x: 0.07, y: 0.38), topRight: CGPoint(x: 0.95, y: 0.42), bottomLeft: CGPoint(x: 0.03, y: 0.92), bottomRight: CGPoint(x: 0.97, y: 0.86))
        let skewText = try await AppleTaskRecognitionService.recognizeText(AppleTaskRecognitionService.correctedImage(fixture, region: skew), locale: locale)
        precondition(skewText.contains("DENTIST") && !skewText.contains("OUTSIDE"), skewText)

        // Raw pixels upside down, with EXIF .down: service must restore upright content.
        let raw = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: size.width, y: size.height)
            context.cgContext.rotate(by: .pi)
            fixture.draw(at: .zero)
        }
        let oriented = UIImage(cgImage: raw.cgImage!, scale: 1, orientation: .down)
        let orientedText = try await AppleTaskRecognitionService.recognizeText(AppleTaskRecognitionService.correctedImage(oriented, region: bottom), locale: locale)
        precondition(orientedText.contains("DENTIST") && !orientedText.contains("OUTSIDE"), orientedText)

        let rotatedSize = CGSize(width: size.height, height: size.width)
        let sidewaysRaw = UIGraphicsImageRenderer(size: rotatedSize, format: format).image { context in
            context.cgContext.translateBy(x: 0, y: size.width)
            context.cgContext.rotate(by: -.pi / 2)
            fixture.draw(at: .zero)
        }
        let sideways = UIImage(cgImage: sidewaysRaw.cgImage!, scale: 1, orientation: .right)
        let sidewaysText = try await AppleTaskRecognitionService.recognizeText(AppleTaskRecognitionService.correctedImage(sideways, region: bottom), locale: locale)
        precondition(sidewaysText.contains("DENTIST") && !sidewaysText.contains("OUTSIDE"), sidewaysText)

        let mirroredRaw = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: size.width, y: 0)
            context.cgContext.scaleBy(x: -1, y: 1)
            fixture.draw(at: .zero)
        }
        let mirrored = UIImage(cgImage: mirroredRaw.cgImage!, scale: 1, orientation: .upMirrored)
        let mirroredText = try await AppleTaskRecognitionService.recognizeText(AppleTaskRecognitionService.correctedImage(mirrored, region: bottom), locale: locale)
        precondition(mirroredText.contains("DENTIST") && !mirroredText.contains("OUTSIDE"), mirroredText)

        for invalid in [
            NormalizedCropQuad(topLeft: CGPoint(x: -.infinity, y: 0), topRight: full.topRight, bottomLeft: full.bottomLeft, bottomRight: full.bottomRight),
            NormalizedCropQuad(topLeft: full.topLeft, topRight: full.bottomRight, bottomLeft: full.bottomLeft, bottomRight: full.topRight),
            NormalizedCropQuad(topLeft: full.topLeft, topRight: full.topLeft, bottomLeft: full.topLeft, bottomRight: full.topLeft)
        ] {
            do { _ = try AppleTaskRecognitionService.correctedImage(fixture, region: invalid); fatalError("Invalid quad accepted") }
            catch AppleTaskRecognitionError.invalidCrop {}
        }
        let blank = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
        }
        do { _ = try await AppleTaskRecognitionService.recognizeText(blank.cgImage!, locale: locale); fatalError("Blank image accepted") }
        catch AppleTaskRecognitionError.noText {}
        print("PASS: input limits, region exclusion, OCR positions, perspective crop, EXIF rotation, mirrored EXIF, invalid quads, blank OCR")
    }
}

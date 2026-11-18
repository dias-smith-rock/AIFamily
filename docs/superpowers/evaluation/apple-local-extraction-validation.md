# Apple local task extraction validation

2026-11-19, Xcode 27.2 installed SDK, simulator arm64 with deployment target iOS 18.6.

Executable deterministic date checks (passed, seven assertions):

```sh
swiftc reminder/Services/TaskCreation/TaskRecognitionDateValidator.swift tests/TaskCreation/AppleRecognitionValidationTests.swift -o /tmp/apple-validation
/tmp/apple-validation
```

The harness rejects invalid calendar dates, daylight-saving gaps and repeated times, timed date-only strings, and unexpected UTC strings; accepts valid timed and all-day local dates. It does not invoke a model.

The service and TaskVoiceDraftSheet additionally passed `xcrun swiftc -typecheck -strict-concurrency=complete`, using `-target arm64-apple-ios18.6-simulator` and the installed iPhoneSimulator SDK. Temporary stubs supplied unrelated app dependencies (AppRouter, payload, crop quad, premium policy and voice capture UI). FoundationModels, Vision, CoreImage, UIKit and SwiftUI were the actual SDK modules. Supabase was absent from the isolated module, so its conditional cloud branch was not checked. This is an isolated SDK/API check, not a full app build.

Direct image inference checks iOS 27 and model vision/guided-generation capabilities; otherwise Vision's accurate OCR includes each observation's position before iOS 26 guided text inference. No service code uploads inputs or invokes cloud. Caller must explicitly offer cloud choice after errors.

Runtime recognition quality, model downloads, Apple Intelligence availability/locale behavior, real photographs, orientation/perspective quality and timing remain device acceptance checks. Date validation cannot guarantee model semantic accuracy. Apple official API reference checked alongside installed SDK:
https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting

## Executed image fixtures

The actual Vision/CoreImage/UIKit paths passed generated-image assertions on the booted iOS 27.2 simulator (2026-11-19). Fixtures verify selected-region text is retained while text outside the region is excluded; OCR positions are preserved; non-axis perspective crop retains intended text; EXIF upside-down, sideways and mirrored images normalize correctly; non-finite/crossing/collapsed quads reject; blank OCR rejects; empty and >6000-character text reject before model availability checks.

```sh
xcrun swiftc -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -target arm64-apple-ios18.6-simulator -strict-concurrency=complete reminder/Services/TaskCreation/TaskRecognitionDateValidator.swift reminder/Services/TaskCreation/AppleTaskRecognitionService.swift tests/TaskCreation/AppleRecognitionImageTests.swift -o /tmp/apple-image-tests
xcrun simctl spawn FAD7BA54-4901-4903-BEE5-C86DAE46617E /tmp/apple-image-tests
```

Replace the simulator identifier with an available booted arm64 iOS simulator. This standalone executable supplies only lightweight crop/DTO fixtures; inference, database and app UI are not invoked. Model route/locale availability and multimodal output accuracy still require Apple Intelligence device acceptance checks.

Both public parse methods now accept optional trailing `selectedCalendarDay: Date? = nil`. The value assists locating a photographed calendar cell; instructions explicitly forbid using it as the anchor for relative dates or inventing dates missing from source data. The reference instant remains independent.

The same image harness additionally passed cancellation-before-inference and unavailable-local-model routing checks on this simulator. A valid input with `SystemLanguageModel.default.availability == .unavailable` throws the explicit local-unavailable error; it does not invoke cloud. This check is conditional when executing on a model-capable runtime.

## Reviewer field-preservation checks

The same simulator harness additionally passed deterministic mapper assertions for deadline-only flexible tasks (end timestamp retained with no start), explicit 120-minute event duration, undated flexible tasks, invalid deadline dates, scheduled events missing their required start, zero/negative/over-seven-day duration, and end-before-start. Duration candidates are limited to 1–10080 minutes; values outside this range surface a clarification error. These checks execute the actual service payload mapper with typed extraction fixtures and do not claim model semantic accuracy.

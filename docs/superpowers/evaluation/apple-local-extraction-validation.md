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

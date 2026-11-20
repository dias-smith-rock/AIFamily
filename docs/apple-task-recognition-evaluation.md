# Apple task creation implementation status — 2026-11-19

User approved plan tasks 0–6. Siri task 7 is deferred. Branch `codex/apple-intelligence-task-plan`.

Implemented local-first photo/text parsing, iOS26 guided extraction, iOS27 image inference with OCR/perspective fallback, local speech recording UI and model downloads, optional-image shared draft, explicit cloud consent, authenticated cloud text parsing, existing form save integration, missing-time semantics, ambiguous-name protection, privacy-safe recognition logs and scoped cloud image fetching.

## Verification performed

- `tests/TaskCreation/run.sh`: passes seven date assertions, cloud snake_case payload regression, six participant checks. Participant tests stub unrelated roster merge types; they exercise actual matcher logic, not Supabase integration.
- `/tmp/task-deno/bin/deno test --allow-env --allow-net supabase/functions/tests/task-parsing_test.ts`: seven tests pass.
- Both Edge Function entrypoints pass Deno typecheck.
- Actual iOS27.2 SDK isolated component typechecks targeting iOS18.6 pass; details in `docs/superpowers/evaluation/apple-local-extraction-validation.md`. These use unrelated dependency stubs and do not replace an App build.
- Integration Swift files frontend syntax parse and git diff whitespace check pass.

## Still required before completion

Full Debug App + widget simulator build **passed** (`/tmp/aifamily-build-2.log`). Hosted XCTest against the real Calendly module **passed**, five tests, zero failures on iOS27.2 (`/tmp/aifamily-acceptance-final.log`) and iOS26.2 (`/tmp/aifamily-xctest-26-valid.log`). Dependency download required using the existing system HTTP proxy for the build command only; no global proxy configuration changed. Derived data: `/tmp/AIFamilyDerived`. Unsigned generic iOS Release App/widget build also **passed** (`/tmp/aifamily-release.log`); this verifies compilation/linking, not signing or device execution.

Generated-photo fixtures executed against actual Vision/CoreImage/UIKit in the iOS27.2 simulator: crop exclusion, perspective, rotated/mirrored EXIF, invalid coordinates and blank input pass. Mapper assertions cover deadline-only tasks, duration, invalid/missing scheduled time and canceled/unavailable recognition. Speech lifecycle/transcript tests exercise the production reducer, including cancellation/restart and late results.

No true-device microphone, model availability/download, image OCR quality, interruption/background, VoiceOver or end-to-end save verification has been completed. The proposed 30 photo/30 voice quality sample gates have not run. No recognition accuracy or latency figures are available.

Cloud functions have not been deployed. New text fallback requires deployment plus existing DeepSeek secrets as documented in `supabase/functions/README.md`; no production release/push is authorized. Until deployed, local recognition and manual task creation remain usable in principle, but new cloud text requests will fail.

Implementation rulings: kept existing `AIPrefilledTaskDraft` name and made paired attachments optional. Added both runnable standalone regression tests and a hosted `reminderTests` XCTest target (sources `reminderUnitTests`, separate from standalone @main harness). Online audio recognition deliberately unavailable; local failures allow edited text and explicit cloud text parsing, never audio upload.

## Remaining acceptance blockers

`xcrun devicectl list devices` shows only a connected physical iPhone 12, which cannot exercise Apple Intelligence. The Mac probe also returns `deviceNotEligible`; simulator inference returns unavailable. No substitute quality numbers are claimed. User was asked to connect an enabled iOS26+ Apple Intelligence iPhone for real model/microphone/end-to-end acceptance. The approved quality gate remains open.

Device Hub subsequently exposed the iPhone 17 Pro simulator running iOS 27.2. Guest-mode UI verification used the signed Debug build and a Debug membership override. The local screenshot report is under `docs/evidence/2026-11-19-iphone17pro/REPORT.md`. Camera capture reports unavailable, Speech fails to create an on-device recognizer after permissions are granted, and Apple Intelligence returns unavailable for the photo and typed speech flows.

Vision OCR remains available on that simulator. The photo failure panel opens the standard creation form with the selected region's recognized text in editable notes and the source photo as a removable attachment. The guest-mode walkthrough verified reading three lines from a synthetic notice, entering a title, removing the source photo, confirming save, reopening the notes with no attachment, and seeing the saved task after relaunch. This verifies OCR and the confirmation/save path. Structured model extraction and cloud response coverage remain open. Eight hosted XCTest cases pass on the same simulator, including a crop-exclusion case for the editable OCR path.

## Requirement audit

| Approved requirement | Current evidence | Status |
| --- | --- | --- |
| New branch, preserve user work | Feature branch, clean initial baseline, local commits only | Done |
| Apple-first photo extraction, 26 OCR/27 image branch | Compiled App, generated-image simulator fixtures and capability/error tests | Implemented; real model quality open |
| Local speech, 60s, cancellation, no silent audio upload | Compiled Speech APIs, production lifecycle/segment harness and hosted tests | Implemented; hardware capture open |
| Shared editable task preview and existing save path | Optional attachments, active form mic, source/member notes, field mapping and guarded routing; guest simulator saved OCR notes and reopened the task with no attachment | Implemented; structured AI draft-to-save acceptance open |
| Explicit cloud choice, text endpoint, context/auth/privacy | Seven Deno tests, endpoint typecheck, scoped image fetch and controlled errors | Implemented; test project deployment/integration open |
| iOS18.6 minimum, 26/27 capability protection | Actual target deployment settings; Debug/Release builds; tests on 26.2/27.2 | Compiled; no 18.6 runtime installed |
| 30 images/30 voice real model quality and latency gate | No eligible device/model; user asked to provide one | Not completed |
| Independent review and important fixes | Deadline/duration/field replacement, decoding, member hints, cancellation and real active mic fixed | Done |
| Siri follow-up | No Siri implementation added | Deferred as approved |

No production deploy, remote push, or merge has occurred. New cloud functions require an authorized test project; no project ref or CLI linkage was found. These remaining acceptance requirements prevent claiming the whole goal complete.

## Final member-matching regression

The 2026-11-19 follow-up audit reproduced a real failure: `Sally` was interpreted as an everyone hint because `all` was matched as a substring. A new standalone assertion failed before the fix (exit 133), then passed after replacing substring detection with complete normalized everyone phrases. The real App XCTest suite now passes **six tests, zero failures** (`/tmp/aifamily-xctest-members.log`). Full names and explicit `whole family` are separately covered.

Rechecked available hardware and project linkage after the fix: the sole connected physical iPhone remains iPhone 12, and no authorized staging Supabase project is linked. All local build/test processes have finished. Real Apple Intelligence quality, microphone/end-to-end UI acceptance and deployed cloud integration still require the requested device/test project; the overall goal remains unproven.

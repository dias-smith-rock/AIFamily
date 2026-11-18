# Apple task creation implementation status — 2026-11-19

User approved plan tasks 0–6. Siri task 7 is deferred. Branch `codex/apple-intelligence-task-plan`.

Implemented local-first photo/text parsing, iOS26 guided extraction, iOS27 image inference with OCR/perspective fallback, local speech recording UI and model downloads, optional-image shared draft, explicit cloud consent, authenticated cloud text parsing, existing form save integration, missing-time semantics, ambiguous-name protection, privacy-safe recognition logs and scoped cloud image fetching.

## Verification performed

- `tests/TaskCreation/run.sh`: passes seven date assertions, cloud snake_case payload regression, four participant checks. Participant tests stub unrelated roster merge types; they exercise actual matcher logic, not Supabase integration.
- `/tmp/task-deno/bin/deno test --allow-env --allow-net supabase/functions/tests/task-parsing_test.ts`: seven tests pass.
- Both Edge Function entrypoints pass Deno typecheck.
- Actual iOS27.2 SDK isolated component typechecks targeting iOS18.6 pass; details in `docs/superpowers/evaluation/apple-local-extraction-validation.md`. These use unrelated dependency stubs and do not replace an App build.
- Integration Swift files frontend syntax parse and git diff whitespace check pass.

## Still required before completion

Full App/widget build is running but blocked in Swift Package Manager fetch of RevenueCat `purchases-ios`. It has not compiled the App yet. Log `/tmp/aifamily-build.log`; derived data `/tmp/AIFamilyDerived`. Do not interpret isolated compilation as whole-App success.

No true-device microphone, model availability/download, image OCR quality, interruption/background, VoiceOver or end-to-end save verification has been completed. The proposed 30 photo/30 voice quality sample gates have not run. No recognition accuracy or latency figures are available.

Cloud functions have not been deployed. New text fallback requires deployment plus existing DeepSeek secrets as documented in `supabase/functions/README.md`; no production release/push is authorized. Until deployed, local recognition and manual task creation remain usable in principle, but new cloud text requests will fail.

Implementation rulings: kept existing `AIPrefilledTaskDraft` name and made paired attachments optional; used runnable standalone Swift tests rather than editing the App test target during SPM dependency blockage. Online audio recognition deliberately unavailable; local failures allow edited text and explicit cloud text parsing, never audio upload.

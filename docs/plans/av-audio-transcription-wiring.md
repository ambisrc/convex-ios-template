# AV Audio Transcription Wiring Plan

Status: Planned
Date: 2026-06-03
Linear: None selected

> **For agentic workers:** Use `.agents/skills/execute-work` for Delivery Map execution. Use `.agents/skills/tdd` for the Swift service seam and model behavior. Use `.agents/skills/ios-voice-template` before Swift capture or simulator verification work. Use `.agents/skills/convex-voice-agent` only if the backend transcription action or payload contract changes.

## Finding

The template had a backend transcription action and Swift handoff flow, but it was not fully wired to real AV audio capture. `TemplateVoiceCaptureService.captureAudio` still threw a configuration error whenever microphone permission was granted.

Already present before this slice:

- `VoiceAgentTemplateModel.startVoiceCommand` asks a `TemplateVoiceCapturing` service for `TemplateVoiceAudio`, sends `audioBase64` and `mimeType` to `commandService.transcribeVoice`, then submits the returned transcript as a voice command.
- `TemplateBackendClient.transcribeVoice` targets `commands:transcribeVoiceCommand`.
- `convex/commands.ts:transcribeVoiceCommand` authenticates the user and calls `convex/lib/voiceTranscription.ts`.
- `convex/lib/voiceTranscription.ts` enforces a raw audio cap, builds multipart form data, and calls Groq Whisper when `GROQ_API_KEY` is configured.

Missing before this slice:

- AVAudioRecorder-backed local capture.
- Runtime AVAudioSession microphone permission request/mapping.
- Temp-file cleanup and client-side raw audio size enforcement before base64 encoding.
- Live transcription credentials and auth/session configuration.

## Goal

Wire the existing Swift voice-capture seam to real AVFoundation audio so tapping the voice control records a short command, sends the recorded audio to `commands:transcribeVoiceCommand`, and submits the transcript through the existing voice command flow.

## Non-Goals

- Do not change the public Convex transcription contract unless AV payload size or MIME behavior proves incompatible.
- Do not store raw voice audio durably.
- Do not add streaming transcription, background recording, waveform rendering, retries, or long-form recording in this slice.
- Do not wire unrelated live services beyond what is needed for the voice path.

## Ship Now

- AVFoundation-backed `TemplateVoiceCaptureService`.
- A small permission adapter that maps AV record permission to `TemplateMicrophonePermission`.
- Focused tests for capture service behavior through injectable recorder/file/session seams.
- Model tests that continue proving capture precedes transcription and voice command submission.
- Build/test evidence, with live Groq transcription documented as blocked unless credentials are available.

## Defer

- Upload URLs or chunked binary transfer. Keep base64 action payloads while recordings stay below `MAX_VOICE_AUDIO_BYTES`.
- Rich recording UI state such as elapsed time, cancel, pause, or waveform.
- Provider/model changes on the Convex side.

## Acceptance Criteria

1. With microphone permission granted, `TemplateVoiceCaptureService.captureAudio` records a bounded short clip and returns non-empty base64 audio with `audio/m4a`.
2. With permission denied, restricted, or unavailable, the model falls back to typed input with the existing fallback reasons.
3. `VoiceAgentTemplateModel.startVoiceCommand` continues to call transcription before `submitCommand(source: .voice)`.
4. Recorded raw audio stays below the backend `MAX_VOICE_AUDIO_BYTES` cap, with enough base64 expansion margin for Convex action limits.
5. No raw audio files remain durably after a successful or failed capture attempt.
6. Local tests pass without live Groq or Apple credentials.
7. Live simulator transcription is either verified against a configured Convex deployment with `GROQ_API_KEY`, or explicitly recorded as blocked by missing credentials.

## Relevant Learnings Applied

- `.agents/learnings/convex-action-payload-limits.md`: base64 audio expands by roughly 4/3, so clip duration/quality must keep encoded action values comfortably below Convex limits.
- `.agents/learnings/ios-simulator-verification.md`: use explicit simulator destinations such as `platform=iOS Simulator,OS=18.5,name=iPhone 16`.
- `convex/_generated/ai/guidelines.md`: backend function validators and auth ownership are already aligned; reread before changing Convex code.

## Implementation Notes

- Use an injectable capture shell around AVFoundation so unit tests can exercise permission, recorder failure, file cleanup, and base64 encoding without real microphone access.
- Use a temporary file under the app temporary directory, then remove it in `defer`.
- Keep recording duration intentionally short: 3 seconds for this starter.
- Use AAC in an MPEG-4 container. The backend filename extension helper treats unknown/non-wav/non-mp3 MIME types as m4a.
- If capture duration/quality risks the Convex action value cap, reduce quality or duration before changing the backend transport.

## Verification Commands

Swift:

```sh
xcodebuild build -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
```

Backend, only if Convex transcription code changes:

```sh
npx vitest run convex/voiceTranscription.test.ts
npx tsc -p convex/tsconfig.json
```

Manual live check, only when credentials are available:

```sh
npx convex dev
xcodebuild build -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
```

Then run the app against a configured deployment and confirm a short voice recording becomes a saved voice entry. Do not commit local deployment URLs, `GROQ_API_KEY`, Apple private keys, or filled local env files.

## Delivery Map

### Node AV-1: Capture Seam Tests

- `id`: AV-1
- `mode`: tdd
- `status`: completed
- `owner_type`: agent
- `executor`: unassigned
- `planned_write_scope`: `ios/Core/TemplateServices.swift`, `ios/Tests/*Voice*`
- `depends_on`: none
- `unblocks`: AV-2
- `required_gates`: XCTest proving granted permission produces encoded audio through a fake recorder/file seam; denied/restricted/unavailable keep existing fallback behavior
- `actual_changed_paths`: `ios/Tests/TemplateVoiceCaptureServiceTests.swift`, `ios/Tests/TemplateVoiceCaptureStateTests.swift`, `ios/Tests/VoiceAgentTemplateModelTests.swift`
- `actual_evidence`: covered by local iOS test run
- `next`: completed

### Node AV-2: AVFoundation Implementation

- `id`: AV-2
- `mode`: execute-work
- `status`: completed
- `owner_type`: agent
- `executor`: unassigned
- `planned_write_scope`: `ios/Core/TemplateServices.swift`, supporting Swift files if the service split is cleaner
- `depends_on`: AV-1
- `unblocks`: AV-3
- `required_gates`: XCTest passes; temp audio cleanup is covered; encoded audio size is bounded
- `actual_changed_paths`: `ios/Core/TemplateVoiceCaptureEngine.swift`, `ios/Core/TemplateMicrophonePermissionService.swift`, `ios/Core/TemplateServices.swift`, `ios/App/VoiceAgentTemplateModel.swift`
- `actual_evidence`: covered by local iOS test run
- `next`: completed

### Node AV-3: Verification And Live Evidence

- `id`: AV-3
- `mode`: execute-work
- `status`: completed
- `owner_type`: agent
- `executor`: unassigned
- `planned_write_scope`: `.context/` evidence notes only unless a test/simulator blocker requires a code fix
- `depends_on`: AV-2
- `unblocks`: ship-work
- `required_gates`: `xcodebuild build`; `xcodebuild test`; manual live transcription attempted or marked blocked with exact missing credential/configuration
- `actual_evidence`: build and test passed in implementation handoff; live transcription blocked by missing Convex deployment URL, Apple session, simulator microphone approval, and `GROQ_API_KEY`
- `next`: use `.agents/skills/ship-work`

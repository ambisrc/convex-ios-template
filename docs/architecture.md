# Architecture

Status: Template

The starter has two runtime halves:

- SwiftUI iOS app under `ios/`
- Convex backend under `convex/`

Swift owns input and display. Convex owns trusted command interpretation,
validation, model-provider calls, user ownership, and writes.

## Command Boundary

All assistant-driven writes enter through `convex/commands.ts:submitCommand`.
The action trims user input, derives ownership, calls the replaceable command
interpreter, then hands typed operations to the server apply layer.

Stable contract:

- public action name: `commands:submitCommand`
- request: `{ text: string, source: "typed" | "voice" }`
- success response: `{ status: "applied", summary, operations, entries }`
- write handoff: `internal.lib.apply.applyCommand`

Clone-owned replacement points:

- `convex/lib/commandInterpreter.ts`: app-specific parsing and summary rules.
- `convex/lib/operations.ts`: app-specific typed operation union.
- `convex/lib/apply.ts`: transactional domain apply facade for the clone's
  domain tables. Keep this as the one registered write handoff from public
  actions; add plain helpers before splitting into submodules.
- `convex/entries.ts`: sample-domain read model, expected to become the clone's
  query surface.

The starter interpreter only supports `create_entry`. A real clone should
replace that module rather than growing app-specific parsing inside
`convex/commands.ts`.

## Swift/Convex Contract

Both backend and iOS tests consume
`tests/fixtures/public-actions.json`. The fixture is the audit point for
public action names, request bodies, success responses, voice configuration
unions, account deletion, the starter `entries:listEntries` read seam, and the
starter `entries:updateEntry` mutation seam.

Stable contract:

- `commands:submitCommand`
- `commands:transcribeVoiceCommand`
- `commands:deleteAccount`
- `entries:listEntries`
- `entries:updateEntry`
- Swift mirrors in `ios/Core/TemplateBackendContract.swift`,
  `ios/Core/TemplateBackendClient.swift`, and
  `ios/Core/TemplateConvexCommandRequest.swift`

Clone-owned replacement points:

- action/query names if the clone reorganizes Convex modules;
- request and response mirrors in `TemplateBackendContract.swift` when the
  operation union changes;
- live Convex Swift client wiring through `TemplateConvexCalling` and
  `TemplateBackendClient`.

## Ownership

Convex functions derive ownership from `ctx.auth.getUserIdentity()` and use
`identity.tokenIdentifier` as the owner key. Clients must not pass user IDs for
authorization.

Stable contract:

- `convex/lib/auth.ts` derives owner keys from Convex auth.
- Public actions and queries call `requireOwnerKey`.

Clone-owned replacement points:

- auth provider configuration in `convex/auth.config.ts`;
- app-specific profile fields in `convex/schema.ts`;
- signed-in Swift session flow in `ios/Core/TemplateServices.swift`.

## Voice

Swift captures short voice-command audio and sends base64 audio to
`commands:transcribeVoiceCommand`. Convex enforces payload limits before
calling the transcription provider. Raw audio is not stored durably.

Stable contract:

- request: `{ audioBase64: string, mimeType: string }`
- success: `{ status: "transcribed", transcript: string }`
- missing config: `{ status: "configuration_missing", missing: "GROQ_API_KEY" }`
- raw payload cap in `convex/lib/voiceTranscription.ts`

Clone-owned replacement points:

- transcription provider and model choice;
- voice capture implementation behind `TemplateVoiceCapturing`;
- user-facing handling of missing or denied voice capability.

## Vendor Boundaries

Sentry and PostHog helpers use fetch-based or isolated action seams and skip
safely when configuration is absent. Analytics payloads must not include
transcripts, entry content, raw audio, Apple refresh tokens, or live secrets.

Stable contract:

- public Convex action modules avoid Node-only vendor SDK imports;
- event payloads exclude user-authored content;
- missing vendor config returns skip states for cleanup paths.

Clone-owned replacement points:

- Sentry project, DSN, and upload token;
- PostHog project and cleanup token;
- clone-specific analytics event names that preserve the privacy boundary.

## Account Deletion

Stable contract:

- `commands:deleteAccount` is the public action.
- `convex/account.ts` owns bounded account-lifecycle writes and
  `accountDeletionJobs` continuation state.
- Small and medium accounts can finish synchronously with
  `status: "deleted"`.
- Large accounts return `status: "deletion_in_progress"` with aggregate
  deleted counts and `jobStatus`, then continue through scheduled mutations
  until cleanup runs.
- PostHog cleanup can request person deletion when configured.
- Sentry cleanup records a best-effort operator report and does not claim user
  deletion.
- Vendor cleanup failures are recorded in the final cleanup result so account
  deletion does not remain stuck after owned app data is removed.

Clone-owned replacement points:

- additional domain tables in the account deletion batch;
- vendor cleanup policies and retention docs;
- Settings copy and account UI.

When a clone adds a new owner-owned Convex table, update the account deletion
surface in one change:

- add the table deletion query to `convex/account.ts`;
- add its count key to `accountDeletionOwnedTableNames` and a matching
  `v.number()` entry to `deleteCountValidators` in
  `convex/lib/accountDeletionContract.ts`;
- update `tests/fixtures/public-actions.json` delete-account responses;
- update `TemplateDeleteAccountResult.DeletedCounts` in
  `ios/Core/TemplateBackendContract.swift`;
- update backend and Swift fixture tests.

The fixture sync test in `convex/account.test.ts` intentionally fails when the
delete-count contract and public fixture drift. The Swift fixture decode tests
then catch a missing iOS mirror.

## iOS Service Adapters

Stable contract:

- `TemplateSessionServicing` owns sign-in/session acquisition.
- `TemplateCommandServicing` owns submit, voice transcription, starter
  `listEntries`, and account deletion calls.
- `TemplateBackendClient` routes public endpoints through an injected
  `TemplateConvexCalling` seam when live wiring is present.
- `PlaceholderTemplateBackendClient` fails with explicit configuration messages
  until the clone wires real SDK clients.
- `TemplateVoiceCapturing` owns local audio capture.

Clone-owned replacement points:

- Apple auth implementation;
- Convex Swift client action/query calls behind `TemplateConvexCalling`;
- AVAudioRecorder or alternate capture implementation;
- app-specific state projection in `VoiceAgentTemplateModel`.

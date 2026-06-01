# AMB-225 Review Fixes

Status: Implementation Complete (awaiting PR review)
Linear issue: AMB-225
Created: 2026-05-31
Source: review findings on the account deletion consolidation workspace

## Goal

Address the three review findings from the account deletion consolidation:

- in-progress account deletion must not leave the signed-in capture surface
  writable;
- vendor cleanup ordering must remain PostHog first, then Sentry;
- account deletion job status validation must be shared between the contract
  module and schema.

Keep the existing public `commands:deleteAccount` response contract unchanged.

## Non-Goals

- Do not redesign account deletion into a generalized job framework.
- Do not add Apple token revocation or new vendor cleanup policies.
- Do not change public action names, request shapes, or response status values.
- Do not introduce live vendor credentials or deployment-specific values.

## Ship Now

- Treat `.deletionInProgress` from the Swift account deletion call as a
  non-writable local state. The simplest acceptable behavior is to clear the
  local session the same way `.deleted` does, while preserving or surfacing an
  appropriate user-facing message if product copy requires it.
- Add or update a Swift model test proving that after
  `.deletionInProgress`, the model no longer exposes a signed-in writable
  capture state.
- Restore sequential vendor cleanup in `convex/account.ts`.
- Add a focused backend test that proves PostHog cleanup is attempted before
  Sentry cleanup.
- Add a shared `accountDeletionJobStatusValidator` covering
  `deleting`, `cleanup_pending`, `cleanup_running`, and `deleted`; use it in
  `convex/schema.ts`.
- Keep the active-status response validator/type separate or derived from the
  full status validator in a way that still prevents `deleted` from appearing
  in `deletion_in_progress.jobStatus`.

## Defer

- UI-specific pending-deletion screens or disabled capture controls beyond the
  minimum non-writable state.
- Backend enforcement that blocks `commands:submitCommand` when an account
  deletion job exists. This can be added later if the product needs signed-in
  pending-deletion UX, but the immediate review fix can remove the local write
  surface.
- Documentation changes unless implementation changes the stable architecture
  text or deployment operator steps.

## Acceptance Criteria

- Calling `VoiceAgentTemplateModel.deleteAccount()` with a
  `.deletionInProgress` backend result leaves `isSignedIn == false`, clears
  entries and command text, and clears the Sentry owner scope.
- The Swift test suite has explicit coverage for the in-progress deletion local
  state.
- `runAccountDeletionVendorCleanup` awaits the PostHog cleanup result before
  starting Sentry cleanup.
- A Convex test would fail if Sentry cleanup starts before PostHog cleanup
  resolves.
- `convex/schema.ts` imports and uses a shared full account deletion job status
  validator instead of hand-writing the status union.
- `commands:deleteAccount` still returns only `deleted` or
  `deletion_in_progress` shapes matching `tests/fixtures/public-actions.json`.

## Verification

Run focused checks first:

```sh
npx vitest run convex/account.test.ts
xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16' -only-testing:VoiceAgentTemplateTests/VoiceAgentTemplateModelTests
```

Then run broader gates:

```sh
npx vitest run convex
npx tsc -p convex/tsconfig.json
npx convex codegen
xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
```

If `xcodebuild test` is blocked by local CoreSimulator state, record the exact
error and preserve any successful build or focused test evidence separately.
If `npx convex codegen` requires deployment setup or deployment env vars,
record the exact missing prerequisite rather than fabricating generated output.

## Skill Choice

- Use `.agents/skills/tdd` for each behavior slice.
- Use `.agents/skills/convex-voice-agent` before Convex account deletion and
  vendor cleanup edits.
- Use `.agents/skills/ios-voice-template` before Swift model or settings UI
  edits.
- Use `.agents/skills/execute-work` to execute the Delivery Map nodes.

## Learnings Applied

- `.agents/learnings/convex-action-vendor-reporting.md`: keep vendor calls in
  isolated fetch-based helpers/actions and do not add private user content to
  analytics or reporting payloads.
- `.agents/learnings/deployment-secrets.md`: do not introduce live Sentry,
  PostHog, Apple, Groq, or Convex deployment secrets while testing cleanup
  behavior.
- `.agents/learnings/ios-simulator-verification.md`: run iOS checks with an
  explicit simulator OS and record CoreSimulator blockers precisely.

## Documentation Impact

No documentation update is required if the implementation only restores the
intended behavior. Update `docs/architecture.md` only if the executor adds a
new backend guard that rejects command writes while deletion is active.

## Safe Concurrency

Keep these fixes in one worker unless explicitly split:

- Swift session-state fix and Swift model test touch
  `ios/App/VoiceAgentTemplateModel.swift` and
  `ios/Tests/VoiceAgentTemplateModelTests.swift`.
- Convex cleanup ordering and status-validator fixes touch
  `convex/account.ts`, `convex/account.test.ts`,
  `convex/lib/accountDeletionContract.ts`, and `convex/schema.ts`.

These files overlap with the current AMB-225 refactor, so avoid parallel agents
editing the same files without a fresh coordination point.

## Delivery Map

### Node A - lock local account state on in-progress deletion

- id: `A-ios-in-progress-lock`
- mode: `tdd`
- status: `done`
- owner_type: `agent`
- executor: `execute-work`
- planned_write_scope:
  - `ios/App/VoiceAgentTemplateModel.swift`
  - `ios/Tests/VoiceAgentTemplateModelTests.swift`
- depends_on: `[]`
- unblocks: `[D-final-gates]`
- required_gates:
  - command: `xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16' -only-testing:VoiceAgentTemplateTests/VoiceAgentTemplateModelTests`
  - status: `passed`
  - evidence: `9/9 VoiceAgentTemplateModelTests passed (2026-05-31); includes testDeleteAccountClearsWritableLocalStateWhenDeletionIsInProgress.`
  - attempts: `2`
- human_gates: `[]`
- notes: `Start with the existing deletion-in-progress model test, flip it to the desired non-writable state, then implement.`
- todos:
  - `Update the test to expect signed-out/cleared local state after deletion_in_progress.`
  - `Reuse clearLocalSession or an equivalent non-writable local state transition.`
  - `Decide whether preserving feedbackMessage is necessary after sign-out; keep copy aligned with BRAND.md if visible.`
- issues_found: `[]`
- actual_changed_paths:
  - `ios/App/VoiceAgentTemplateModel.swift`
  - `ios/Tests/VoiceAgentTemplateModelTests.swift`
- actual_evidence:
  - `testDeleteAccountClearsWritableLocalStateWhenDeletionIsInProgress` expects signed-out/cleared state; implementation calls `clearLocalSession()` then sets in-progress feedback copy.
- next: `B-vendor-order`

### Node B - restore vendor cleanup ordering

- id: `B-vendor-order`
- mode: `tdd`
- status: `done`
- owner_type: `agent`
- executor: `execute-work`
- planned_write_scope:
  - `convex/account.ts`
  - `convex/account.test.ts`
- depends_on: `[]`
- unblocks: `[D-final-gates]`
- required_gates:
  - command: `npx vitest run convex/account.test.ts`
  - status: `passed`
  - evidence: `10 tests passed (521ms); new test awaits PostHog cleanup before starting Sentry cleanup.`
  - attempts: `1`
- human_gates: `[]`
- notes: `Prove Sentry cleanup waits until the PostHog cleanup promise resolves, then replace Promise.all with sequential awaits.`
- todos:
  - `Add a fetch-order test using deferred PostHog and Sentry responses.`
  - `Change runAccountDeletionVendorCleanup to await PostHog before Sentry.`
  - `Confirm cleanup failure handling remains per-vendor and finalizes deletion.`
- issues_found: `[]`
- actual_changed_paths:
  - `convex/account.ts`
  - `convex/account.test.ts`
- actual_evidence:
  - `npx vitest run convex/account.test.ts` — 10/10 passed.
- next: `C-status-validator`

### Node C - share full job status validator

- id: `C-status-validator`
- mode: `tdd`
- status: `done`
- owner_type: `agent`
- executor: `execute-work`
- planned_write_scope:
  - `convex/lib/accountDeletionContract.ts`
  - `convex/schema.ts`
  - `convex/account.ts`
  - `convex/account.test.ts`
- depends_on: `[]`
- unblocks: `[D-final-gates]`
- required_gates:
  - command: `npx tsc -p convex/tsconfig.json`
  - status: `passed`
  - evidence: `exit 0`
  - attempts: `1`
  - command: `npx vitest run convex/account.test.ts`
  - status: `passed`
  - evidence: `10/10 passed`
  - attempts: `1`
- human_gates: `[]`
- notes: `The schema needs the full status union including deleted; deletion_in_progress responses still need only active statuses.`
- todos:
  - `Add accountDeletionJobStatusValidator with all persisted statuses.`
  - `Use the shared full status validator in schema.ts.`
  - `Keep ActiveDeletionJobStatus excluding deleted for response typing.`
- issues_found: `[]`
- actual_changed_paths:
  - `convex/lib/accountDeletionContract.ts`
  - `convex/schema.ts`
- actual_evidence:
  - `accountDeletionJobStatusValidator` includes deleting, cleanup_pending, cleanup_running, deleted; schema uses it; `activeDeletionJobStatusValidator` unchanged for responses.
- next: `D-final-gates`

### Node D - final verification

- id: `D-final-gates`
- mode: `verification`
- status: `done`
- owner_type: `agent`
- executor: `execute-work`
- planned_write_scope:
  - `convex/_generated/` if `npx convex codegen` changes generated files
  - `docs/architecture.md` only if backend write-blocking behavior is added
- depends_on: `[A-ios-in-progress-lock, B-vendor-order, C-status-validator]`
- unblocks: `[ship-work]`
- required_gates:
  - command: `npx vitest run convex`
  - status: `passed`
  - evidence: `4 files, 19 tests passed (813ms). Scheduler stderr on continueAccountDeletion (pre-existing harness noise).`
  - attempts: `1`
  - command: `npx tsc -p convex/tsconfig.json`
  - status: `passed`
  - evidence: `exit 0`
  - attempts: `1`
  - command: `npx convex codegen`
  - status: `blocked`
  - evidence: `Linked deployment brilliant-minnow-935 is missing APPLE_SIGN_IN_CLIENT_IDS; codegen stopped before upload completed.`
  - attempts: `2`
  - command: `xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'`
  - status: `passed`
  - evidence: `30/30 VoiceAgentTemplateTests passed (2026-05-31).`
  - attempts: `2`
- human_gates:
  - `Convex deployment env var APPLE_SIGN_IN_CLIENT_IDS is needed for codegen in the linked deployment.`
  - `CoreSimulator health may block iOS test execution.`
- notes: `Do not claim final readiness from focused gates alone. Record any scheduler stderr warning separately if tests pass but emit harness noise.`
- todos:
  - `Run full backend and Swift gates.`
  - `Check git diff for unchanged public fixture contract unless intentionally changed.`
  - `Update Delivery Map actual evidence before handoff.`
- issues_found:
  - `APPLE_SIGN_IN_CLIENT_IDS unset in linked Convex deployment — codegen blocked (non-blocking for review-fix acceptance).`
- actual_changed_paths:
  - `ios/App/VoiceAgentTemplateModel.swift`
  - `ios/Tests/VoiceAgentTemplateModelTests.swift`
  - `convex/account.ts`
  - `convex/account.test.ts`
  - `convex/lib/accountDeletionContract.ts`
  - `convex/schema.ts`
- actual_evidence:
  - `npx vitest run convex` — 19/19 passed (2026-05-31).
  - `npx tsc -p convex/tsconfig.json` — exit 0.
  - `xcodebuild test` (focused + full) — 30/30 passed.
  - `npx convex codegen` — blocked because linked Convex deployment is missing `APPLE_SIGN_IN_CLIENT_IDS`.
  - Public-actions fixture unchanged; ready for ship-work.
- next: `ship-work`

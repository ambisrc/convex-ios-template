# Resumable Account Deletion

Status: Implemented (pending ship-work)
Linear issue: Not configured for this template workspace
Created: 2026-05-31

## Goal

Make `commands:deleteAccount` safe for accounts with more owned rows than fit in
the current synchronous action loop. Account deletion must not throw after
committing partial database deletes, and vendor cleanup must run after all
app-owned Convex rows are deleted.

## Non-Goals

- Do not add account recovery, undo, admin dashboards, or broad audit tooling.
- Do not change ownership semantics; user ownership still comes from Convex auth
  via `convex/lib/auth.ts`.
- Do not import Node-only Sentry or PostHog SDKs into public action modules.
- Do not attempt to delete or scrub Sentry user records beyond the existing
  best-effort operator report.

## Ship Now

- Replace the hard `MAX_DELETE_ACCOUNT_BATCHES` failure path with a resumable,
  server-owned deletion job.
- Keep the current `status: "deleted"` response for accounts that finish during
  the initial request.
- Add an explicit in-progress response for larger accounts, and update Swift and
  fixture mirrors for that response shape.
- Schedule continuation work with `ctx.scheduler.runAfter(0, ...)` until no
  owned rows remain.
- Run PostHog and Sentry cleanup once, after Convex data deletion completes.
- Make repeated `deleteAccount` calls idempotently resume or report the current
  deletion state.

## Defer

- User-visible progress percentages.
- Retention policy customization per clone.
- External vendor deletion polling or verification.
- A generalized background job framework beyond this account deletion job.

## Acceptance Criteria

- A user with more than 1,000 rows in any owned table can call
  `commands:deleteAccount` without receiving `DELETE_ACCOUNT_BATCH_LIMIT_EXCEEDED`.
- The first call for a small account still returns the existing
  `status: "deleted"` shape used by `tests/fixtures/public-actions.json`.
- The first call for a large account returns a typed in-progress state, such as
  `status: "deletion_in_progress"`, with bounded count/status fields and no
  private user-authored content.
- Scheduled continuations delete all owned rows from `profiles`, `entries`,
  `commandHistory`, `appleSignInCredentials`, and `usageEvents`.
- PostHog cleanup is requested exactly once when configured, after all owned
  Convex rows are gone.
- Sentry cleanup is reported exactly once when configured, after all owned
  Convex rows are gone.
- Repeated calls while a deletion is in progress do not create duplicate jobs,
  duplicate vendor cleanup requests, or resurrect deleted state.
- Repeated calls after completion return a stable completed response.
- Tests prove partial committed batches are not followed by an uncaught action
  throw.

## Implementation Notes

- Read `convex/_generated/ai/guidelines.md` before editing Convex code. It
  explicitly recommends batching large deletes and scheduling continuation with
  `ctx.scheduler.runAfter(0, ...)`.
- Keep `commands:deleteAccount` as the public action boundary.
- Keep account lifecycle writes in `convex/account.ts`.
- Add one schema table, tentatively `accountDeletionJobs`, indexed by
  `ownerKey`, to persist deletion status, deleted counts, cleanup status, and
  timestamps.
- Model job status as a validator-backed union. Suggested statuses:
  `deleting`, `cleanup_pending`, `cleanup_running`, `deleted`, `failed`.
- Keep vendor cleanup actions in `convex/posthog.ts` and `convex/sentry.ts`.
  Add an internal action only if orchestration needs to call vendor cleanup and
  then record completion.
- Avoid storing transcripts, entry bodies, raw audio, Apple refresh tokens, or
  other user-authored content in the deletion job.

## Proposed Flow

1. `commands:deleteAccount` derives `ownerKey` with `requireOwnerKey`.
2. The action calls an internal mutation in `convex/account.ts` to create or
   load the deletion job and delete one bounded batch.
3. If the first batch drains all owned rows, the public action runs the existing
   PostHog and Sentry cleanup actions inline, finalizes the job through an
   internal mutation, and returns the current `status: "deleted"` response.
4. If more owned rows remain, the mutation schedules a continuation internal
   mutation with `ctx.scheduler.runAfter(0, ...)` and returns an in-progress
   result to the action.
5. The continuation mutation deletes one bounded batch per invocation. It
   reschedules itself while rows remain.
6. When a continuation finds no owned rows remain, it marks cleanup pending and
   schedules an internal cleanup action.
7. The cleanup action calls the existing PostHog and Sentry internal actions,
   then records cleanup completion through an internal mutation.
8. `commands:deleteAccount` maps the job state to the public response union.

## TDD Plan

Use `.agents/skills/tdd` and work through public behavior first.

1. Add a failing Convex test for a large account with enough entries,
   command history, and usage events to exceed the old 20-batch action cap.
   Assert the public action returns in-progress instead of throwing.
2. Add a failing test proving scheduled continuation drains all owned tables.
   Use `convex-test` scheduler helpers if available; otherwise isolate the
   internal continuation function through a public-callable behavior test.
3. Add a failing test proving vendor cleanup is not called until all owned rows
   are gone.
4. Add a failing test proving repeated calls during deletion are idempotent.
5. Preserve the existing small-account tests and fixture-backed contract tests.
6. Implement the smallest schema/action/mutation changes needed to make each
   test pass before adding the next test.

## Verification

Required local commands:

```sh
npx vitest run convex
npx tsc -p convex/tsconfig.json
```

Contract checks:

- Update `tests/fixtures/public-actions.json` only if the public response union
  changes.
- Update Swift mirrors in `ios/Core/TemplateBackendContract.swift` and related
  request/response decoding code if the public response union changes.
- Run Swift tests if Swift response mirrors change:

```sh
xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
```

Manual/live checks:

- No live PostHog or Sentry credentials are required for local tests.
- If checking a deployed cleanup path, use fake or test project credentials and
  record the Convex env vars required. Do not commit live values.

## Documentation Impact

- Update `docs/architecture.md` Account Deletion if the response status union or
  background job semantics change.
- Update `docs/deployment.md` Account Cleanup to explain scheduled deletion and
  eventual vendor cleanup.
- Add a learning only if implementation exposes a reusable Convex scheduler or
  vendor cleanup caveat not already captured in `.agents/learnings/`.

## Safe Concurrency

- Backend deletion worker can own `convex/account.ts`, `convex/commands.ts`,
  `convex/schema.ts`, `convex/account.test.ts`, and
  `tests/fixtures/public-actions.json`.
- Swift contract worker can proceed only after the backend response union is
  decided. Its likely scope is `ios/Core/` and `ios/Tests/`.
- Documentation worker can update docs after the backend design stabilizes.
- Do not split `convex/account.ts` and `convex/schema.ts` across parallel
  workers because the job schema and mutation behavior are tightly coupled.

## Delivery Map

### Node A

- id: `A-repro-contract`
- mode: `tdd`
- status: `done`
- owner_type: `agent`
- executor: `execute-work`
- planned_write_scope:
  - `convex/account.test.ts`
- depends_on: `[]`
- unblocks: `[B-resumable-backend]`
- required_gates:
  - command: `npx vitest run convex/account.test.ts`
  - status: `passed`
  - evidence: `Large-account test expects deletion_in_progress with 20 sync batches`
  - attempts: `1`
- human_gates: `[]`
- notes: `Start with public action behavior through api.commands.deleteAccount.`
- todos:
  - `Create data volume that exceeds the old 20 batch cap.`
  - `Assert no DELETE_ACCOUNT_BATCH_LIMIT_EXCEEDED escapes.`
- issues_found: `[]`
- actual_changed_paths:
  - `convex/account.test.ts`
- actual_evidence:
  - `npx vitest run convex/account.test.ts` — 8 passed
- next: `B-resumable-backend`

### Node B

- id: `B-resumable-backend`
- mode: `tdd`
- status: `done`
- owner_type: `agent`
- executor: `execute-work`
- planned_write_scope:
  - `convex/schema.ts`
  - `convex/account.ts`
  - `convex/commands.ts`
  - `convex/account.test.ts`
- depends_on: `[A-repro-contract]`
- unblocks: `[C-vendor-cleanup, D-contract-mirrors, E-docs]`
- required_gates:
  - command: `npx vitest run convex/account.test.ts`
  - status: `passed`
  - evidence: `105-row account still returns deleted; large account returns in_progress`
  - attempts: `1`
  - command: `npx tsc -p convex/tsconfig.json`
  - status: `passed`
  - evidence: `Convex TS clean after @types/node devDependency`
  - attempts: `1`
- human_gates: `[]`
- notes: `Use ctx.scheduler.runAfter(0, ...) from a mutation for continuation.`
- todos:
  - `Add accountDeletionJobs schema with ownerKey index.`
  - `Persist aggregate deleted counts and cleanup status.`
  - `Make deleteAccount idempotent for active and completed jobs.`
- issues_found: `[]`
- actual_changed_paths:
  - `convex/schema.ts`
  - `convex/account.ts`
  - `convex/commands.ts`
  - `convex/account.test.ts`
  - `package.json`
  - `package-lock.json`
- actual_evidence:
  - `npx vitest run convex/account.test.ts` — 8 passed
  - `npx tsc -p convex/tsconfig.json` — exit 0
- next: `C-vendor-cleanup`

### Node C

- id: `C-vendor-cleanup`
- mode: `tdd`
- status: `done`
- owner_type: `agent`
- executor: `execute-work`
- planned_write_scope:
  - `convex/account.ts`
  - `convex/posthog.ts`
  - `convex/sentry.ts`
  - `convex/account.test.ts`
- depends_on: `[B-resumable-backend]`
- unblocks: `[D-contract-mirrors, E-docs]`
- required_gates:
  - command: `npx vitest run convex/account.test.ts convex/analytics.test.ts`
  - status: `passed`
  - evidence: `Vendor fetch not called until scheduled deletion completes`
  - attempts: `1`
- human_gates:
  - `Live vendor cleanup checks require test PostHog/Sentry credentials; local fake-fetch tests are enough for this template unless explicitly requested.`
- notes: `Preserve fetch-based vendor seams and missing-config skip behavior.`
- todos:
  - `Assert PostHog deletePerson is called once after rows are gone.`
  - `Assert Sentry recordAccountCleanup is called once after rows are gone.`
  - `Assert missing config remains a skip state.`
- issues_found: `[]`
- actual_changed_paths:
  - `convex/account.ts`
  - `convex/account.test.ts`
- actual_evidence:
  - `npx vitest run convex/account.test.ts convex/analytics.test.ts` — 9 passed
- next: `D-contract-mirrors`

### Node D

- id: `D-contract-mirrors`
- mode: `implementation`
- status: `done`
- owner_type: `agent`
- executor: `execute-work`
- planned_write_scope:
  - `tests/fixtures/public-actions.json`
  - `ios/Core/`
  - `ios/Tests/`
- depends_on: `[B-resumable-backend, C-vendor-cleanup]`
- unblocks: `[E-docs, F-final-verification]`
- required_gates:
  - command: `npx vitest run convex`
  - status: `passed`
  - evidence: `17 Convex tests passed`
  - attempts: `1`
  - command: `xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'`
  - status: `passed`
  - evidence: `28 Swift tests passed`
  - attempts: `1`
- human_gates:
  - `Simulator availability may block Swift tests; record exact blocker if unavailable.`
- notes: `Skip this node if the backend keeps the public fixture shape for all documented cases and Swift mirrors do not need changes.`
- todos:
  - `Decide whether in-progress status belongs in the shared fixture.`
  - `Update Swift enums/decoders if needed.`
- issues_found: `[]`
- actual_changed_paths:
  - `tests/fixtures/public-actions.json`
  - `ios/Core/TemplateBackendContract.swift`
  - `ios/Tests/TemplateConvexCommandRequestTests.swift`
  - `ios/Tests/TemplateBackendClientTests.swift`
  - `ios/Tests/VoiceAgentTemplateModelTests.swift`
- actual_evidence:
  - `npx vitest run convex` — 17 passed
  - `xcodebuild test ...` — TEST SUCCEEDED, 28 tests
- next: `E-docs`

### Node E

- id: `E-docs`
- mode: `documentation`
- status: `done`
- owner_type: `agent`
- executor: `execute-work`
- planned_write_scope:
  - `docs/architecture.md`
  - `docs/deployment.md`
  - `.agents/learnings/`
- depends_on: `[B-resumable-backend, C-vendor-cleanup]`
- unblocks: `[F-final-verification]`
- required_gates:
  - command: `rg -n "deleteAccount|Account Deletion|Account Cleanup|deletion_in_progress" README.md docs .agents/learnings`
  - status: `passed`
  - evidence: `architecture.md and deployment.md updated`
  - attempts: `1`
- human_gates: `[]`
- notes: `Only add a new learning for reusable scheduler/vendor cleanup context.`
- todos:
  - `Document scheduled continuation semantics.`
  - `Document cleanup ordering and missing-config behavior.`
- issues_found: `[]`
- actual_changed_paths:
  - `docs/architecture.md`
  - `docs/deployment.md`
- actual_evidence:
  - `rg` gate — matches in architecture, deployment, README
- next: `F-final-verification`

### Node F

- id: `F-final-verification`
- mode: `verification`
- status: `done`
- owner_type: `agent`
- executor: `execute-work`
- planned_write_scope: `[]`
- depends_on: `[D-contract-mirrors, E-docs]`
- unblocks: `[ship-work]`
- required_gates:
  - command: `npx vitest run convex`
  - status: `passed`
  - evidence: `17 tests, 4 files`
  - attempts: `1`
  - command: `npx tsc -p convex/tsconfig.json`
  - status: `passed`
  - evidence: `exit 0`
  - attempts: `1`
- human_gates:
  - `Swift test gate required only if Node D changes Swift files.`
- notes: `Use verification-before-completion before claiming done.`
- todos:
  - `Record exact command output summary in the plan.`
  - `Move to ship-work if a PR is needed.`
- issues_found: `[]`
- actual_changed_paths: `[]`
- actual_evidence:
  - `npx vitest run convex` — 17 passed
  - `npx tsc -p convex/tsconfig.json` — exit 0
  - `xcodebuild test` — 28 passed
- next: `ship-work`

## Skills For Execution

- `convex-voice-agent`: required before backend account lifecycle changes.
- `tdd`: required for the behavioral fix.
- `execute-work`: use to implement each Delivery Map node.
- `ios-voice-template`: use only if Swift response mirrors or settings UI need
  updates.
- `ship-work`: use after implementation and verification if preparing a PR.

## Learnings Checked

- `.agents/learnings/convex-action-vendor-reporting.md`
- `.agents/learnings/deployment-secrets.md`

## Linear Updates

None. This template workspace does not currently define a Linear team, project,
or selected issue key in `docs/workflow.md`.

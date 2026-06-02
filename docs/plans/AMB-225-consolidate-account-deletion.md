# Consolidate Account Deletion Into account.ts

Status: Planning Artifact
Linear issue: [AMB-225](https://linear.app/ambimake/issue/AMB-225/consolidate-account-deletion-validators-into-account-module)
Created: 2026-05-31
Predecessor: `docs/plans/resumable-account-deletion.md` (behavior shipped; this is structural cleanup)

Note: this file records the original implementation plan. Completion evidence
and review-fix delivery status are tracked in
`docs/plans/AMB-225-review-fixes.md`.

## Goal

Apply a code-judo refactor: make `convex/account.ts` the single owner of account
deletion domain logic, response shaping, and shared Convex validators. Keep
`commands:deleteAccount` as a thin public action boundary (auth + Sentry wrapper
only).

Eliminate parallel TypeScript types and inline validator copies across
`commands.ts`, `account.ts`, and `schema.ts` so new owned tables or cleanup
states cannot drift across files.

## Non-Goals

- Do not change the public `commands:deleteAccount` response union or fixture
  shapes (`status: "deleted"` | `status: "deletion_in_progress"`).
- Do not change resumable batching, scheduler continuation, or vendor cleanup
  ordering.
- Do not add Apple token revocation (see completed YapTask work in AMB-187 for
  the product app; this template may mirror later).
- Do not move PostHog/Sentry HTTP helpers out of `convex/posthog.ts` and
  `convex/sentry.ts`.
- Do not add a generalized job framework.

## Ship Now

- Introduce one shared validator module for the account-deletion domain
  (recommended: `convex/lib/accountDeletionContract.ts`, imported by `account.ts` and
  `schema.ts`; re-export public types from `account.ts` for callers).
- Define validators once for:
  - `deleteCounts` (per-table deleted row counts);
  - `accountDeletionJobStatus`;
  - `posthogCleanupResult`, `sentryCleanupResult`, `accountDeletionCleanup`;
  - public `deleteAccountResponse` discriminated union.
- Derive TypeScript types with `Infer<typeof validator>` (or equivalent) from
  those validators; remove hand-written duplicate unions in `commands.ts`.
- Wire `convex/schema.ts` `accountDeletionJobs` fields through the shared
  validators (not copy-pasted `v.object` trees).
- Move synchronous batch loop, in-progress/deleted response mapping, and inline
  cleanup orchestration from `commands.ts` into `account.ts` (internal action or
  exported orchestration helper callable from the public action).
- Add `returns` validators on `commands:deleteAccount` and account lifecycle
  functions per `convex/_generated/ai/guidelines.md`.
- Remove unused `internal.account.deleteAccount` batch-only mutation (no
  callers after resumable deletion landed).
- Keep `MAX_SYNCHRONOUS_DELETE_BATCHES` next to deletion orchestration in the
  account module, not in `commands.ts`.

## Defer

- Schema-validator `.extend()` helpers for full `accountDeletionJobs` documents
  unless a query needs them.
- Swift or fixture updates (none expected if public JSON is unchanged).
- Extracting vendor cleanup into a third module beyond `account.ts` +
  `posthog.ts` + `sentry.ts`.

## Acceptance Criteria

- `commands.ts` `deleteAccount` handler is a thin wrapper: `requireOwnerKey`,
  `withSentry`, and one call into account-owned orchestration; no local
  `DeleteCounts` / cleanup / response types.
- `schema.ts` `accountDeletionJobs.deleted`, `status`, and `cleanup` use imported
  shared validators (grep shows no duplicated cleanup union literals in
  `schema.ts`).
- `finalizeAccountDeletion` args use the same `accountDeletionCleanupValidator`
  as the schema `cleanup` field.
- Public action behavior unchanged: existing `convex/account.test.ts` cases pass
  without assertion edits (except imports if tests move).
- `rg 'type DeleteCounts'` reports a single domain definition (plus inferred
  types if any).
- `internal.account.deleteAccount` is removed or renamed without breaking
  generated API references (run `npx convex codegen` after removal).
- `npx vitest run convex` and `npx tsc -p convex/tsconfig.json` pass.

## Code-Judo Target State

```text
commands:deleteAccount (public action)
  └─ requireOwnerKey + withSentry
       └─ account.executeAccountDeletion (internal action)
            ├─ requestAccountDeletion / runAccountDeletionBatch / schedule...
            ├─ runAccountDeletionVendorCleanup (existing)
            └─ map job/batch results → deleteAccountResponseValidator

convex/lib/accountDeletionContract.ts
  └─ exported validators + inferred types

convex/schema.ts
  └─ accountDeletionJobs fields ← shared validators

convex/posthog.ts / convex/sentry.ts
  └─ unchanged vendor internal actions
```

## Duplication To Remove (current)

| Concern | Today | After |
|--------|-------|-------|
| Delete counts | `DeleteCounts` in `account.ts` and `commands.ts` | One validator + inferred type |
| Cleanup unions | Inline in `schema.ts`, `finalizeAccountDeletion`, `commands.ts` types | `accountDeletionCleanupValidator` |
| Response union | Hand-written types in `commands.ts` | `deleteAccountResponseValidator` in lib/accountDeletion |
| Orchestration | ~50 lines in `commands.ts` | `account.ts` internal action |
| Legacy mutation | `export const deleteAccount = internalMutation` unused | Removed |

## Implementation Notes

- Read `convex/_generated/ai/guidelines.md` before editing Convex functions.
- Follow `.agents/skills/convex-voice-agent` boundaries: public action stays in
  `commands.ts`; lifecycle writes stay in `account.ts`.
- Mirror the `convex/lib/operations.ts` pattern: validators in `lib/`, domain
  orchestration in the owning module.
- Prefer importing validators into `schema.ts` from `lib/accountDeletionContract.ts`
  rather than from `account.ts` to avoid any risk of schema ↔ handler import
  cycles.
- Export `DeleteAccountResponse` and `deletionJobToDeletedResponse` from
  `account.ts` for `commands.ts` typing and tests.
- `deletionJobToDeletedResponse` should validate against the shared deleted
  response validator before return (or trust job shape after finalize — pick
  one approach and test).

## TDD / Skill Choice

- Primary: `.agents/skills/tdd` — behavior already covered; refactor should keep
  tests green. Add one focused test only if orchestration moves to an internal
  action and needs a direct seam (prefer keeping coverage via
  `api.commands.deleteAccount`).
- Supporting: `.agents/skills/convex-voice-agent` before edits.
- Not needed: `ios-voice-template` unless public JSON accidentally changes.

Suggested slice order:

1. Add `convex/lib/accountDeletionContract.ts` with validators; switch `schema.ts` —
   run tests (schema-only change should be behavior-neutral).
2. Replace inline cleanup args in `finalizeAccountDeletion`; run tests.
3. Move orchestration from `commands.ts` to `account.ts`; slim public action;
   run tests.
4. Remove dead `internal.account.deleteAccount`; run `npx convex codegen` and
   tests.
5. Add `returns` validators on public/internal functions; typecheck.

## Verification

```sh
npx vitest run convex
npx tsc -p convex/tsconfig.json
npx convex codegen
rg "type DeleteCounts|CleanupResult|SentryCleanupResult" convex/
rg "v\.object\(\{[\s\S]*posthog" convex/schema.ts convex/account.ts
```

Contract (should be unchanged):

- `tests/fixtures/public-actions.json` — no edits unless response keys change.
- Swift `TemplateBackendContract.swift` — no edits unless union changes.

## Learnings Applied

- Checked `.agents/learnings/README.md`; opened
  `convex-action-vendor-reporting.md`: vendor cleanup stays in isolated internal
  actions with fetch seams; do not pull Node SDKs into the public action module
  when moving orchestration.
- No new learning file unless codegen or scheduler edge cases surprise us.

## Documentation Impact

- Light touch `docs/architecture.md` Account Deletion: note shared validators
  live under `convex/lib/accountDeletionContract.ts` and orchestration is account-owned.
- No `docs/deployment.md` change unless env or operator steps change (they should
  not).

## Visual Evidence

Not required (backend-only refactor, no UI).

## Safe Concurrency

- Single backend worker owns `convex/lib/accountDeletionContract.ts`, `convex/account.ts`,
  `convex/commands.ts`, `convex/schema.ts`, and `convex/account.test.ts`.
- Do not split `schema.ts` and `account.ts` across parallel agents.
- Documentation node can run after backend gates pass.

## Delivery Map

### Node A — shared validators

- id: `A-shared-validators`
- mode: `tdd`
- status: `pending`
- owner_type: `agent`
- executor: `execute-work`
- planned_write_scope:
  - `convex/lib/accountDeletionContract.ts`
  - `convex/schema.ts`
  - `convex/account.ts` (import swaps only)
- depends_on: `[]`
- unblocks: `[B-orchestration, C-cleanup-dead-code]`
- required_gates:
  - command: `npx vitest run convex/account.test.ts`
  - status: `pending`
  - evidence: ``
  - attempts: `0`
  - command: `npx tsc -p convex/tsconfig.json`
  - status: `pending`
  - evidence: ``
  - attempts: `0`
- human_gates: `[]`
- notes: `Schema and finalizeAccountDeletion must reference the same validator objects.`
- todos:
  - `Create deleteCountsValidator and cleanup validators.`
  - `Replace schema inline objects with imports.`
- issues_found: `[]`
- actual_changed_paths: `[]`
- actual_evidence: `[]`
- next: `B-orchestration`

### Node B — move orchestration to account

- id: `B-orchestration`
- mode: `tdd`
- status: `pending`
- owner_type: `agent`
- executor: `execute-work`
- planned_write_scope:
  - `convex/account.ts`
  - `convex/commands.ts`
- depends_on: `[A-shared-validators]`
- unblocks: `[C-cleanup-dead-code, D-returns-validators, E-docs]`
- required_gates:
  - command: `npx vitest run convex`
  - status: `pending`
  - evidence: ``
  - attempts: `0`
- human_gates: `[]`
- notes: `commands.deleteAccount should only wrap auth, Sentry, and account orchestration.`
- todos:
  - `Add internal action or exported executeAccountDeletion helper.`
  - `Map batch/job kinds to deleteAccountResponse using shared validators.`
- issues_found: `[]`
- actual_changed_paths: `[]`
- actual_evidence: `[]`
- next: `C-cleanup-dead-code`

### Node C — remove dead API surface

- id: `C-cleanup-dead-code`
- mode: `implementation`
- status: `pending`
- owner_type: `agent`
- executor: `execute-work`
- planned_write_scope:
  - `convex/account.ts`
  - `convex/_generated/` (via codegen)
- depends_on: `[A-shared-validators, B-orchestration]`
- unblocks: `[D-returns-validators]`
- required_gates:
  - command: `npx convex codegen`
  - status: `pending`
  - evidence: ``
  - attempts: `0`
  - command: `npx vitest run convex`
  - status: `pending`
  - evidence: ``
  - attempts: `0`
- human_gates: `[]`
- notes: `Remove unused internal.account.deleteAccount mutation.`
- todos:
  - `Delete legacy batch-only mutation.`
  - `Confirm no references in tests or docs.`
- issues_found: `[]`
- actual_changed_paths: `[]`
- actual_evidence: `[]`
- next: `D-returns-validators`

### Node D — returns validators

- id: `D-returns-validators`
- mode: `implementation`
- status: `pending`
- owner_type: `agent`
- executor: `execute-work`
- planned_write_scope:
  - `convex/commands.ts`
  - `convex/account.ts`
- depends_on: `[B-orchestration, C-cleanup-dead-code]`
- unblocks: `[E-docs, F-final-verification]`
- required_gates:
  - command: `npx tsc -p convex/tsconfig.json`
  - status: `pending`
  - evidence: ``
  - attempts: `0`
- human_gates: `[]`
- notes: `Guidelines require returns on all Convex functions.`
- todos:
  - `Add returns to commands.deleteAccount and key account mutations/actions.`
- issues_found: `[]`
- actual_changed_paths: `[]`
- actual_evidence: `[]`
- next: `E-docs`

### Node E — docs

- id: `E-docs`
- mode: `documentation`
- status: `pending`
- owner_type: `agent`
- executor: `execute-work`
- planned_write_scope:
  - `docs/architecture.md`
- depends_on: `[D-returns-validators]`
- unblocks: `[F-final-verification]`
- required_gates:
  - command: `rg -n "accountDeletion|deleteAccount" docs/architecture.md`
  - status: `pending`
  - evidence: ``
  - attempts: `0`
- human_gates: `[]`
- notes: `One short paragraph on validator ownership.`
- todos: `[]`
- issues_found: `[]`
- actual_changed_paths: `[]`
- actual_evidence: `[]`
- next: `F-final-verification`

### Node F — final verification

- id: `F-final-verification`
- mode: `verification`
- status: `pending`
- owner_type: `agent`
- executor: `ship-work`
- planned_write_scope: `[]`
- depends_on: `[E-docs]`
- unblocks: `[]`
- required_gates:
  - command: `npx vitest run convex && npx tsc -p convex/tsconfig.json`
  - status: `pending`
  - evidence: ``
  - attempts: `0`
- human_gates: `[]`
- notes: `Ready for PR when all gates pass.`
- todos: `[]`
- issues_found: `[]`
- actual_changed_paths: `[]`
- actual_evidence: `[]`
- next: `ship-work`

# Template Hardening V2 Plan

> **For agentic workers:** Use `.agents/skills/execute-work` to complete one
> Delivery Map node at a time. Use `.agents/skills/tdd` for behavior changes,
> `.agents/skills/ios-voice-template` for SwiftUI/simulator work,
> `.agents/skills/convex-voice-agent` for Convex action/auth/voice/vendor work,
> and `.agents/skills/ship-work` before PR review or merge.

**Goal:** After the prototype extraction backlog, harden the template as a
cloneable starter: make setup mistakes obvious, make public contracts harder to
drift, and produce repeatable local evidence for the iOS starter states.

**Series status:** Implementation nodes complete; `node.ship-series` remains
pending. This is the next phase after `docs/plans/template-backlog.md`, which
is complete through PRs #4-#8.

**Linear status:** No Linear issue was selected for this planning pass. Treat
this file as Git-owned planning until tracker work is created and linked.

**Ship now:**

- Clone readiness checks that detect tracked local secrets, stale source-app
  paths, and broken placeholder assumptions.
- Contract fixture coverage that proves Swift and Convex still agree on public
  action, query, and mutation surfaces.
- Deterministic iOS launch states and smoke evidence for signed-out,
  signed-in/offline, missing-config, voice-denied, and deletion-progress paths.
- Documentation updates that tell clone owners which checks to run and what
  failures mean.

**Defer:**

- One-command project renaming.
- Live Apple Developer, Groq, Sentry, PostHog, or production Convex setup.
- App-specific domain replacement beyond the starter `entries` example.
- CI matrix design beyond documenting the local verification bar.
- Marketing/App Store assets.

## Context Applied

- `AGENTS.md`: preserve Convex ownership, command, apply-layer, account, and
  secret boundaries.
- `README.md`, `CUSTOMIZE.md`, `TEMPLATE_VARIABLES.md`,
  `docs/architecture.md`, and `docs/deployment.md`: current template setup,
  replacement, public contract, and deployment docs.
- `.agents/learnings/ios-simulator-verification.md`: use explicit simulator
  destinations and fixture launch arguments for visual evidence.
- `.agents/learnings/ios-accessibility-identifiers.md`: smoke tests need stable
  identifiers on concrete controls.
- `.agents/learnings/deployment-secrets.md` should be opened before any node
  edits secret/config guidance.
- `.agents/learnings/convex-action-payload-limits.md` and
  `.agents/learnings/convex-action-vendor-reporting.md` should be opened before
  nodes that touch voice payloads or vendor reporting.

## Acceptance Criteria

- A fresh clone owner can run one documented readiness sequence and understand
  which failures require local credentials, simulator repair, or code changes.
- No tracked file contains live deployment URLs, API tokens, Apple private key
  material, generated client secrets, or source-app project paths.
- Public Swift/Convex contract fixtures cover all starter endpoints:
  `commands:submitCommand`, `commands:transcribeVoiceCommand`,
  `commands:deleteAccount`, `entries:listEntries`, and
  `entries:updateEntry`.
- iOS starter states are smokeable without live Apple Sign In, microphone
  permission, or Convex credentials.
- The template docs explain how to replace the sample `entries` domain without
  violating command ownership, account deletion, or fixture sync boundaries.

## Verification Bar

Run the focused command listed on each node. Before shipping the series, run:

```sh
npm test
npm run typecheck:convex
xcodebuild build -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
```

If `npx convex codegen` is required by a node, run it. If it is blocked by
deployment configuration, record the exact blocker and keep generated files
unchanged unless codegen succeeds.

For UI-facing nodes, capture simulator screenshots into `.context/` and record
their paths in the Delivery Map.

## Dependency Order

1. Start with clone-readiness checks and docs. They establish the audit bar for
   later nodes.
2. Expand contract fixtures before changing smoke launch states, so UI and
   model fixtures can reuse stable response examples.
3. Add iOS launch states and smoke evidence after accessibility identifiers and
   fixture data are confirmed.
4. Finish with domain-replacement docs, using the hardened checks as the
   recommended workflow.

Safe concurrency:

- `node.clone-readiness` and `node.contract-fixtures` can run in parallel if
  write scopes stay separate.
- `node.ios-smoke-states` should wait for `node.contract-fixtures`.
- `node.domain-replacement-guide` should wait for the earlier nodes so it can
  reference final commands and evidence.

## Delivery Map

### node.clone-readiness

- `id`: `node.clone-readiness`
- `mode`: implementation
- `status`: complete
- `owner_type`: agent
- `executor`: `.agents/skills/execute-work` with `.agents/skills/tdd` if adding
  script tests
- `planned_write_scope`:
  - `package.json`
  - optional `scripts/` readiness helper
  - `.gitignore`
  - `CUSTOMIZE.md`
  - `docs/deployment.md`
  - `docs/plans/template-hardening-v2.md`
- `depends_on`: none
- `unblocks`:
  - `node.contract-fixtures`
  - `node.ios-smoke-states`
  - `node.domain-replacement-guide`
- `required_gates`:
  - command: `git check-ignore -v ios/Local.xcconfig .env.local .env || true`
    status: passed
    evidence: `.gitignore` ignores `ios/Local.xcconfig`, `.env.local`, and `.env`
    attempts: 1
  - command: `npm run verify:template`
    status: passed
    evidence: `Template readiness checks passed.`
    attempts: 1
  - command: `npm test`
    status: passed
    evidence: `vitest run convex scripts` passed 6 files and 27 tests; existing convex-test scheduled-function stderr in `account.test.ts`, exit 0
    attempts: 1
- `human_gates`: none
- `notes`:
  - `ios/Local.xcconfig` is intentionally gitignored; readiness checks should
    not fail because a developer has a local override.
  - Prefer a small auditable script only if the command list becomes too easy
    to run incorrectly.
- `todos`:
  - done: Added `npm run verify:template`.
  - done: Source-app and secret scans use tracked cloneable template files and ignore local-only config.
- `issues_found`: none
- `actual_changed_paths`:
  - `package.json`
  - `scripts/verify-template-readiness.mjs`
  - `scripts/verify-template-readiness.test.mjs`
  - `CUSTOMIZE.md`
  - `docs/deployment.md`
  - `docs/plans/template-hardening-v2.md`
- `actual_evidence`:
  - red: `npx vitest run scripts/verify-template-readiness.test.mjs` failed before the helper existed
  - focused green: `npx vitest run scripts/verify-template-readiness.test.mjs` passed 2 tests
  - gate: `git check-ignore -v ios/Local.xcconfig .env.local .env || true` passed
  - gate: `npm run verify:template` passed
  - gate: `npm test` passed 6 files and 27 tests
- `next`: `node.contract-fixtures`

### node.contract-fixtures

- `id`: `node.contract-fixtures`
- `mode`: implementation
- `status`: complete
- `owner_type`: agent
- `executor`: `.agents/skills/execute-work` with `.agents/skills/tdd` and
  `.agents/skills/convex-voice-agent`
- `planned_write_scope`:
  - `tests/fixtures/public-actions.json`
  - `convex/*.test.ts`
  - `ios/Tests/TemplateBackendClientTests.swift`
  - `ios/Tests/TemplateConvexCommandRequestTests.swift`
  - `ios/Core/TemplateBackendContract.swift` only if fixture decode resilience
    needs a public mirror change
  - `docs/architecture.md`
  - `docs/plans/template-hardening-v2.md`
- `depends_on`:
  - `node.clone-readiness`
- `unblocks`:
  - `node.ios-smoke-states`
  - `node.domain-replacement-guide`
- `required_gates`:
  - command: `npx vitest run convex`
    status: passed
    evidence: `6 files, 27 tests passed; existing convex-test scheduled-function stderr in account.test.ts, exit 0`
    attempts: 1
  - command: `npx tsc -p convex/tsconfig.json`
    status: passed
    evidence: `exit 0`
    attempts: 1
  - command: `xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'`
    status: passed
    evidence: `45 tests passed, 0 failures; xcresult Test-VoiceAgentTemplate-2026.06.02_20-46-39--0700.xcresult`
    attempts: 1
- `human_gates`: none
- `notes`:
  - Read `convex/_generated/ai/guidelines.md` before changing Convex tests or
    generated API assumptions.
  - Keep fixtures free of user-authored private content and source-app terms.
- `todos`:
  - done: Added backend exact endpoint coverage for the shared fixture.
  - done: Added backend update-entry DTO shape coverage; existing Swift tests decode and route the mutation fixture.
- `issues_found`: none
- `actual_changed_paths`:
  - `convex/publicActionsFixture.test.ts`
  - `docs/architecture.md`
  - `docs/plans/template-hardening-v2.md`
- `actual_evidence`:
  - focused: `npx vitest run convex/publicActionsFixture.test.ts` passed 2 tests
  - gate: `npx vitest run convex` passed 6 files and 27 tests
  - gate: `npx tsc -p convex/tsconfig.json` passed
  - gate: `xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'` passed 45 tests
- `next`: `node.ios-smoke-states`

### node.ios-smoke-states

- `id`: `node.ios-smoke-states`
- `mode`: implementation
- `status`: complete
- `owner_type`: agent
- `executor`: `.agents/skills/execute-work` with
  `.agents/skills/ios-voice-template`
- `planned_write_scope`:
  - `ios/App/VoiceAgentTemplateModel.swift`
  - `ios/App/VoiceAgentRootView.swift`
  - `ios/Features/Capture/`
  - `ios/Features/Settings/`
  - `ios/Core/TemplateAccessibility.swift`
  - `ios/Tests/`
  - `.agents/learnings/ios-simulator-verification.md` only if the smoke flow
    discovers a reusable simulator lesson
  - `docs/plans/template-hardening-v2.md`
- `depends_on`:
  - `node.contract-fixtures`
- `unblocks`:
  - `node.domain-replacement-guide`
- `required_gates`:
  - command: `xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'`
    status: passed
    evidence: `47 tests passed, 0 failures; xcresult Test-VoiceAgentTemplate-2026.06.02_20-48-36--0700.xcresult`
    attempts: 1
  - command: `xcodebuild build -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'`
    status: passed
    evidence: `BUILD SUCCEEDED`
    attempts: 1
  - command: `xcrun simctl launch --terminate-running-process "iPhone 16" com.example.voiceagent.template --template-signed-in`
    status: passed
    evidence: `launched com.example.voiceagent.template with --template-signed-in`
    attempts: 1
  - command: `xcrun simctl io "iPhone 16" screenshot .context/template-signed-in.png`
    status: passed
    evidence: `.context/template-signed-in.png`, 1179 x 2556 PNG
    attempts: 1
- `human_gates`: none
- `notes`:
  - Smoke states must not require live Apple Sign In, microphone permission, or
    Convex credentials.
  - Add launch arguments only for deterministic fixture states, not hidden app
    modes that diverge from runtime behavior.
- `todos`:
  - done: Inventoried existing signed-in, voice-fallback, and settings launch fixtures.
  - done: Added deletion-progress launch fixture and leaf entry body accessibility identifiers.
  - done: Captured signed-out, signed-in, voice-fallback, and deletion-progress screenshots.
- `issues_found`: none
- `actual_changed_paths`:
  - `ios/App/VoiceAgentTemplateModel.swift`
  - `ios/App/VoiceAgentRootView.swift`
  - `ios/Core/TemplateAccessibility.swift`
  - `ios/Tests/VoiceAgentTemplateModelTests.swift`
  - `docs/plans/template-hardening-v2.md`
- `actual_evidence`:
  - red: focused model test failed because `--template-deletion-progress` did not set feedback state
  - focused green: `xcodebuild test ... -only-testing:VoiceAgentTemplateTests/VoiceAgentTemplateModelTests` passed 12 tests
  - gate: `xcodebuild test ...` passed 47 tests
  - gate: `xcodebuild build ...` passed
  - visual: `.context/template-signed-out.png`
  - visual: `.context/template-signed-in.png`
  - visual: `.context/template-voice-fallback.png`
  - visual: `.context/template-deletion-progress.png`
- `next`: `node.domain-replacement-guide`

### node.domain-replacement-guide

- `id`: `node.domain-replacement-guide`
- `mode`: documentation
- `status`: complete
- `owner_type`: agent
- `executor`: `.agents/skills/execute-work`
- `planned_write_scope`:
  - `CUSTOMIZE.md`
  - `TEMPLATE_VARIABLES.md`
  - `docs/architecture.md`
  - `docs/deployment.md`
  - `README.md`
  - `docs/plans/template-hardening-v2.md`
- `depends_on`:
  - `node.clone-readiness`
  - `node.contract-fixtures`
  - `node.ios-smoke-states`
- `unblocks`:
  - `node.ship-series`
- `required_gates`:
  - command: `rg -n "entries|create_entry|TemplateBackendContract|accountDeletionOwnedTableNames|public-actions" CUSTOMIZE.md TEMPLATE_VARIABLES.md docs README.md`
    status: passed
    evidence: output includes replacement checklist coverage in `CUSTOMIZE.md`, placeholder inventory in `TEMPLATE_VARIABLES.md`, contract/account deletion guidance in `docs/architecture.md` and `docs/deployment.md`, and README setup notes
    attempts: 1
  - command: `npm test`
    status: passed
    evidence: `vitest run convex scripts` passed 7 files and 30 tests after review fix; existing convex-test scheduled-function stderr in `account.test.ts`, exit 0
    attempts: 2
- `human_gates`: none
- `notes`:
  - This node should explain replacement order, not perform a replacement.
  - Keep source-app names and reflection/journal language out of examples.
- `todos`:
  - done: Added a clear "replace entries domain" checklist to `CUSTOMIZE.md`.
  - done: Included account deletion and fixture update reminders for new owner-owned tables.
  - done: Pointed clone owners to readiness and simulator smoke commands.
- `issues_found`: none
- `actual_changed_paths`:
  - `CUSTOMIZE.md`
  - `TEMPLATE_VARIABLES.md`
  - `docs/deployment.md`
  - `README.md`
  - `docs/plans/template-hardening-v2.md`
- `actual_evidence`:
  - gate: `rg -n "entries|create_entry|TemplateBackendContract|accountDeletionOwnedTableNames|public-actions" CUSTOMIZE.md TEMPLATE_VARIABLES.md docs README.md` passed
  - gate: `npm test` passed 7 files and 29 tests
- `next`: `node.ship-series`

### node.ship-series

- `id`: `node.ship-series`
- `mode`: shipping
- `status`: blocked
- `owner_type`: agent
- `executor`: `.agents/skills/ship-work`
- `planned_write_scope`:
  - `docs/plans/template-hardening-v2.md`
  - PR body/checklist only
- `depends_on`:
  - `node.domain-replacement-guide`
- `unblocks`: none
- `required_gates`:
  - command: `npm test`
    status: passed
    evidence: `vitest run convex scripts` passed 7 files and 29 tests; existing convex-test scheduled-function stderr in `account.test.ts`, exit 0
    attempts: 1
  - command: `npm run typecheck:convex`
    status: passed
    evidence: `tsc -p convex/tsconfig.json` passed
    attempts: 1
  - command: `xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'`
    status: passed
    evidence: `47 tests passed, 0 failures; xcresult Test-VoiceAgentTemplate-2026.06.02_20-54-13--0700.xcresult`
    attempts: 1
  - command: `gh pr checks <pr-number>`
    status: blocked
    evidence: `gh pr checks 10` reports CodeRabbit pending, Greptile Review pending, and claude-review pending; PR is otherwise mergeable
    attempts: 3
- `human_gates`: PR review if repository policy requires human approval.
- `notes`:
  - Open separate PRs per node if the implementation becomes review-heavy.
  - Merge only after review comments, checks, and Delivery Map evidence are
    reconciled.
- `todos`: none
- `issues_found`:
  - `origin`: discovered_during_shipping
    `issue`: External review/check contexts remained pending after polling.
    `owner`: GitHub review/check providers.
    `next`: Rerun `gh pr checks 10` and inspect comments/reviews once CodeRabbit, Greptile, and claude-review finish.
  - `origin`: Qodo review
    `issue`: `verify:template` documented source-app Xcode project path scans but did not include `VoiceAgentTemplate.xcodeproj/`.
    `resolution`: Added `VoiceAgentTemplate.xcodeproj` to scanned roots and covered `project.pbxproj` with a focused readiness test.
- `actual_changed_paths`:
  - `docs/plans/template-hardening-v2.md`
  - PR body/checklist
- `actual_evidence`:
  - local gate: `npm test` passed 7 files and 30 tests after review fix
  - local gate: `npm run typecheck:convex` passed
  - local gate: `xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'` passed 47 tests
  - review fix gate: `npm run verify:template` passed
  - review fix gate: `npx vitest run scripts/verify-template-readiness.test.mjs` passed 3 tests
  - PR: https://github.com/ambimake/convex-ios-template/pull/10
  - PR state: open, not draft, mergeable
  - review triage: CodeRabbit and Qodo comments were summaries/in-progress notices with no actionable feedback; no reviews submitted
  - blocked check evidence: CodeRabbit pending, Greptile Review pending, claude-review pending
- `next`: terminal

## Durable Documentation Impact

By the end of this phase, `README.md`, `CUSTOMIZE.md`,
`TEMPLATE_VARIABLES.md`, `docs/architecture.md`, and `docs/deployment.md`
should agree on:

- which local files are intentionally ignored;
- which placeholders are expected in a fresh template;
- how to verify public Swift/Convex contracts;
- how to smoke the starter UI without live credentials;
- how to replace the `entries` sample domain without breaking account deletion
  or command boundaries.

## Open Questions

- Should readiness live as an `npm run verify:template` script, a documented
  command block, or both?
- Should iOS smoke evidence be automated with XCUITest, a shell script around
  `simctl`, or kept as documented manual simulator commands for now?
- Should this V2 plan be represented by one Linear issue or split into one
  issue per Delivery Map node once the tracker is configured?

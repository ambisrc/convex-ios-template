# Template Backlog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `.agents/skills/execute-work` to implement one task branch at a time. Use `.agents/skills/ship-work` before opening or updating PRs. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move reusable lessons from the prototype snapshot into the template through small, reviewable PRs while keeping journal/reflection product work out of the starter.

**Architecture:** Treat the default branch as the template source of truth. Use prototype work only as reference material, then reimplement generic slices on fresh template branches. Keep each slice independently buildable and easy to revert.

**Tech Stack:** SwiftUI, Xcode project settings, Convex Swift, Convex TypeScript, XCTest, Vitest, shared public-action fixtures.

---

## Reference Guidance

Do not merge prototype work directly into the template. Use prototype diffs only for selective inspection, then reimplement reusable pieces from the template base branch.

## Scope Rules

Reusable:

- Runtime iOS service wiring that lets configured clones talk to live Convex.
- Generic Apple Sign In and Convex auth adapter seams.
- Local config hygiene for deployment URLs and Xcode user state.
- Entry contracts that include stable IDs and owner-checked update paths.
- Public fixture coverage for actions, queries, and mutations.
- Plain transcript capture as the starter default command behavior.
- Clear docs/checklists for extending account deletion when adding tables.

Prototype-specific:

- Journal/reflection product language, UI, palettes, launch fixtures, and navigation.
- Reflection prompt tables, daily cron, reflection Groq prompt generation, and prompt-linked entries.
- App-specific bundle IDs, Apple client IDs, development team IDs, deployment URLs, and generated user state.

## Delivery Map

### node.ios-config

- `status`: ready to ship in the first template PR
- `purpose`: keep live Convex deployment URLs out of tracked plist files.
- `verification`:
  - `plutil -lint ios/Info.plist`
  - `xcodebuild -list -project VoiceAgentTemplate.xcodeproj`
  - `xcodebuild build -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'`
- `ship`: open PR against `main`.

### node.runtime-convex-auth

- `status`: ready for PR
- `branch`: `ambisrc/template-runtime-convex-auth`
- `purpose`: add generic live Swift runtime wiring for Convex and Apple Sign In.
- `files`:
  - `VoiceAgentTemplate.xcodeproj/project.pbxproj`
  - `VoiceAgentTemplate.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
  - `ios/Core/TemplateAppleAuthProvider.swift`
  - `ios/Core/TemplateAppleSignInService.swift`
  - `ios/Core/TemplateConvexArgumentDecoder.swift`
  - `ios/Core/TemplateConvexLiveCaller.swift`
  - `ios/Core/TemplateJWTIdentity.swift`
  - `ios/Core/TemplateRuntimeServices.swift`
  - `ios/Core/TemplateServices.swift`
  - `ios/Tests/TemplateRuntimeAuthTests.swift`
  - `ios/Tests/VoiceAgentTemplateModelTests.swift`
- `notes`:
  - Keep bundle IDs and fallback client IDs generic.
  - Do not commit a development team ID.
  - Do not pretend Apple cached login can mint a fresh ID token unless proven.
- `verification`:
  - passed: `xcodebuild -resolvePackageDependencies -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate` (Convex Swift `0.8.1`)
  - passed: `xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'` (42 tests, 0 failures)

### node.entry-contracts

- `status`: pending
- `branch`: create from the latest template base branch after previous PRs land.
- `purpose`: make starter entries editable through stable public contracts.
- `files`:
  - `convex/_generated/ai/guidelines.md` read first
  - `convex/entries.ts`
  - `convex/lib/apply.ts`
  - `convex/entries.test.ts`
  - `ios/Core/TemplateBackendClient.swift`
  - `ios/Core/TemplateBackendContract.swift`
  - `ios/Core/TemplateConvexCommandRequest.swift`
  - `ios/Tests/TemplateBackendClientTests.swift`
  - `ios/Tests/TemplateConvexCommandRequestTests.swift`
  - `tests/fixtures/public-actions.json`
- `notes`:
  - `entries:listEntries` should return `id`, `body`, and `source`, but not owner keys or internal metadata.
  - `entries:updateEntry` must derive ownership server-side and apply writes through `convex/lib/apply.ts`.
  - Extend the shared fixture format to include mutations.
- `verification`:
  - `npx vitest run convex`
  - `npx tsc -p convex/tsconfig.json`
  - `xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'`

### node.plain-transcript-command

- `status`: pending
- `branch`: create from the latest template base branch.
- `purpose`: make the starter voice loop save plain non-empty transcripts without requiring command grammar.
- `files`:
  - `convex/_generated/ai/guidelines.md` read first
  - `convex/lib/commandInterpreter.ts`
  - `convex/commandExecution.test.ts`
  - `tests/fixtures/public-actions.json` if response fixtures change
- `notes`:
  - Empty input should reject with `EMPTY_COMMAND`.
  - Existing explicit `create note saying ...` syntax can remain as a convenience.
  - Keep all assistant-driven writes entering through `convex/commands.ts:submitCommand`.
- `verification`:
  - `npx vitest run convex/commandExecution.test.ts`
  - `npx vitest run convex`
  - `npx tsc -p convex/tsconfig.json`

### node.account-deletion-extension-guide

- `status`: pending
- `branch`: create from the latest template base branch.
- `purpose`: make it hard to add new owner-owned tables without updating deletion contracts, Swift decoders, and fixtures.
- `files`:
  - `docs/architecture.md`
  - `docs/deployment.md`
  - `convex/lib/accountDeletionContract.ts`
  - `convex/account.test.ts`
  - `tests/fixtures/public-actions.json`
  - `ios/Core/TemplateBackendContract.swift` if decoder resilience changes
- `notes`:
  - Prefer docs and tests over adding abstraction unless duplication becomes meaningful.
  - Do not add reflection-specific tables or counts to the template.
- `verification`:
  - `npx vitest run convex/account.test.ts`
  - `npx vitest run convex`
  - `xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'`

## Working Rules

- Start each implementation branch from the latest template base branch unless building directly on a landed prior PR.
- Keep PRs small enough to review independently.
- Run a base-branch diff before opening each PR and remove prototype-specific values.
- Record exact verification evidence in each PR body.

# Customize This Template

Status: Template

Use this guide after copying `templates/voice-agent-ios-convex/` into a new
repository. It is the adoption contract for what a clone must rename, replace,
generate, configure, and verify before treating the starter as app-owned code.

## Setup Order

1. Rename the app and bundle identifiers listed in
   [TEMPLATE_VARIABLES.md](TEMPLATE_VARIABLES.md).
2. Replace the generic product language in [CONTEXT.md](CONTEXT.md) and
   [BRAND.md](BRAND.md).
3. Configure local env files from [.env.example](.env.example), keeping live
   values out of git.
4. Link or create a Convex deployment, then set server-side env vars from
   [docs/deployment.md](docs/deployment.md).
5. Replace the starter `entries` domain only after the public Swift/Convex
   contract tests pass unchanged.
6. Run `npx convex ai-files install` after cloning if
   `convex/_generated/ai/guidelines.md` is missing or Convex upgrades.
7. Run the verification commands in this guide before handing the clone to an
   app team.

## Replacement Inventory

Required app identity replacements:

- `VoiceAgentTemplate`: Xcode project, scheme, product/module name, Swift app
  type, test module import, and derived test bundle names.
- `Template`: Swift helper prefixes and generic copy placeholders that should
  become app-owned names once the clone's language is known.
- `com.example.voiceagent.template` and
  `com.example.voiceagent.template.tests`: iOS app and test bundle IDs.
- `com.example.voiceagent`: Apple Sign In client ID example in Convex auth and
  deployment docs.
- `https://example.convex.cloud` and
  `https://your-convex-deployment.convex.cloud`: local placeholder deployment
  URLs only.
- `dev:your-convex-deployment`: local Convex deployment placeholder only.

Keep these placeholders until the clone has a real app name, bundle ID, and
deployment. Do not replace them with YapTask values.

## Generated Files

Generated Convex files are part of the public contract:

- `convex/_generated/api.d.ts`
- `convex/_generated/api.js`
- `convex/_generated/dataModel.d.ts`
- `convex/_generated/server.d.ts`
- `convex/_generated/server.js`
- `convex/_generated/ai/guidelines.md`

Run `npx convex codegen` after changing Convex functions, validators, schema,
or generated API references. If codegen asks for deployment setup, configure
`CONVEX_DEPLOYMENT` or run `npx convex dev` for the clone, then rerun codegen.
Do not claim generated files are current when codegen is blocked.

## Public Contract Checks

The shared fixture at [tests/fixtures/public-actions.json](tests/fixtures/public-actions.json)
is consumed by both Vitest and XCTest. It covers:

- `commands:submitCommand` action name, request shape, success response, and
  returned entry shape.
- `commands:transcribeVoiceCommand` action name, request shape, success
  response, and `configuration_missing` response union.
- `commands:deleteAccount` action name and starter deletion response shape.
- `entries:listEntries` read seam name and projected public DTO shape.
- `entries:updateEntry` mutation seam name, request shape, and projected public
  DTO shape.

When a clone changes action names, request fields, response status values, or
domain result shapes, update this fixture in the same change as the backend and
Swift tests.

## Domain Replacement Points

The starter domain is intentionally small:

- `convex/lib/commandInterpreter.ts`: replace starter natural-language parsing
  and summary generation.
- `convex/lib/operations.ts`: replace typed operation validators and TypeScript
  operation types.
- `convex/lib/apply.ts`: replace the transactional domain apply facade and
  server-owned writes for sample-domain tables.
- `convex/entries.ts`: replace sample-domain read queries and public list DTOs.
- `ios/Core/TemplateBackendContract.swift`: replace Swift request/response DTO
  mirrors when the public contract changes.
- `ios/Core/TemplateBackendClient.swift`: replace endpoint routing and live
  Convex Swift client wiring.
- `ios/App/VoiceAgentTemplateModel.swift`: replace starter state projection
  only after service contracts are stable.

Keep `convex/commands.ts` as orchestration for auth, trusted public actions,
provider calls, and apply-layer handoff. Do not bury clone-specific parsing
directly in the public action once the domain grows beyond the starter example.

## Replace The Entries Domain

Use this order when turning the sample `entries` model into clone-owned domain
objects:

1. Write the domain terms in [CONTEXT.md](CONTEXT.md) before renaming code.
2. Replace `convex/schema.ts`, `convex/lib/operations.ts`,
   `convex/lib/commandInterpreter.ts`, `convex/lib/apply.ts`, and
   `convex/entries.ts` together so validated operations, server-owned writes,
   and public read/mutation DTOs stay aligned.
3. Keep assistant-driven writes entering through
   `convex/commands.ts:submitCommand`; derive ownership through Convex auth and
   do not add client-supplied user IDs.
4. Update [tests/fixtures/public-actions.json](tests/fixtures/public-actions.json)
   for every changed public action, query, mutation, request body, response
   union, and DTO field.
5. Update Swift mirrors in `ios/Core/TemplateBackendContract.swift`,
   endpoint routing in `ios/Core/TemplateBackendClient.swift`, and model state
   projection in `ios/App/VoiceAgentTemplateModel.swift`.
6. When adding an owner-owned table, extend account deletion in the same change:
   update `convex/account.ts`, `accountDeletionOwnedTableNames` and
   validators in `convex/lib/accountDeletionContract.ts`, delete-account
   fixture counts, and `TemplateDeleteAccountResult.DeletedCounts`.
7. Add or update stable accessibility identifiers and fixture launch arguments
   only for smokeable states the clone can render without live credentials.
8. Run the verification block below before handing the clone to an app team.

## Verification

Run from the template root:

```sh
npm run verify:template
npm test
npm run typecheck:convex
npx convex codegen
xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
```

`npm run verify:template` checks that local env files stay ignored and that the
cloneable template surface does not track Apple private key material,
source-app deployment IDs, source-app Xcode project paths, or live-looking
secret assignments. It intentionally allows placeholders in `.env.example` and
documented public example values.

Substitute an installed simulator if your local Xcode does not include iOS 18.5
or iPhone 16. `xcrun simctl list devices available` shows available
destinations.

For visual smoke evidence after a successful build, install the simulator app
and launch fixture states that do not require live Apple Sign In, microphone
permission, or Convex credentials:

```sh
xcrun simctl install "iPhone 16" "<path-to-built VoiceAgentTemplate.app>"
xcrun simctl launch --terminate-running-process "iPhone 16" com.example.voiceagent.template --template-signed-in
xcrun simctl io "iPhone 16" screenshot .context/template-signed-in.png
xcrun simctl launch --terminate-running-process "iPhone 16" com.example.voiceagent.template --template-voice-fallback
xcrun simctl io "iPhone 16" screenshot .context/template-voice-fallback.png
xcrun simctl launch --terminate-running-process "iPhone 16" com.example.voiceagent.template --template-deletion-progress
xcrun simctl io "iPhone 16" screenshot .context/template-deletion-progress.png
```

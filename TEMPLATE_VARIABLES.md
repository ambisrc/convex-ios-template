# Template Variables

Status: Template

This file lists clone-owned names and placeholders. Replace them deliberately
instead of doing a blind global rename.

| Placeholder | Meaning | Common locations |
| --- | --- | --- |
| `VoiceAgentTemplate` | Xcode project, scheme, module, app, and test product name. | `VoiceAgentTemplate.xcodeproj`, `ios/App/`, `ios/Tests/`, README commands |
| `VoiceAgentTemplateApp` | Swift app entry point. | `ios/App/VoiceAgentTemplateApp.swift` |
| `VoiceAgentTemplateModel` | Starter app model. | `ios/App/VoiceAgentTemplateModel.swift`, tests |
| `Template*` | Generic Swift service, state, analytics, Sentry, and accessibility prefixes. | `ios/Core/`, `ios/Features/`, `ios/Tests/` |
| `com.example.voiceagent.template` | Debug/release starter app bundle ID. | Xcode project build settings |
| `com.example.voiceagent.template.tests` | Starter test bundle ID. | Xcode project build settings |
| `com.example.voiceagent` | Example Apple Sign In client ID. | `convex/auth.config.ts`, deployment docs, tests |
| `https://example.convex.cloud` | Placeholder Convex deployment URL used to detect unwired live clients. | `ios/Info.plist`, Swift configuration tests |
| `dev:your-convex-deployment` | Placeholder local Convex deployment name. | `.env.example` |
| `https://your-convex-deployment.convex.cloud` | Placeholder local Convex deployment URL. | `.env.example` |
| `TemplateBackendContract` / `TemplateBackendClient` | Swift public DTO mirrors and Convex caller seam. | `ios/Core/TemplateBackendContract.swift`, `ios/Core/TemplateBackendClient.swift`, `ios/Tests/` |
| `entries` | Sample domain table, read model, and update seam. | `convex/schema.ts`, `convex/entries.ts`, `convex/lib/apply.ts`, Swift entry models |
| `entries:listEntries` / `entries:updateEntry` | Sample public query and mutation names mirrored by Swift and fixtures. | `tests/fixtures/public-actions.json`, `ios/Core/TemplateBackendContract.swift`, backend and Swift tests |
| `create_entry` | Starter assistant operation type. | `convex/lib/operations.ts`, contract fixture, Swift tests |
| `accountDeletionOwnedTableNames` | Owner-owned table count contract for delete-account fixtures and Swift mirrors. | `convex/lib/accountDeletionContract.ts`, `convex/account.ts`, `tests/fixtures/public-actions.json` |
| `--template-signed-in`, `--template-voice-fallback`, `--template-deletion-progress` | Fixture launch states for simulator smoke evidence without live credentials. | `ios/App/VoiceAgentTemplateModel.swift`, `CUSTOMIZE.md`, plan evidence |

Generated Convex files under `convex/_generated/` should be refreshed with
`npx convex codegen` after renaming functions, schema, or validators. Do not
hand-edit generated API files except to inspect diffs.

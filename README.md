# Voice Agent iOS Convex Template

Status: Starter

This is a cloneable starter for a small voice-agent iOS app using SwiftUI,
Convex, Sign in with Apple, backend voice transcription, a trusted backend
command action, Sentry, PostHog, and account deletion cleanup hooks.

The template is intentionally not YapTask. Its example domain is `entries`: a
signed-in user can type or speak a short request, the backend validates a
generic operation, and server-owned mutations persist an entry.

## Includes

- Convex schema for profiles, entries, command history, Apple Sign In
  credentials, and privacy-limited usage events.
- Public command actions in `convex/commands.ts`:
  `submitCommand`, `transcribeVoiceCommand`,
  `recordAppleSignInAuthorization`, and `deleteAccount`.
- Auth-owned data access through Convex identity `tokenIdentifier`.
- Voice payload limits that account for base64 expansion before transcription.
- Fetch-based Sentry and PostHog hooks that skip safely when env vars are
  absent. PostHog can request person deletion; Sentry records a best-effort
  account-cleanup report instead of claiming user deletion.
- Shared Swift/Convex public-contract fixtures for command, voice, account
  deletion, entry list, and entry update seams.
- Focused tests for command execution, account deletion, voice payload limits,
  contract fixture drift, analytics payload privacy, and Swift service seams.

## Excludes

- YapTask List, Task, Subtask, timeline, undo, and command semantics.
- Billing, subscriptions, feature flags, session replay, dashboards, or
  marketplace packaging.
- Live secrets or deployment-specific vendor IDs.
- One-command project renaming.

## Backend Setup

1. Clone or copy this directory into a new repository.
2. Follow [CUSTOMIZE.md](CUSTOMIZE.md) and
   [TEMPLATE_VARIABLES.md](TEMPLATE_VARIABLES.md) for app names, bundle IDs,
   domain replacement points, generated-file policy, and verification.
3. Copy `.env.example` to a gitignored local env file and fill local values.
4. Configure Convex deployment env vars separately from local machine secrets.
5. Run `npm run verify:template` to confirm local env files are ignored and no
   tracked template file contains live-looking secrets or stale source-app
   setup paths.
6. Run `npx convex ai-files install` after cloning if
   `convex/_generated/ai/guidelines.md` is absent or stale.
7. Run backend verification:

```sh
npm test
npm run typecheck:convex
```

Root YapTask Convex commands are separate from this template-local backend.
Run template commands from this directory after copying it.

## iOS Setup

The starter includes a template-local Xcode project. A clone does not need the
root YapTask project to build or test the iOS app.

```sh
xcodebuild build -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
```

The default app services expose real seams for Sign in with Apple, Convex
commands, voice audio handoff, Sentry scope, PostHog capture, and account
deletion. Until a clone wires live credentials and SDK clients, those seams
return explicit configuration-missing messages instead of pretending a live
request succeeded.

The iOS app reads `CONVEX_DEPLOYMENT_URL` from `ios/Config.xcconfig`, with
gitignored local overrides in `ios/Local.xcconfig`; `ios/Info.plist` expands
that value at build time. `POSTHOG_API_KEY` and `POSTHOG_HOST` remain in
`ios/Info.plist` for the starter. Server-side Convex functions read Apple,
Groq, Sentry, and PostHog cleanup values from Convex deployment env vars.

For credential-free visual smoke checks, build and install the app on a
simulator, then launch fixture states such as `--template-signed-in`,
`--template-voice-fallback`, and `--template-deletion-progress` before taking
screenshots.

## Top-Level Docs

- `CUSTOMIZE.md`: clone setup order, replacement inventory, contract checks,
  and verification.
- `TEMPLATE_VARIABLES.md`: placeholder inventory and generated-file policy.
- `CONTEXT.md`: product contract to customize for the clone.
- `BRAND.md`: generic voice, positioning, and onboarding copy guidance.
- `ENGINEERING.md`: reusable engineering and verification principles.
- `AGENTS.md`: coding-agent rules and skill routing.
- `docs/README.md`: documentation map.
- `docs/architecture.md`, `docs/deployment.md`, and `docs/workflow.md`:
  system, setup, and tracker workflow guides.

## Agent Pack

Reusable agent guidance lives under `.agents/`:

- `.agents/skills/tdd`: red-green-refactor workflow for backend and Swift seams.
- `.agents/skills/diagnose`: disciplined debugging loop.
- `.agents/skills/choose-work`, `plan-work`, `execute-work`, and `ship-work`:
  generic Linear-primary workflow skills.
- `.agents/skills/convex-voice-agent`: Convex command, auth, voice, vendor, and
  account-lifecycle boundaries.
- `.agents/skills/ios-voice-template`: SwiftUI, capture, accessibility, and
  simulator verification workflow.
- `.agents/learnings/`: compact runbooks for payload limits, vendor reporting,
  deployment secrets, simulator verification, and accessibility identifiers.
- `docs/workflow.md`: tracker setup and source-of-truth boundaries.

These are intentionally generic. They exclude YapTask's Linear workflow,
product language, task/list/subtask model, and branch-specific planning rules.

## Secrets

Tracked files may name env vars, but must not contain live values. Keep Apple
private keys, generated Apple client secrets, Groq keys, Sentry tokens, and
PostHog personal API keys in gitignored local files or vendor dashboards.

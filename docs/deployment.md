# Deployment

Status: Template

Use `.env.example` as a variable index only. Do not commit live values.

## Adoption Checklist

1. Replace placeholders listed in
   [../TEMPLATE_VARIABLES.md](../TEMPLATE_VARIABLES.md).
2. Copy `.env.example` to `.env.local` or another gitignored local file.
3. Link a clone-owned Convex deployment and set `CONVEX_DEPLOYMENT`.
4. Set Convex deployment env vars with `npx convex env set`; do not put server
   secrets in Swift, Info.plist, or tracked docs.
5. Run `npx convex ai-files install` if
   `convex/_generated/ai/guidelines.md` is missing.
6. Run `npx convex codegen` after function, schema, or validator changes.

## Convex

Set server-side values in the linked Convex deployment:

```sh
npx convex env set APPLE_SIGN_IN_CLIENT_IDS "com.example.voiceagent"
npx convex env set APPLE_SIGN_IN_CLIENT_SECRET "<generated-jwt>"
npx convex env set GROQ_API_KEY "<groq-api-key>"
npx convex env set SENTRY_DSN "<sentry-dsn>"
npx convex env set SENTRY_AUTH_TOKEN "<sentry-auth-token>"
npx convex env set SENTRY_ORG_SLUG "<sentry-org-slug>"
npx convex env set SENTRY_PROJECT_SLUG "<sentry-project-slug>"
npx convex env set POSTHOG_HOST "https://app.posthog.com"
npx convex env set POSTHOG_PROJECT_ID "<posthog-project-id>"
npx convex env set POSTHOG_PERSONAL_API_KEY "<posthog-personal-api-key>"
```

Run local backend checks:

```sh
npx vitest run convex
npx tsc -p convex/tsconfig.json
npx convex codegen
```

If `npx convex codegen` asks for deployment setup, stop and configure the
clone's `CONVEX_DEPLOYMENT` or run `npx convex dev`, then rerun codegen.
Record the exact blocker if credentials or deployment ownership are not
available.

## Apple Sign In

Create an App ID and Sign in with Apple key in Apple Developer. Generate an
Apple client secret JWT locally from the private `.p8` key, then store only the
JWT value in Convex env. Keep the `.p8` file outside git.

## iOS

Replace the example bundle identifier before shipping a clone. `ios/Info.plist`
reads `CONVEX_DEPLOYMENT_URL` from `ios/Config.xcconfig`, which includes an
optional gitignored `ios/Local.xcconfig` for local device builds. Keep live
deployment URLs in `ios/Local.xcconfig`, not in tracked plist files. If the
clone uses PostHog from iOS, set `POSTHOG_API_KEY` and `POSTHOG_HOST` in
`ios/Info.plist`; leave them empty for a no-op local starter. Build with an
explicit simulator destination:

```sh
xcodebuild build -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
```

If simulator tests are blocked by local CoreSimulator state, record the exact
error and rerun after repairing or replacing the simulator.

## Contract Verification

The public Swift/Convex contract is checked by
[../tests/fixtures/public-actions.json](../tests/fixtures/public-actions.json).
Update the fixture whenever a clone changes public action/query names, request
shapes, response status values, or read-list response fields.

## Account Cleanup

`commands:deleteAccount` deletes app-owned Convex rows in bounded batches. When
more rows remain than fit in the synchronous action budget, Convex schedules
continuation mutations with `ctx.scheduler.runAfter(0, ...)` until app-owned
rows are gone. PostHog and Sentry cleanup run once after deletion completes.
Missing PostHog or Sentry configuration remains a skip state. Vendor cleanup
request failures are stored in the final cleanup result instead of blocking
account deletion completion.

PostHog cleanup uses the configured deletion request API. Sentry cleanup records
a best-effort account-cleanup report for project operators; it does not claim
to delete or scrub Sentry user records.

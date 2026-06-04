# Runtime Apple Sign In Swift Flow

Status: Implemented (ship-work blocked on mixed-scope worktree)

## Goal

Make the iOS sign-in button work against the live Convex deployment by wiring
native Sign in with Apple to Convex Swift authentication and routing all
subsequent command/query/action calls through the authenticated Convex client.

The runtime flow should:

- present Apple Sign In through `AuthenticationServices`;
- read Apple's `identityToken` and use it as the Convex auth JWT;
- create one process-lifetime authenticated Convex Swift client;
- route `commands:submitCommand`, `commands:transcribeVoiceCommand`,
  `entries:listEntries`, `reflections:listLatest`, `reflections:generateNow`,
  `entries:updateEntry`, and `commands:deleteAccount` through that client;
- optionally persist Apple credential material through
  `commands:recordAppleSignInAuthorization` only when a real refresh token is
  available.

## Non-Goals

- Do not change Convex ownership. Backend functions must continue deriving
  ownership from `ctx.auth.getUserIdentity()` and `identity.tokenIdentifier`.
- Do not pass a client-supplied user ID to Convex.
- Do not store Apple private keys, generated client secrets, live deployment
  URLs, API tokens, identity tokens, authorization codes, or refresh tokens in
  tracked files.
- Do not make voice capture or command interpretation changes beyond using the
  authenticated client for existing calls.
- Do not pretend cached Apple reauthentication can mint a fresh ID token unless
  the implementation proves it with Apple's APIs or a server-side token flow.

## Ship Now / Defer

Ship now:

- Interactive Apple Sign In launches from the existing sign-in button.
- A successful Apple credential with a valid UTF-8 `identityToken` authenticates
  `ConvexClientWithAuth`.
- The app signs in only after Convex auth state is authenticated, then loads the
  home data through authenticated calls.
- Missing configuration, canceled Apple auth, missing identity token, and
  Convex auth failure show explicit error messages and do not fake sign-in.
- Existing tests keep using injected seams without requiring live Apple or
  Convex credentials.

Defer or split if needed:

- Silent sign-in across app launches. Native Apple Sign In can check credential
  state, but the Convex Swift `AuthProvider` needs an ID token callback; if a
  fresh token cannot be obtained without UI, treat cached login as unavailable.
- Refresh-token persistence. `ASAuthorizationAppleIDCredential` provides an
  `authorizationCode`, while the current
  `commands:recordAppleSignInAuthorization` action expects `refreshToken`.
  Either add a backend authorization-code exchange against Apple's token
  endpoint, or call the existing action only from a trusted path that already
  has a refresh token. Do not send an authorization code in the `refreshToken`
  field.

## Current Repo State

- `ios/Core/TemplateServices.swift` has `TemplateConfiguredSessionService`,
  which currently throws configuration-missing errors instead of presenting
  Apple Sign In.
- `ios/Core/TemplateBackendClient.swift` has the `TemplateConvexCalling` seam
  and an injectable `TemplateBackendClient`, but the app defaults to
  `PlaceholderTemplateBackendClient`.
- `ios/App/VoiceAgentTemplateModel.swift` already handles successful sign-in by
  binding Sentry scope, capturing `auth_signed_in`, and loading home data.
- `ios/App/VoiceAgentRootView.swift` already exposes the Sign in with Apple
  button and accessibility identifier.
- `ios/VoiceAgentTemplate.entitlements` already includes Sign in with Apple.
- `convex/auth.config.ts` is configured for Apple as an OIDC provider.
- `convex/commands.ts` already exposes
  `commands:recordAppleSignInAuthorization`; `convex/account.ts` stores
  refresh tokens under the authenticated owner key.
- `tests/fixtures/public-actions.json` does not currently include
  `commands:recordAppleSignInAuthorization`, even though it is part of the
  public Swift/Convex contract.

## References Checked

- `README.md`, `docs/architecture.md`, `docs/deployment.md`,
  `docs/workflow.md`, `AGENTS.md`
- `.agents/learnings/deployment-secrets.md`
- `.agents/learnings/ios-simulator-verification.md`
- `.agents/learnings/ios-accessibility-identifiers.md`
- `convex/_generated/ai/guidelines.md`
- Convex Swift docs:
  https://docs.convex.dev/client/swift/overview
- Convex Swift `AuthProvider` API:
  https://github.com/get-convex/convex-swift/blob/main/Sources/ConvexMobile/ConvexMobile.swift
- Apple `ASAuthorizationAppleIDCredential` docs:
  https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidcredential

## TDD / Execution Skill Choice

Use `.agents/skills/tdd` for implementation. The behavior is clear and testable
through public Swift service seams. Use `.agents/skills/ios-voice-template`
before SwiftUI, app state, accessibility, or simulator evidence work. Use
`.agents/skills/convex-voice-agent` before any backend change, especially if
the refresh-token path grows into an authorization-code exchange.

## Acceptance Criteria

1. Tapping the existing Apple sign-in button presents
   `ASAuthorizationAppleIDProvider` interactive auth in live builds.
2. On success, the implementation extracts a UTF-8 `identityToken` from
   `ASAuthorizationAppleIDCredential`.
3. Convex calls use `ConvexClientWithAuth` or the current Convex Swift auth API
   with a custom Apple auth provider that supplies the Apple ID token.
4. `VoiceAgentTemplateModel.signIn()` sets `isSignedIn = true` only after the
   Apple credential and Convex auth client are ready.
5. The app uses the live `TemplateBackendClient` with an authenticated
   `TemplateConvexCalling` adapter when `CONVEX_DEPLOYMENT_URL` is configured.
6. Existing command, voice transcription, list, reflection, entry update, and
   delete-account calls route through the authenticated client and therefore
   satisfy Convex `AUTH_REQUIRED` backend checks.
7. Apple auth cancellation, missing identity token, invalid UTF-8 token data,
   missing Convex URL, placeholder URL, and Convex login failure leave the app
   signed out with a concrete feedback message.
8. If `commands:recordAppleSignInAuthorization` is used, tests prove it sends
   `{ clientId, refreshToken }` only when a refresh token exists; otherwise the
   call is skipped.
9. The public-action fixture includes
   `commands:recordAppleSignInAuthorization` if Swift adds a DTO/client method
   for it.
10. No tests or fixtures contain live Apple, Convex, Sentry, PostHog, or Groq
    secrets.

## Planned Implementation

1. Add the Convex Swift package dependency to
   `VoiceAgentTemplate.xcodeproj/project.pbxproj`, using
   `https://github.com/get-convex/convex-swift` and the `ConvexMobile` product.
   Resolve package dependencies before the first build.
2. Add an Apple auth provider/service under `ios/Core/`, likely
   `TemplateAppleSignInService.swift`, that wraps `ASAuthorizationController`
   delegate callbacks into `async` code and returns an auth result containing
   `user`, `clientId`, `identityToken`, and optional credential metadata.
3. Implement a Convex auth provider adapter that conforms to Convex Swift's
   `AuthProvider`. It should call the Apple service for interactive `login`,
   invoke the `onIdToken` callback with the extracted identity token, and make
   `loginFromCache` fail or return unauthenticated unless a valid no-UI token
   path is implemented.
4. Implement `TemplateConvexLiveCaller` behind `TemplateConvexCalling`. It
   should translate encoded Swift request bodies into Convex argument
   dictionaries or supported Convex encodable values, then call `action`,
   `query`/subscription-as-one-shot as appropriate, and `mutation`.
5. Replace app defaults in `VoiceAgentTemplateModel` or
   `VoiceAgentTemplateApp` so configured builds use a shared authenticated
   Convex service container, while tests can continue injecting stubs.
6. Add Swift DTOs/endpoints for `commands:recordAppleSignInAuthorization` only
   if the implementation can provide a real refresh token or a trusted exchange
   result. Otherwise document the skip and leave the action unused from iOS.
7. Add focused Swift tests around Apple credential parsing, missing-token
   errors, authenticated caller routing, configured service assembly, and model
   sign-in state. Use fakes for `AuthenticationServices` and Convex.
8. Run backend checks if the fixture or Convex action contract changes. Run iOS
   build/tests and capture simulator evidence for the sign-in screen and a
   signed-in fixture state.

## Verification Commands

Backend, only if Convex files or shared fixtures change:

```sh
npx vitest run convex
npx tsc -p convex/tsconfig.json
npx convex codegen
```

iOS:

```sh
xcodebuild -resolvePackageDependencies -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate
xcodebuild build -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
```

Manual/live checks:

```sh
xcrun simctl boot "iPhone 16" 2>/dev/null || true
xcrun simctl install "iPhone 16" "<DerivedData app path>"
xcrun simctl launch --terminate-running-process "iPhone 16" com.example.voiceagent.template
```

Manual evidence to record:

- screenshot of the signed-out screen with the Apple sign-in button;
- screenshot or short note confirming Apple auth UI appears;
- screenshot of signed-in home after a successful live sign-in;
- command submission or `entries:listEntries` response proving Convex accepted
  authenticated calls;
- exact blocker if Apple Developer credentials, provisioning, or Convex
  deployment env vars are unavailable.

## Human Gates

- Apple Developer App ID, bundle ID, provisioning profile, and Sign in with
  Apple entitlement must match the built app.
- Convex `APPLE_SIGN_IN_CLIENT_IDS` must include the app's Apple audience.
- `ios/Local.xcconfig` or equivalent local config must provide a real
  `CONVEX_DEPLOYMENT_URL`; keep it gitignored.
- If refresh-token persistence is required, someone must decide whether to add
  server-side Apple token exchange or provide refresh tokens through an
  existing trusted path.

## Durable Documentation Impact

- Update `docs/deployment.md` if the iOS runtime setup requires extra local
  config, provisioning, or package-resolution steps.
- Update `docs/architecture.md` if the service assembly changes the stable
  Swift/Convex adapter contract.
- Add a learning only if Apple credential caching, Convex Swift auth, or
  simulator Sign in with Apple verification exposes a reusable caveat.

## Dependency Ordering And Concurrency

- The package dependency and live Convex caller can be implemented in parallel
  with the Apple auth provider because they share only the final assembly seam.
- Contract fixture/DTO updates should wait until the refresh-token persistence
  decision is made.
- Simulator visual evidence waits for the app to build and for the configured
  service assembly to compile.
- Backend verification is independent unless Convex code or shared fixtures
  change.

## Delivery Map

### node.runtime-auth-provider

- `id`: `runtime-auth-provider`
- `mode`: `tdd`
- `status`: `done`
- `owner_type`: `agent`
- `executor`: `.agents/skills/tdd` plus `.agents/skills/ios-voice-template`
- `planned_write_scope`:
  - `ios/Core/TemplateServices.swift`
  - `ios/Core/TemplateAppleSignInService.swift`
  - `ios/Tests/VoiceAgentTemplateModelTests.swift`
  - new focused Swift auth-provider tests if useful
- `depends_on`: []
- `unblocks`: `runtime-convex-client`, `runtime-service-assembly`
- `required_gates`:
  - command: focused Swift tests for auth provider/model sign-in
  - status: `passed`
  - evidence: `xcodebuild test` — 41 tests, 0 failures; `TemplateRuntimeAuthTests` + model sign-in failure test
  - attempts: 1
- `human_gates`:
  - Apple Developer provisioning for live auth UI
- `notes`:
  - Native Apple credentials supply `identityToken` and `authorizationCode`.
    Do not treat authorization code as refresh token.
- `todos`:
  - Add delegate bridge around `ASAuthorizationController`.
  - Test cancellation and missing identity-token failures.
- `issues_found`: []
- `actual_changed_paths`:
  - `ios/Core/TemplateAppleSignInService.swift`
  - `ios/Core/TemplateAppleAuthProvider.swift`
  - `ios/Core/TemplateJWTIdentity.swift`
  - `ios/Core/TemplateServices.swift`
  - `ios/Tests/TemplateRuntimeAuthTests.swift`
  - `ios/Tests/VoiceAgentTemplateModelTests.swift`
- `actual_evidence`:
  - Credential parser, JWT owner-key, and model auth-failure tests pass in iOS test run.
- `next`: `runtime-service-assembly` (completed in same execution pass)

### node.runtime-convex-client

- `id`: `runtime-convex-client`
- `mode`: `tdd`
- `status`: `done`
- `owner_type`: `agent`
- `executor`: `.agents/skills/tdd`
- `planned_write_scope`:
  - `VoiceAgentTemplate.xcodeproj/project.pbxproj`
  - `ios/Core/TemplateBackendClient.swift`
  - `ios/Core/TemplateBackendContract.swift`
  - `ios/Tests/TemplateBackendClientTests.swift`
- `depends_on`: []
- `unblocks`: `runtime-service-assembly`
- `required_gates`:
  - command: `xcodebuild -resolvePackageDependencies -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate`
  - status: `passed`
  - evidence: resolved `ConvexMobile` @ 0.8.1
  - attempts: 1
  - command: focused backend-client Swift tests
  - status: `passed`
  - evidence: `TemplateBackendClientTests` pass after JSON semantic body comparison fix
  - attempts: 1
- `human_gates`: []
- `notes`:
  - Convex docs say to use one process-lifetime client and
    `ConvexClientWithAuth` for authenticated calls.
- `todos`:
  - Add `ConvexMobile` package product.
  - Implement request-body to Convex-argument conversion without ad hoc string
    surgery.
  - Preserve injectable caller tests.
- `issues_found`: []
- `actual_changed_paths`:
  - `VoiceAgentTemplate.xcodeproj/project.pbxproj`
  - `ios/Core/TemplateBackendClient.swift` (unchanged behavior; live caller added separately)
  - `ios/Core/TemplateConvexArgumentDecoder.swift`
  - `ios/Core/TemplateConvexLiveCaller.swift`
  - `ios/Tests/TemplateBackendClientTests.swift`
- `actual_evidence`:
  - Package resolve succeeded; app build succeeded on iPhone 16 / iOS 18.5 simulator.
- `next`: `runtime-service-assembly`

### node.runtime-record-apple-authorization

- `id`: `runtime-record-apple-authorization`
- `mode`: `decision`
- `status`: `deferred`
- `owner_type`: `human_or_agent`
- `executor`: `.agents/skills/convex-voice-agent` if backend exchange is added
- `planned_write_scope`:
  - `tests/fixtures/public-actions.json`
  - `ios/Core/TemplateBackendClient.swift`
  - `ios/Core/TemplateBackendContract.swift`
  - `ios/Tests/TemplateBackendClientTests.swift`
  - possible backend files only if adding authorization-code exchange
- `depends_on`: `runtime-auth-provider`
- `unblocks`: `runtime-service-assembly`
- `required_gates`:
  - command: Swift DTO/client tests if action is wired
  - status: `waived`
  - evidence: ship-now defers refresh-token persistence; iOS does not call `commands:recordAppleSignInAuthorization`
  - attempts: 0
  - command: `npx vitest run convex`
  - status: `waived`
  - evidence: no backend or shared fixture changes in this execution pass
  - attempts: 0
- `human_gates`:
  - Decide whether refresh-token persistence is required for this release.
  - Provide Apple client secret only through Convex env if server exchange is
    added.
- `notes`:
  - Current action takes `refreshToken`; iOS native auth does not directly
    provide one.
  - **Decision:** skip iOS wiring for ship-now; authorization code is not sent
    as `refreshToken`.
- `todos`:
  - Either skip this call for ship-now or implement a real token exchange.
- `issues_found`: []
- `actual_changed_paths`: []
- `actual_evidence`:
  - No Swift DTO or fixture update; deferred per plan ship-now scope.
- `next`: unblock `runtime-service-assembly` via waiver

### node.runtime-service-assembly

- `id`: `runtime-service-assembly`
- `mode`: `tdd`
- `status`: `done`
- `owner_type`: `agent`
- `executor`: `.agents/skills/tdd` plus `.agents/skills/ios-voice-template`
- `planned_write_scope`:
  - `ios/App/VoiceAgentTemplateApp.swift`
  - `ios/App/VoiceAgentTemplateModel.swift`
  - `ios/Core/TemplateServices.swift`
  - `ios/Tests/VoiceAgentTemplateModelTests.swift`
- `depends_on`: `runtime-auth-provider`, `runtime-convex-client`
- `unblocks`: `runtime-verification`
- `required_gates`:
  - command: focused model/service-assembly tests
  - status: `passed`
  - evidence: `VoiceAgentTemplateModelTests` — 12 tests pass including sign-in failure and fixture states
  - attempts: 1
- `human_gates`: []
- `notes`:
  - Preserve launch fixtures so visual checks can run without live auth.
- `todos`:
  - Share one authenticated Convex service container.
  - Keep test injection simple and deterministic.
- `issues_found`: []
- `actual_changed_paths`:
  - `ios/Core/TemplateRuntimeServices.swift`
  - `ios/App/VoiceAgentTemplateModel.swift`
- `actual_evidence`:
  - Configured builds assemble shared `TemplateRuntimeServiceContainer` with one `ConvexClientWithAuth` and live caller.
- `next`: `runtime-verification`

### node.runtime-verification

- `id`: `runtime-verification`
- `mode`: `verify`
- `status`: `done`
- `owner_type`: `agent`
- `executor`: `.agents/skills/ios-voice-template`
- `planned_write_scope`:
  - `.context/` evidence files only
- `depends_on`: `runtime-service-assembly`
- `unblocks`: `ship-work`
- `required_gates`:
  - command: `xcodebuild build -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'`
  - status: `passed`
  - evidence: BUILD SUCCEEDED
  - attempts: 1
  - command: `xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'`
  - status: `passed`
  - evidence: 41 tests, 0 failures
  - attempts: 2
  - command: simulator screenshots for signed-out and signed-in fixture states
  - status: `passed`
  - evidence: `.context/runtime-apple-sign-in-signed-out.png`, `.context/runtime-apple-sign-in-signed-in-fixture.png`
  - attempts: 1
- `human_gates`:
  - Live Apple Sign In manual check may require configured Apple account,
    matching provisioning profile, and a real Convex deployment URL.
- `notes`:
  - If CoreSimulator fails with known device-state errors, record the exact
    failure and preserve build evidence separately.
  - Live Apple auth UI + authenticated Convex calls remain **blocked** until
    `ios/Local.xcconfig` (or equivalent) provides a real `CONVEX_DEPLOYMENT_URL`
    and Apple/Convex env alignment is confirmed on device/simulator.
- `todos`:
  - Save screenshots under `.context/`.
  - Record live-check blockers explicitly.
- `issues_found`: []
- `actual_changed_paths`:
  - `.context/runtime-apple-sign-in-signed-out.png`
  - `.context/runtime-apple-sign-in-signed-in-fixture.png`
- `actual_evidence`:
  - Build/test green on iPhone 16 / iOS 18.5 simulator.
  - Fixture screenshots captured without live Apple or Convex credentials.
- `next`: `ship-work`

### node.runtime-ship-work

- `id`: `runtime-ship-work`
- `mode`: `ship`
- `status`: `blocked`
- `owner_type`: `agent`
- `executor`: `.agents/skills/ship-work`
- `planned_write_scope`:
  - `docs/plans/runtime-apple-sign-in-swift.md`
- `depends_on`: `runtime-verification`
- `unblocks`: PR creation
- `required_gates`:
  - command: `xcodebuild -resolvePackageDependencies -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate`
  - status: `passed`
  - evidence: resolved `ConvexMobile` @ 0.8.1
  - attempts: 1
  - command: `xcodebuild build -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'`
  - status: `passed`
  - evidence: `BUILD SUCCEEDED`; simulator entitlements include `com.apple.developer.applesignin`
  - attempts: 1
  - command: `xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'`
  - status: `passed`
  - evidence: 41 tests, 0 failures
  - attempts: 1
  - command: `npx vitest run convex`
  - status: `passed`
  - evidence: 23 tests across 6 files passed; stderr reported a `convex-test` scheduled-function rollback warning in `account.test.ts`, but the process exited 0
  - attempts: 1
  - command: `npx tsc -p convex/tsconfig.json`
  - status: `passed`
  - evidence: TypeScript clean; npm emitted an experimental CommonJS/ESM warning
  - attempts: 1
  - command: `npx convex codegen`
  - status: `passed`
  - evidence: generated bindings and uploaded functions to the linked Convex deployment
  - attempts: 1
  - command: `git diff --check`
  - status: `passed`
  - evidence: no whitespace errors
  - attempts: 1
- `human_gates`:
  - Decide whether to create one broad PR containing the adjacent journal/reflection/backend work, or split this runtime-auth work into a clean workspace/branch.
  - Live Apple Sign In still requires real `CONVEX_DEPLOYMENT_URL`, matching Apple provisioning, and Convex `APPLE_SIGN_IN_CLIENT_IDS`.
- `notes`:
  - PR creation is blocked because the worktree is mixed-scope. Runtime-auth files are present, but the same worktree also contains journal/reflection UI, backend reflection generation, entry editing, bundle/team/project configuration, and other unrelated changes.
  - `VoiceAgentTemplate.xcodeproj/project.xcworkspace/xcuserdata/.../UserInterfaceState.xcuserstate` is untracked user UI state and should not be committed.
  - `.context/AuthKey_2PUAN9RU37.p8` exists but is gitignored under `.context/`; do not copy it into tracked files.
  - Tracked secret-pattern scan found no matches.
- `todos`:
  - For a runtime-auth-only PR, isolate/stage only auth/client/package/config changes and remove unrelated project-file hunks before committing.
  - For a broad PR, include `docs/plans/voice-journal-prototype.md` and run/review acceptance for that scope too.
- `issues_found`:
  - Mixed-scope worktree prevents a clean ship-work PR decision.
- `actual_changed_paths`:
  - `docs/plans/runtime-apple-sign-in-swift.md`
- `actual_evidence`:
  - Local verification green as listed above.
- `next`: choose split-clean-PR or broad-PR scope, then commit and open PR.

## Linear Updates

No Linear issue key was provided in the prompt, so no Linear issue was read or
updated. If this work is tracker-backed, link this plan to the selected issue
before execution.

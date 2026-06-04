# Voice Journal Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `.agents/skills/execute-work` for Delivery Map execution. For code changes inside a node, use `.agents/skills/tdd`; use `.agents/skills/convex-voice-agent` before Convex command, voice, cron, or model-provider work; use `.agents/skills/ios-voice-template` before SwiftUI, capture, accessibility, or simulator work. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working private voice-journal prototype with a ritual-feed Home, a dedicated watercolor Brain Dump voice screen, auto-saved transcribed entries, daily generated reflection prompts, and prompt-driven follow-up dumps.

**Architecture:** SwiftUI owns navigation, display, microphone state, and fixture-driven visual states. Convex owns authenticated data, voice transcription, assistant-command writes, scheduled reflection generation, and entry/reflection persistence. Public assistant-created entries continue through `convex/commands.ts:submitCommand`; manual entry edits and reflection read state must still derive ownership from Convex auth and keep database writes in the server apply layer.

**Tech Stack:** SwiftUI, XCTest, AVFoundation capture seam, Convex TypeScript, `convex-test`, Vitest, Convex crons, fetch-based model-provider calls, existing Groq transcription seam.

---

## Current Context

There is no Linear issue selected for this work. This is a repo-local plan for a prototype and should be linked to Linear later if the clone adopts tracker workflow.

The approved product direction from brainstorming:

- Home is a calm "Today" ritual feed.
- Home does not record directly.
- The first Home card navigates to the dedicated Brain Dump screen.
- Brain Dump uses the generated watercolor background, one prompt, voice waveform, and one microphone button.
- Speaking auto-saves the resulting transcription as a private entry.
- After dumps, reflection prompts appear as bubbles/cards and can launch the same voice dump flow with prompt context.
- Cron-generated reflections start with "entries since the last reflection run, once per day."

## Ship Now

- Signed-in app shell with Home ritual feed and dedicated Brain Dump destination.
- Fixture launch states for Home, Brain Dump, and post-dump reflections.
- Voice command path keeps existing transcription flow but changes command interpretation so raw brain dumps create entries without requiring "create a note saying...".
- Entry rows persist `body`, `source`, timestamps, and optional `promptId` for entries created from a reflection prompt.
- Basic manual edit path for saved entries through authenticated Convex update, applied through `convex/lib/apply.ts`.
- Reflection tables, queries, and an authenticated action to generate reflections on demand for local/manual testing.
- `convex/crons.ts` daily job that generates reflections for profiles with new entries since their last run.
- Swift contracts and model state for Home feed, reflection prompts, and prompt-linked voice dumps.
- Visual evidence using fixture launch arguments and simulator screenshots.

## Defer

- General chat over the journal.
- Rich theme clustering UI.
- Notifications/reminders.
- Billing, sync beyond Convex, widgets, or calendar integration.
- Durable raw audio storage.
- Analytics containing transcript, entry body, prompt body, or raw audio.
- A polished history/search editor beyond the simple manual edit needed for the prototype.

## Acceptance Criteria

1. A signed-in fixture can show Home with a watercolor Brain Dump card, reflection prompt cards, and recent thread cards.
2. Tapping/opening Brain Dump shows a dedicated watercolor voice screen with prompt text, waveform, and one microphone control.
3. Starting voice capture transcribes audio through `commands:transcribeVoiceCommand`, submits the transcript through `commands:submitCommand`, and inserts the saved entry at the top of local state.
4. A plain transcript such as `"I felt scattered today but clearer after walking"` creates an entry; it does not require command grammar.
5. Unsupported/empty submissions do not create partial writes.
6. Reflection generation analyzes only entries since the owner's previous reflection run and stores 1-3 prompts.
7. Reflection prompt rows are returned without owner keys or Convex document internals.
8. Starting a dump from a reflection prompt links the created entry to that prompt and marks the prompt answered.
9. Manual edits update an existing entry body only for the authenticated owner.
10. Account deletion removes entries, command history, usage events, reflection prompts, reflection runs, and any new reflection state.
11. Local tests pass without live secrets by mocking provider fetches or using configuration-missing/fake seams.
12. Live transcription/reflection checks are documented as blocked unless `GROQ_API_KEY` and Convex deployment configuration are available.

## Relevant Learnings Applied

- `convex-action-payload-limits.md`: voice audio remains base64 payload through existing cap; no durable audio storage.
- `convex-action-vendor-reporting.md`: provider/analytics calls use fetch helpers; private journal content is not sent to analytics.
- `deployment-secrets.md`: no live keys, deployment IDs, generated Apple secrets, or filled env files are committed.
- `ios-simulator-verification.md`: simulator commands use explicit `platform=iOS Simulator,OS=18.5,name=iPhone 16`.
- `ios-accessibility-identifiers.md`: tap targets get identifiers on concrete controls.
- `convex/_generated/ai/guidelines.md` is present after `npx convex ai-files install`; read it before implementing Convex changes.

## Planned File Structure

### Convex

- Modify `convex/schema.ts`: add prompt/run tables and optional entry prompt link.
- Modify `convex/lib/operations.ts`: keep `create_entry`; optionally add `promptId` validator for prompt-linked entry creation.
- Modify `convex/lib/commandInterpreter.ts`: brain-dump transcript becomes a `create_entry` operation by default.
- Modify `convex/lib/apply.ts`: create entries, update entries, mark reflection prompts answered, delete reflection data through account lifecycle hooks.
- Modify `convex/commands.ts`: accept optional `promptId` on `submitCommand`; keep public write entry point for assistant-driven entry creation.
- Modify `convex/entries.ts`: list and update user-owned entries through public DTOs.
- Create `convex/reflections.ts`: public queries/actions for latest prompts and manual generation.
- Create `convex/lib/reflectionGenerator.ts`: fetch-based model-provider prompt generation with test seam.
- Create `convex/crons.ts`: daily reflection generation cron.
- Modify `convex/account.ts` and `convex/lib/accountDeletionContract.ts`: include reflection tables in deletion counts.
- Modify `convex/commandExecution.test.ts`; create `convex/reflections.test.ts`; update `convex/account.test.ts`.
- Modify `tests/fixtures/public-actions.json`: public contracts for reflection and updated entry DTOs.

### iOS

- Modify `ios/Core/TemplateBackendContract.swift`: add `TemplateReflectionPrompt`, entry IDs, prompt links, update-entry response.
- Modify `ios/Core/TemplateBackendClient.swift`: add endpoints for reflection queries/actions and entry update.
- Modify `ios/Core/TemplateAccessibility.swift`: add Home, Brain Dump, waveform, prompt card, and edit identifiers.
- Modify `ios/App/VoiceAgentTemplateModel.swift`: navigation state, Home feed state, prompt-linked dump state, list/load/edit methods.
- Modify `ios/App/VoiceAgentRootView.swift`: replace current list-first signed-in view with Home + navigation.
- Create `ios/Features/Home/RitualHomeView.swift`: Today feed.
- Create `ios/Features/Capture/BrainDumpView.swift`: watercolor voice surface.
- Create `ios/Features/Capture/WatercolorBackgroundView.swift`: SwiftUI approximation or bundled PNG-backed background.
- Create `ios/Features/Reflections/ReflectionPromptBubble.swift`: reusable prompt card/bubble.
- Create `ios/Features/Entries/EntryEditorView.swift`: simple body editor for manual edits.
- Modify `ios/Tests/VoiceAgentTemplateModelTests.swift`, `ios/Tests/TemplateBackendClientTests.swift`, `ios/Tests/TemplateConvexCommandRequestTests.swift`.
- Add deterministic fixture launch args: `--journal-home`, `--journal-brain-dump`, `--journal-reflections`.

### Assets

- Copy the approved watercolor from `.superpowers/brainstorm/78983-1780373100/content/watercolor-bg.png` into a durable project path during implementation, for example `ios/Resources/watercolor-bg.png`, and add it to the app target resources. If Xcode resource wiring is too much for the first slice, create `WatercolorBackgroundView` with SwiftUI gradients and blobs that match the mockup, then add the PNG in a later visual-polish node.

## Verification Commands

Backend:

```sh
npx convex ai-files install
npx vitest run convex
npx tsc -p convex/tsconfig.json
npx convex codegen
```

iOS:

```sh
xcodebuild build -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
```

Visual evidence:

```sh
xcrun simctl boot "iPhone 16" 2>/dev/null || true
xcrun simctl install "iPhone 16" "<derived-data-app-path>/VoiceAgentTemplate.app"
xcrun simctl launch --terminate-running-process "iPhone 16" com.example.voiceagent.template --journal-home
xcrun simctl io "iPhone 16" screenshot .context/journal-home.png
xcrun simctl launch --terminate-running-process "iPhone 16" com.example.voiceagent.template --journal-brain-dump
xcrun simctl io "iPhone 16" screenshot .context/journal-brain-dump.png
xcrun simctl launch --terminate-running-process "iPhone 16" com.example.voiceagent.template --journal-reflections
xcrun simctl io "iPhone 16" screenshot .context/journal-reflections.png
```

Manual live checks, only when credentials are available:

```sh
npx convex env set GROQ_API_KEY "<groq-api-key>"
npx convex dev
```

Then run the app against the linked deployment and confirm a short microphone recording becomes a saved entry. Do not commit the key or deployment-local env.

## Implementation Tasks

### Task 1: Backend Brain Dump Entries

**Files:**

- Modify `convex/lib/commandInterpreter.ts`
- Modify `convex/lib/operations.ts`
- Modify `convex/lib/apply.ts`
- Modify `convex/commands.ts`
- Modify `convex/commandExecution.test.ts`
- Modify `tests/fixtures/public-actions.json`

- [x] **Step 1: Read Convex AI guidelines**

Run:

```sh
sed -n '1,220p' convex/_generated/ai/guidelines.md
```

Expected: local Convex API guidance is available and has been reviewed before editing Convex files.

- [x] **Step 2: Add a failing backend test for plain brain dumps**

Add this test to `convex/commandExecution.test.ts`:

```ts
it("saves a plain voice brain dump without command grammar", async () => {
  const t = convexTest(schema, modules).withIdentity(identity);

  const response = await t.action(api.commands.submitCommand, {
    text: "I felt scattered today but clearer after walking",
    source: "voice",
  });

  expect(response.status).toBe("applied");
  expect(response.operations).toEqual([
    { type: "create_entry", body: "I felt scattered today but clearer after walking" },
  ]);

  const entries = await t.query(api.entries.listEntries, {});
  expect(entries[0]).toMatchObject({
    body: "I felt scattered today but clearer after walking",
    source: "voice",
  });
});
```

Run:

```sh
npx vitest run convex/commandExecution.test.ts -t "plain voice brain dump"
```

Expected now: FAIL with the current `UNSUPPORTED_COMMAND` behavior.

- [x] **Step 3: Change command interpretation to default to entry creation**

Replace the parse logic in `convex/lib/commandInterpreter.ts` so it trims text, rejects empty input, still strips existing "create note" prefixes, and otherwise creates an entry from the raw transcript:

```ts
function parseOperations(text: string): AssistantOperation[] {
  if (!text) {
    throw new Error("EMPTY_COMMAND");
  }

  const explicitEntry = text
    .replace(/^create\s+(a\s+)?(note|entry)\s+(saying|called|named)\s+/i, "")
    .trim();

  const body = explicitEntry || text;
  return [{ type: "create_entry", body }];
}
```

Keep `commands.ts` as the public action boundary.

- [x] **Step 4: Run focused backend tests**

Run:

```sh
npx vitest run convex/commandExecution.test.ts
```

Expected: existing tests need one update: the old unsupported-command case should become an empty-command rejection test.

- [x] **Step 5: Update unsupported test to empty-input behavior**

Replace the old unsupported command test with:

```ts
it("rejects empty command submissions without partial writes", async () => {
  const t = convexTest(schema, modules).withIdentity(identity);

  await expect(
    t.action(api.commands.submitCommand, {
      text: "   ",
      source: "typed",
    }),
  ).rejects.toThrow("EMPTY_COMMAND");

  await expect(t.query(api.entries.listEntries, {})).resolves.toEqual([]);
});
```

Run:

```sh
npx vitest run convex/commandExecution.test.ts
```

Expected: PASS.

### Task 2: Reflection Data Model And Generation

**Files:**

- Modify `convex/schema.ts`
- Create `convex/reflections.ts`
- Create `convex/lib/reflectionGenerator.ts`
- Create `convex/crons.ts`
- Modify `convex/account.ts`
- Modify `convex/lib/accountDeletionContract.ts`
- Create `convex/reflections.test.ts`
- Modify `convex/account.test.ts`
- Modify `tests/fixtures/public-actions.json`

- [ ] **Step 1: Write a failing reflection generation test**

Create `convex/reflections.test.ts` with a public behavior test:

```ts
/// <reference types="vite/client" />
// @vitest-environment edge-runtime

import { convexTest } from "convex-test";
import { describe, expect, it, vi } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");
const identity = { issuer: "test", subject: "user-1", tokenIdentifier: "test|user-1" };

describe("reflection generation", () => {
  it("generates prompts from entries since the previous run", async () => {
    vi.stubGlobal("process", { env: { GROQ_API_KEY: "test-groq-key" } });
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({
      choices: [{
        message: {
          content: JSON.stringify({
            questions: [
              "What kept coming back?",
              "Where was there energy?",
              "Say the unpolished version.",
            ],
          }),
        },
      }],
    }), { status: 200 })));

    const t = convexTest(schema, modules).withIdentity(identity);
    await t.action(api.commands.submitCommand, {
      text: "I felt scattered today but clearer after walking",
      source: "voice",
    });

    const generated = await t.action(api.reflections.generateNow, {});

    expect(generated.status).toBe("generated");
    expect(generated.prompts.map((p) => p.question)).toEqual([
      "What kept coming back?",
      "Where was there energy?",
      "Say the unpolished version.",
    ]);

    const latest = await t.query(api.reflections.listLatest, {});
    expect(latest).toEqual(generated.prompts);
    expect(latest[0]).not.toHaveProperty("ownerKey");
  });
});
```

Run:

```sh
npx vitest run convex/reflections.test.ts
```

Expected now: FAIL because `api.reflections` does not exist.

- [ ] **Step 2: Add reflection schema**

Extend `convex/schema.ts`:

```ts
reflectionRuns: defineTable({
  ownerKey: v.string(),
  entryWindowStart: v.number(),
  entryWindowEnd: v.number(),
  status: v.union(v.literal("generated"), v.literal("skipped"), v.literal("failed")),
  promptCount: v.number(),
  errorCode: v.optional(v.string()),
  createdAt: v.number(),
}).index("by_ownerKey_and_createdAt", ["ownerKey", "createdAt"]),

reflectionPrompts: defineTable({
  ownerKey: v.string(),
  runId: v.id("reflectionRuns"),
  question: v.string(),
  status: v.union(v.literal("open"), v.literal("answered")),
  answeredEntryId: v.optional(v.id("entries")),
  createdAt: v.number(),
  updatedAt: v.number(),
}).index("by_ownerKey_and_createdAt", ["ownerKey", "createdAt"]),
```

Also add optional `promptId: v.optional(v.id("reflectionPrompts"))` to `entries`.

- [ ] **Step 3: Implement fetch-based reflection generation seam**

Create `convex/lib/reflectionGenerator.ts`:

```ts
type ReflectionQuestionResult =
  | { status: "generated"; questions: string[] }
  | { status: "configuration_missing"; missing: "GROQ_API_KEY" };

export async function generateReflectionQuestions(entries: string[]): Promise<ReflectionQuestionResult> {
  const apiKey = process.env.GROQ_API_KEY;
  if (!apiKey) {
    return { status: "configuration_missing", missing: "GROQ_API_KEY" };
  }

  const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: process.env.GROQ_REFLECTION_MODEL ?? "llama-3.3-70b-versatile",
      messages: [
        {
          role: "system",
          content: "You generate three short, gentle reflection questions for a private journal. Return JSON only: {\"questions\":[\"...\"]}. Do not summarize the journal.",
        },
        {
          role: "user",
          content: JSON.stringify({ entries }),
        },
      ],
      temperature: 0.7,
    }),
  });

  if (!response.ok) {
    throw new Error(`REFLECTION_PROVIDER_${response.status}`);
  }
  const json = await response.json();
  const content = json.choices?.[0]?.message?.content;
  const parsed = JSON.parse(content);
  return {
    status: "generated",
    questions: parsed.questions.slice(0, 3).map((q: string) => q.trim()).filter(Boolean),
  };
}
```

- [ ] **Step 4: Implement reflection public/query API**

Create `convex/reflections.ts` with:

- `listLatest` query returning `{ id, question, status, createdAt }[]`.
- `generateNow` action deriving `ownerKey` with `requireOwnerKey(ctx)`, finding entries since the latest run, calling `generateReflectionQuestions`, and writing a run/prompts through internal mutations in `convex/lib/apply.ts`.
- If provider config is missing, return `{ status: "configuration_missing", missing: "GROQ_API_KEY", prompts: [] }` and do not write fake AI prompts.
- If there are no new entries, write a skipped run or return `{ status: "skipped", reason: "no_new_entries", prompts: [] }`.

- [ ] **Step 5: Add daily cron**

Create `convex/crons.ts`:

```ts
import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

crons.daily(
  "generate daily reflection prompts",
  { hourUTC: 13, minuteUTC: 0 },
  internal.reflections.generateDailyForActiveProfiles,
);

export default crons;
```

Implement `internal.reflections.generateDailyForActiveProfiles` so it scans recent profiles in bounded batches and schedules or runs generation per owner. Use a low batch size for the prototype.

- [ ] **Step 6: Add account deletion coverage**

Update account deletion counts and batch deletion helpers to include `reflectionPrompts` and `reflectionRuns`. Add assertions in `convex/account.test.ts` that generated prompts/runs are removed by `commands:deleteAccount`.

- [ ] **Step 7: Run backend verification**

Run:

```sh
npx vitest run convex
npx tsc -p convex/tsconfig.json
npx convex codegen
```

Expected: PASS, or `npx convex codegen` records a deployment setup blocker.

### Task 3: Swift Contracts And Model State

**Files:**

- Modify `ios/Core/TemplateBackendContract.swift`
- Modify `ios/Core/TemplateBackendClient.swift`
- Modify `ios/Core/TemplateAccessibility.swift`
- Modify `ios/App/VoiceAgentTemplateModel.swift`
- Modify `ios/Tests/TemplateBackendClientTests.swift`
- Modify `ios/Tests/TemplateConvexCommandRequestTests.swift`
- Modify `ios/Tests/VoiceAgentTemplateModelTests.swift`
- Modify `tests/fixtures/public-actions.json`

- [ ] **Step 1: Add shared contract fixtures**

Add `reflections:listLatest`, `reflections:generateNow`, and an entry update endpoint to `tests/fixtures/public-actions.json`. Use response shapes with public DTO fields only:

```json
"reflections:listLatest": {
  "request": {},
  "success": [
    {
      "id": "reflectionPromptFixture",
      "question": "What kept coming back?",
      "status": "open",
      "createdAt": 1720000000000
    }
  ]
}
```

- [ ] **Step 2: Write Swift decode tests**

Add tests in `TemplateConvexCommandRequestTests.swift`:

```swift
func testReflectionPromptDecodesSharedFixture() throws {
    let json = try PublicActionContractFixture.load()
        .requiredQuery(TemplateBackendEndpoints.listReflections)
        .successData()

    let prompts = try JSONDecoder().decode([TemplateReflectionPrompt].self, from: json)

    XCTAssertEqual(prompts.first?.question, "What kept coming back?")
    XCTAssertEqual(prompts.first?.status, .open)
}
```

Expected now: FAIL because endpoint/type do not exist.

- [ ] **Step 3: Add Swift DTOs and endpoints**

Add:

```swift
struct TemplateReflectionPrompt: Decodable, Equatable, Identifiable {
    enum Status: String, Decodable, Equatable {
        case open
        case answered
    }

    let id: String
    let question: String
    let status: Status
    let createdAt: Double
}
```

Add endpoints:

```swift
static let listReflections = "reflections:listLatest"
static let generateReflections = "reflections:generateNow"
static let updateEntry = "entries:updateEntry"
```

Extend `TemplateCommandServicing` with `listReflections()`, `generateReflections()`, and `updateEntry(id:body:)`.

- [ ] **Step 4: Add model state tests**

Add tests in `VoiceAgentTemplateModelTests.swift`:

```swift
func testLaunchFixtureShowsJournalHomeState() {
    let model = VoiceAgentTemplateModel(
        sessionService: StubSessionService(result: .success(TemplateSession(ownerKey: "test|owner"))),
        commandService: StubCommandService(),
        voiceCapture: StubVoiceCapture(),
        analytics: TemplateProductAnalytics(configuration: nil),
        sentryScope: TemplateSentryUserScope(),
        launchArguments: ["--journal-home"]
    )

    XCTAssertTrue(model.isSignedIn)
    XCTAssertEqual(model.screen, .home)
    XCTAssertFalse(model.homeReflectionPrompts.isEmpty)
}

func testReflectionPromptStartsPromptLinkedVoiceDump() async {
    let commandService = StubCommandService()
    commandService.transcriptionResult = TemplateVoiceTranscriptionResult(transcript: "I keep thinking about focus")
    commandService.submitResult = TemplateCommandResult(
        summary: "Saved entry.",
        operations: [.createEntry(body: "I keep thinking about focus")],
        entries: [TemplateAppliedEntry(body: "I keep thinking about focus", source: .voice)]
    )
    let voiceCapture = StubVoiceCapture(audio: TemplateVoiceAudio(audioBase64: "dGVzdA==", mimeType: "audio/m4a"))
    let model = VoiceAgentTemplateModel(
        sessionService: StubSessionService(result: .success(TemplateSession(ownerKey: "test|owner"))),
        commandService: commandService,
        voiceCapture: voiceCapture,
        analytics: TemplateProductAnalytics(configuration: nil),
        sentryScope: TemplateSentryUserScope(),
        launchArguments: ["--journal-home"]
    )

    await model.startVoiceDump(from: TemplateReflectionPrompt.fixture)

    XCTAssertEqual(commandService.submittedCommands.first?.source, .voice)
    XCTAssertEqual(model.entries.first?.body, "I keep thinking about focus")
}
```

Expected now: FAIL because `screen`, `homeReflectionPrompts`, and prompt-linked voice APIs do not exist.

- [ ] **Step 5: Implement model state**

Add a screen enum and state:

```swift
enum JournalScreen: Equatable {
    case home
    case brainDump(prompt: TemplateReflectionPrompt?)
    case entryEditor(Entry)
}
```

Add `@Published var screen: JournalScreen = .home` and `@Published var homeReflectionPrompts: [TemplateReflectionPrompt] = []`. Add `openBrainDump()`, `openBrainDump(prompt:)`, `loadHome()`, and `startVoiceDump(from:)` methods. Keep existing `startVoiceCommand` internally if useful, but expose product-named methods for the new UI.

- [ ] **Step 6: Run Swift focused tests**

Run:

```sh
xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16' -only-testing:VoiceAgentTemplateTests/VoiceAgentTemplateModelTests
```

Expected: PASS or exact simulator blocker recorded.

### Task 4: SwiftUI Home And Brain Dump Screens

**Files:**

- Modify `ios/App/VoiceAgentRootView.swift`
- Create `ios/Features/Home/RitualHomeView.swift`
- Create `ios/Features/Capture/BrainDumpView.swift`
- Create `ios/Features/Capture/WatercolorBackgroundView.swift`
- Create `ios/Features/Reflections/ReflectionPromptBubble.swift`
- Create `ios/Features/Entries/EntryEditorView.swift`
- Modify `ios/Core/TemplateAccessibility.swift`
- Modify `VoiceAgentTemplate.xcodeproj/project.pbxproj`
- Optionally add `ios/Resources/watercolor-bg.png`

- [ ] **Step 1: Add accessibility IDs**

Add:

```swift
static let homeBrainDumpCard = "journal.home.brain-dump-card"
static let homeReflectionPrompt = "journal.home.reflection-prompt"
static let brainDumpStartVoice = "journal.brain-dump.voice.start"
static let brainDumpWaveform = "journal.brain-dump.waveform"
static let entryEditBody = "journal.entry-edit.body"
static let entryEditSave = "journal.entry-edit.save"
```

- [ ] **Step 2: Create watercolor background**

For the first prototype, implement `WatercolorBackgroundView` as SwiftUI-native so the app builds before resource wiring:

```swift
struct WatercolorBackgroundView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.98, green: 0.95, blue: 0.87), Color(red: 0.86, green: 0.93, blue: 0.91)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle().fill(.green.opacity(0.18)).blur(radius: 34).offset(x: -140, y: -240)
            Circle().fill(.cyan.opacity(0.16)).blur(radius: 38).offset(x: 150, y: 160)
            Circle().fill(.orange.opacity(0.13)).blur(radius: 42).offset(x: 120, y: -270)
            Rectangle().fill(.white.opacity(0.16))
        }
        .ignoresSafeArea()
    }
}
```

If using the PNG immediately, copy `.superpowers/brainstorm/78983-1780373100/content/watercolor-bg.png` to `ios/Resources/watercolor-bg.png`, add it to the app resources build phase, and render with `Image("watercolor-bg").resizable().scaledToFill().ignoresSafeArea()`.

- [ ] **Step 3: Build RitualHomeView**

Home should show:

- title "Today";
- a watercolor Brain Dump card with "Tell me about it.";
- reflection prompt cards from `model.homeReflectionPrompts`;
- recent entries or recent thread copy from fixture state;
- no microphone button.

The Brain Dump card button calls `model.openBrainDump()`.

- [ ] **Step 4: Build BrainDumpView**

Brain Dump should show:

- watercolor background;
- prompt text from selected reflection or default "How did your day go? Tell me about it.";
- static waveform bars for idle/prototype;
- one microphone button calling `model.startVoiceDump(from: prompt)`;
- no text field on the main surface.

- [ ] **Step 5: Wire root navigation**

In `VoiceAgentRootView`, signed-in state should switch over `model.screen`:

```swift
switch model.screen {
case .home:
    RitualHomeView(model: model)
case .brainDump(let prompt):
    BrainDumpView(model: model, prompt: prompt)
case .entryEditor(let entry):
    EntryEditorView(model: model, entry: entry)
}
```

Keep Settings available through a small top-right button on Home.

- [ ] **Step 6: Add fixture launch states**

Update `applyLaunchFixture`:

- `--journal-home`: signed in, Home screen, sample reflection prompts and recent entries.
- `--journal-brain-dump`: signed in, Brain Dump screen, no reflections visible.
- `--journal-reflections`: signed in, Home screen with multiple reflection prompts.

- [ ] **Step 7: Run iOS build/tests**

Run:

```sh
xcodebuild build -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
```

Expected: PASS or exact simulator blocker recorded.

### Task 5: Manual Entry Edit

**Files:**

- Modify `convex/entries.ts`
- Modify `convex/lib/apply.ts`
- Modify `convex/commandExecution.test.ts` or create `convex/entries.test.ts`
- Modify `ios/Features/Entries/EntryEditorView.swift`
- Modify `ios/App/VoiceAgentTemplateModel.swift`
- Modify `ios/Tests/VoiceAgentTemplateModelTests.swift`

- [ ] **Step 1: Add failing backend edit test**

Create a test that saves an entry, edits it, and verifies only public DTOs are returned:

```ts
it("updates an owned entry body through the apply layer", async () => {
  const t = convexTest(schema, modules).withIdentity(identity);
  await t.action(api.commands.submitCommand, {
    text: "Original private thought",
    source: "voice",
  });
  const entries = await t.query(api.entries.listEntries, {});

  const updated = await t.mutation(api.entries.updateEntry, {
    id: entries[0].id,
    body: "Edited private thought",
  });

  expect(updated).toEqual({ id: entries[0].id, body: "Edited private thought", source: "voice" });
});
```

This requires `listEntries` to return a public `id`. Update existing DTO tests accordingly.

- [ ] **Step 2: Implement update through apply layer**

Add an internal mutation in `convex/lib/apply.ts` that checks owner ownership before patching. Expose a public `entries.updateEntry` mutation that calls this internal apply mutation after `requireOwnerKey(ctx)`.

- [ ] **Step 3: Add Swift editor behavior**

`EntryEditorView` should show a `TextEditor`, Save button, and Cancel/Back. `VoiceAgentTemplateModel.saveEntryEdit(id:body:)` calls the backend, patches local `entries`, and returns Home.

- [ ] **Step 4: Run focused verification**

Run:

```sh
npx vitest run convex/entries.test.ts convex/commandExecution.test.ts
xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16' -only-testing:VoiceAgentTemplateTests/VoiceAgentTemplateModelTests
```

Expected: PASS or exact simulator blocker recorded.

### Task 6: Visual Evidence And Prototype Polish

**Files:**

- Modify `.context/` evidence only, not tracked app code unless screenshots reveal bugs.
- Optionally modify SwiftUI view files for spacing/contrast fixes discovered by screenshots.

- [ ] **Step 1: Build for simulator**

Run:

```sh
xcodebuild build -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
```

- [ ] **Step 2: Capture Home, Brain Dump, and Reflections screenshots**

Run the visual evidence commands from the verification section. Save screenshots to:

- `.context/journal-home.png`
- `.context/journal-brain-dump.png`
- `.context/journal-reflections.png`

- [ ] **Step 3: Inspect screenshots**

Check:

- Home has no microphone control.
- Brain Dump has one microphone control.
- Watercolor background is visible and not dark green.
- Text contrast is readable.
- Reflection cards do not overlap.
- The UI still fits on iPhone 16 dimensions.

- [ ] **Step 4: Full verification**

Run:

```sh
npx vitest run convex
npx tsc -p convex/tsconfig.json
xcodebuild build -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
xcodebuild test -project VoiceAgentTemplate.xcodeproj -scheme VoiceAgentTemplate -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
```

Expected: PASS, except live checks requiring credentials may remain explicitly blocked.

## Delivery Map

### Node 1

- `id`: `backend-brain-dump`
- `mode`: `tdd`
- `status`: `completed`
- `owner_type`: `agent`
- `executor`: `execute-work + tdd + convex-voice-agent`
- `planned_write_scope`: `convex/lib/commandInterpreter.ts`, `convex/lib/operations.ts`, `convex/lib/apply.ts`, `convex/commands.ts`, `convex/commandExecution.test.ts`, `tests/fixtures/public-actions.json`
- `actual_write_scope`: `convex/lib/commandInterpreter.ts`, `convex/commandExecution.test.ts` (no changes needed to `operations.ts`, `apply.ts`, `commands.ts`, or `public-actions.json` for this slice)
- `depends_on`: []
- `unblocks`: [`backend-reflections`, `swift-contracts`]
- `required_gates`: `npx vitest run convex/commandExecution.test.ts`; `npx tsc -p convex/tsconfig.json`
- `gate_evidence`: `npx vitest run convex/commandExecution.test.ts` — 5 passed (2026-06-01); `npx tsc -p convex/tsconfig.json` — exit 0
- `human_gates`: none
- `notes`: `convex/_generated/ai/guidelines.md` reviewed; plain transcripts default to `create_entry`; empty/whitespace rejects with `EMPTY_COMMAND`
- `next`: Node 2

### Node 2

- `id`: `backend-reflections`
- `mode`: `tdd`
- `status`: `completed`
- `owner_type`: `agent`
- `executor`: `execute-work + tdd + convex-voice-agent`
- `planned_write_scope`: `convex/schema.ts`, `convex/reflections.ts`, `convex/lib/reflectionGenerator.ts`, `convex/crons.ts`, `convex/lib/apply.ts`, `convex/account.ts`, `convex/lib/accountDeletionContract.ts`, `convex/reflections.test.ts`, `convex/account.test.ts`, `tests/fixtures/public-actions.json`
- `depends_on`: [`backend-brain-dump`]
- `unblocks`: [`swift-contracts`]
- `required_gates`: `npx vitest run convex/reflections.test.ts convex/account.test.ts`; `npx vitest run convex`; `npx tsc -p convex/tsconfig.json`; `npx convex codegen`
- `human_gates`: live provider verification needs `GROQ_API_KEY`
- `gate_evidence`: `npx vitest run convex` — 23 passed (2026-06-01); `npx tsc -p convex/tsconfig.json` — exit 0; `npx convex codegen` — exit 0
- `notes`: no transcript or prompt text in analytics; model provider receives entry bodies only for reflection generation; live Groq verification deferred without `GROQ_API_KEY`
- `next`: Node 3

### Node 3

- `id`: `swift-contracts`
- `mode`: `tdd`
- `status`: `completed`
- `owner_type`: `agent`
- `executor`: `execute-work + tdd + ios-voice-template`
- `planned_write_scope`: `ios/Core/TemplateBackendContract.swift`, `ios/Core/TemplateBackendClient.swift`, `ios/Core/TemplateAccessibility.swift`, `ios/App/VoiceAgentTemplateModel.swift`, `ios/Tests/TemplateBackendClientTests.swift`, `ios/Tests/TemplateConvexCommandRequestTests.swift`, `ios/Tests/VoiceAgentTemplateModelTests.swift`
- `depends_on`: [`backend-brain-dump`, `backend-reflections`]
- `unblocks`: [`swiftui-screens`, `entry-edit`]
- `required_gates`: focused XCTest commands for backend client and model tests
- `human_gates`: none
- `gate_evidence`: `xcodebuild test` — 33 passed (2026-06-01)
- `notes`: keep public action/query names synchronized with `tests/fixtures/public-actions.json`
- `next`: Node 4

### Node 4

- `id`: `swiftui-screens`
- `mode`: `tdd`
- `status`: `completed`
- `owner_type`: `agent`
- `executor`: `execute-work + ios-voice-template`
- `planned_write_scope`: `ios/App/VoiceAgentRootView.swift`, `ios/Features/Home/RitualHomeView.swift`, `ios/Features/Capture/BrainDumpView.swift`, `ios/Features/Capture/WatercolorBackgroundView.swift`, `ios/Features/Reflections/ReflectionPromptBubble.swift`, `ios/Core/TemplateAccessibility.swift`, `VoiceAgentTemplate.xcodeproj/project.pbxproj`, optional `ios/Resources/watercolor-bg.png`
- `depends_on`: [`swift-contracts`]
- `unblocks`: [`entry-edit`, `visual-evidence`]
- `required_gates`: iOS build and model tests
- `human_gates`: design review of screenshots
- `gate_evidence`: `xcodebuild build` — succeeded (2026-06-01)
- `notes`: Home has no mic control; Brain Dump has one primary mic control; SwiftUI watercolor background (no PNG wiring in this slice)
- `next`: Node 5

### Node 5

- `id`: `entry-edit`
- `mode`: `tdd`
- `status`: `completed`
- `owner_type`: `agent`
- `executor`: `execute-work + tdd + convex-voice-agent + ios-voice-template`
- `planned_write_scope`: `convex/entries.ts`, `convex/lib/apply.ts`, `convex/entries.test.ts`, `ios/Features/Entries/EntryEditorView.swift`, `ios/App/VoiceAgentTemplateModel.swift`, `ios/Tests/VoiceAgentTemplateModelTests.swift`
- `depends_on`: [`swift-contracts`]
- `unblocks`: [`visual-evidence`]
- `required_gates`: focused backend entry tests; focused model tests
- `human_gates`: none
- `gate_evidence`: `npx vitest run convex/entries.test.ts` — passed; model tests — passed
- `notes`: manual edits are user-authored writes but still use authenticated owner checks and the apply layer
- `next`: Node 6

### Node 6

- `id`: `visual-evidence`
- `mode`: `verification`
- `status`: `completed`
- `owner_type`: `agent`
- `executor`: `execute-work + ios-voice-template`
- `planned_write_scope`: `.context/journal-home.png`, `.context/journal-brain-dump.png`, `.context/journal-reflections.png`; code fixes only if screenshots reveal defects
- `depends_on`: [`swiftui-screens`, `entry-edit`]
- `unblocks`: [`ship-work`]
- `required_gates`: full backend tests, Convex typecheck, iOS build/test, simulator screenshots
- `human_gates`: user design acceptance of screenshots
- `gate_evidence`: screenshots at `.context/journal-home.png`, `.context/journal-brain-dump.png`, `.context/journal-reflections.png` (2026-06-01); full `npx vitest run convex` + iOS build/test green
- `notes`: Home card text is low-contrast on watercolor (white on light) — acceptable for prototype; human design acceptance still open
- `next`: `ship-work` after a PR is desired

## Safe Concurrency

- Node 1 and Node 2 should be sequential because Node 2 depends on final entry semantics and schema.
- Node 3 can start after the public DTO shapes from Node 2 are stable.
- Node 4 and Node 5 can run partly in parallel after Node 3 if write scopes remain separate: one worker owns view files, one owns entry edit backend/model. Coordinate `VoiceAgentTemplateModel.swift` edits carefully.
- Node 6 must run after UI and edit behavior are integrated.

## Documentation Impact

- Update `CONTEXT.md` from template text to the private voice journal product contract before shipping beyond prototype.
- Update `BRAND.md` with calm journal language and privacy boundaries.
- Update `docs/architecture.md` with reflection tables, cron flow, and model-provider reflection boundary.
- Update `docs/deployment.md` with reflection model env var if `GROQ_REFLECTION_MODEL` remains configurable.
- Add a learning if simulator screenshot setup or Convex cron testing has non-obvious caveats.

## Linear Updates

No Linear issue was selected or updated. If this becomes tracked work, create an issue for "Voice journal working prototype" and attach this plan path.

## Next Skill

Use `.agents/skills/execute-work` to execute the Delivery Map. Within implementation nodes, use `.agents/skills/tdd`, `.agents/skills/convex-voice-agent`, and `.agents/skills/ios-voice-template` as called out above.

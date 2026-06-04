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
    expect(generated.prompts.map((p: { question: string }) => p.question)).toEqual([
      "What kept coming back?",
      "Where was there energy?",
      "Say the unpolished version.",
    ]);

    const latest = await t.query(api.reflections.listLatest, {});
    expect(latest).toEqual(generated.prompts);
    expect(latest[0]).not.toHaveProperty("ownerKey");
  });
});

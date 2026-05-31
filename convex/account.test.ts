/// <reference types="vite/client" />
// @vitest-environment edge-runtime

import { convexTest, type TestConvex } from "convex-test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");

type AccountTestConvex = TestConvex<typeof schema>;

const identity = {
  issuer: "test",
  subject: "user-1",
  tokenIdentifier: "test|user-1",
};

const LARGE_ACCOUNT_ROW_COUNT = 1001;

async function seedLargeOwnedEntryVolume(
  t: Pick<AccountTestConvex, "mutation">,
  ownerKey: string,
  rowCount: number,
) {
  const chunkSize = 200;
  for (let start = 0; start < rowCount; start += chunkSize) {
    await t.mutation(async (ctx) => {
      const end = Math.min(start + chunkSize, rowCount);
      for (let index = start; index < end; index += 1) {
        const timestamp = Date.now() + index;
        await ctx.db.insert("entries", {
          ownerKey,
          body: `entry ${index}`,
          source: "typed",
          createdAt: timestamp,
          updatedAt: timestamp,
        });
        await ctx.db.insert("commandHistory", {
          ownerKey,
          source: "typed",
          transcript: `entry ${index}`,
          status: "applied",
          summary: `entry ${index}`,
          createdAt: timestamp,
        });
        await ctx.db.insert("usageEvents", {
          ownerKey,
          eventName: "command_applied",
          createdAt: timestamp,
        });
      }
    });
  }
}

describe("starter account lifecycle", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("deletes owner data and runs cleanup hooks without live vendor credentials", async () => {
    const t = convexTest(schema, modules).withIdentity(identity);

    await t.action(api.commands.submitCommand, {
      text: "Create a note saying hello",
      source: "typed",
    });
    await t.action(api.commands.recordAppleSignInAuthorization, {
      clientId: "com.example.voiceagent",
      refreshToken: "test-refresh-token",
    });

    const response = await t.action(api.commands.deleteAccount, {});

    expect(response).toMatchObject({
      status: "deleted",
      deleted: {
        entries: 1,
        commandHistory: 1,
        appleSignInCredentials: 1,
      },
      cleanup: {
        posthog: { status: "skipped" },
        sentry: { status: "skipped" },
      },
    });
    await expect(t.query(api.entries.listEntries, {})).resolves.toEqual([]);
  });

  it("deletes all owner entries, command history, and usage events beyond one query page", async () => {
    const t = convexTest(schema, modules).withIdentity(identity);

    for (let index = 0; index < 105; index += 1) {
      await t.action(api.commands.submitCommand, {
        text: `Create a note saying entry ${index}`,
        source: "typed",
      });
    }

    const response = await t.action(api.commands.deleteAccount, {});

    expect(response).toMatchObject({
      status: "deleted",
      batches: 3,
      deleted: {
        entries: 105,
        commandHistory: 105,
        usageEvents: 105,
      },
    });
    await expect(t.query(api.entries.listEntries, {})).resolves.toEqual([]);
  });

  it("returns deletion_in_progress for large accounts instead of batch limit errors", async () => {
    const t = convexTest(schema, modules).withIdentity(identity);
    await seedLargeOwnedEntryVolume(t, identity.tokenIdentifier, LARGE_ACCOUNT_ROW_COUNT);

    const response = await t.action(api.commands.deleteAccount, {});

    expect(response).toMatchObject({
      status: "deletion_in_progress",
      jobStatus: "deleting",
      deleted: {
        entries: 1000,
        commandHistory: 1000,
        usageEvents: 1000,
      },
      batches: 20,
    });
    await expect(t.query(api.entries.listEntries, {})).resolves.not.toEqual([]);
  });

  it("drains owned rows through scheduled continuation", async () => {
    vi.useFakeTimers();
    const t = convexTest(schema, modules).withIdentity(identity);
    await seedLargeOwnedEntryVolume(t, identity.tokenIdentifier, LARGE_ACCOUNT_ROW_COUNT);

    const firstResponse = await t.action(api.commands.deleteAccount, {});
    expect(firstResponse.status).toBe("deletion_in_progress");

    await t.finishAllScheduledFunctions(() => {
      vi.runAllTimers();
    });
    vi.useRealTimers();

    await expect(t.query(api.entries.listEntries, {})).resolves.toEqual([]);
    const jobs = await t.run(async (ctx) => {
      return await ctx.db
        .query("accountDeletionJobs")
        .withIndex("by_ownerKey", (q) => q.eq("ownerKey", identity.tokenIdentifier))
        .collect();
    });
    expect(jobs).toHaveLength(1);
    expect(jobs[0]?.status).toBe("deleted");
    expect(jobs[0]?.deleted.entries).toBe(LARGE_ACCOUNT_ROW_COUNT);
  });

  it("does not call vendor cleanup until owned rows are gone", async () => {
    vi.useFakeTimers();
    const fetchSpy = vi.fn(async () => new Response(null, { status: 204 }));
    vi.stubGlobal("fetch", fetchSpy);
    vi.stubGlobal("process", {
      env: {
        POSTHOG_HOST: "https://eu.posthog.com/",
        POSTHOG_PROJECT_ID: "12345",
        POSTHOG_PERSONAL_API_KEY: "test-posthog-key",
        SENTRY_AUTH_TOKEN: "test-sentry-token",
        SENTRY_ORG_SLUG: "example-org",
        SENTRY_PROJECT_SLUG: "voice-agent",
      },
    });

    const t = convexTest(schema, modules).withIdentity(identity);
    await seedLargeOwnedEntryVolume(t, identity.tokenIdentifier, LARGE_ACCOUNT_ROW_COUNT);

    await t.action(api.commands.deleteAccount, {});
    expect(fetchSpy).not.toHaveBeenCalled();

    await t.finishAllScheduledFunctions(() => {
      vi.runAllTimers();
    });
    vi.useRealTimers();

    expect(fetchSpy).toHaveBeenCalledTimes(2);
    await expect(t.query(api.entries.listEntries, {})).resolves.toEqual([]);
  });

  it("is idempotent while deletion is in progress and after completion", async () => {
    vi.useFakeTimers();
    const t = convexTest(schema, modules).withIdentity(identity);
    await seedLargeOwnedEntryVolume(t, identity.tokenIdentifier, LARGE_ACCOUNT_ROW_COUNT);

    const first = await t.action(api.commands.deleteAccount, {});
    const second = await t.action(api.commands.deleteAccount, {});

    expect(first.status).toBe("deletion_in_progress");
    expect(second).toMatchObject({
      status: "deletion_in_progress",
      batches: first.batches,
      deleted: first.deleted,
    });

    await t.finishAllScheduledFunctions(() => {
      vi.runAllTimers();
    });
    vi.useRealTimers();

    const completed = await t.action(api.commands.deleteAccount, {});
    expect(completed).toMatchObject({
      status: "deleted",
      deleted: {
        entries: LARGE_ACCOUNT_ROW_COUNT,
        commandHistory: LARGE_ACCOUNT_ROW_COUNT,
        usageEvents: LARGE_ACCOUNT_ROW_COUNT,
      },
      cleanup: {
        posthog: { status: "skipped" },
        sentry: { status: "skipped" },
      },
    });

    const jobs = await t.run(async (ctx) => {
      return await ctx.db
        .query("accountDeletionJobs")
        .withIndex("by_ownerKey", (q) => q.eq("ownerKey", identity.tokenIdentifier))
        .collect();
    });
    expect(jobs).toHaveLength(1);
  });

  it("reports Sentry account cleanup without claiming user deletion", async () => {
    vi.stubGlobal("process", {
      env: {
        SENTRY_AUTH_TOKEN: "test-sentry-token",
        SENTRY_ORG_SLUG: "example-org",
        SENTRY_PROJECT_SLUG: "voice-agent",
      },
    });
    const fetchSpy = vi.fn(async () => new Response(null, { status: 202 }));
    vi.stubGlobal("fetch", fetchSpy);

    const t = convexTest(schema, modules).withIdentity(identity);

    const response = await t.action(api.commands.deleteAccount, {});

    expect(response.status).toBe("deleted");
    if (response.status !== "deleted") {
      throw new Error("expected deleted response");
    }
    expect(response.cleanup.sentry).toEqual({ status: "reported" });
    expect(JSON.stringify(fetchSpy.mock.calls)).not.toContain("delete");
  });

  it("requests PostHog person deletion with the owner key and configured host", async () => {
    vi.stubGlobal("process", {
      env: {
        POSTHOG_HOST: "https://eu.posthog.com/",
        POSTHOG_PROJECT_ID: "12345",
        POSTHOG_PERSONAL_API_KEY: "test-posthog-key",
      },
    });
    const fetchSpy = vi.fn(async () => new Response(null, { status: 204 }));
    vi.stubGlobal("fetch", fetchSpy);

    const t = convexTest(schema, modules).withIdentity(identity);

    const response = await t.action(api.commands.deleteAccount, {});

    expect(response.status).toBe("deleted");
    if (response.status !== "deleted") {
      throw new Error("expected deleted response");
    }
    expect(response.cleanup.posthog).toEqual({ status: "requested" });
    expect(fetchSpy).toHaveBeenCalledWith(
      "https://eu.posthog.com/api/projects/12345/persons/bulk_delete/",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({
          distinct_ids: [identity.tokenIdentifier],
          delete_events: true,
        }),
      }),
    );
  });
});

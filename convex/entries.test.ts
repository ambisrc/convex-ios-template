/// <reference types="vite/client" />
// @vitest-environment edge-runtime

import { convexTest } from "convex-test";
import { describe, expect, it } from "vitest";
import { api } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");

const identity = {
  issuer: "test",
  subject: "user-1",
  tokenIdentifier: "test|user-1",
};

const otherIdentity = {
  issuer: "test",
  subject: "user-2",
  tokenIdentifier: "test|user-2",
};

describe("entries", () => {
  it("lists public entry DTOs with stable IDs", async () => {
    const t = convexTest(schema, modules).withIdentity(identity);
    await t.action(api.commands.submitCommand, {
      text: "Create a note saying hello",
      source: "typed",
    });

    const entries = await t.query(api.entries.listEntries, {});

    expect(entries).toHaveLength(1);
    expect(entries[0]).toMatchObject({
      body: "hello",
      source: "typed",
    });
    expect(entries[0]?.id).toEqual(expect.any(String));
    expect(entries[0]).not.toHaveProperty("_id");
    expect(entries[0]).not.toHaveProperty("ownerKey");
  });

  it("updates an owned entry body through the apply layer", async () => {
    const t = convexTest(schema, modules).withIdentity(identity);
    await t.action(api.commands.submitCommand, {
      text: "Create a note saying original",
      source: "voice",
    });
    const [entry] = await t.query(api.entries.listEntries, {});

    const updated = await t.mutation(api.entries.updateEntry, {
      id: entry.id as Id<"entries">,
      body: " edited ",
    });

    expect(updated).toEqual({
      id: entry.id,
      body: "edited",
      source: "voice",
    });
    await expect(t.query(api.entries.listEntries, {})).resolves.toEqual([updated]);
  });

  it("does not allow another owner to update an entry", async () => {
    const base = convexTest(schema, modules);
    const t = base.withIdentity(identity);
    await t.action(api.commands.submitCommand, {
      text: "Create a note saying private",
      source: "typed",
    });
    const [entry] = await t.query(api.entries.listEntries, {});

    const otherUser = base.withIdentity(otherIdentity);
    await expect(
      otherUser.mutation(api.entries.updateEntry, {
        id: entry.id as Id<"entries">,
        body: "stolen",
      }),
    ).rejects.toThrow("ENTRY_NOT_FOUND");

    await expect(t.query(api.entries.listEntries, {})).resolves.toEqual([entry]);
  });
});

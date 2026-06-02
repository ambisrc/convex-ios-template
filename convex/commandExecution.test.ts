/// <reference types="vite/client" />
// @vitest-environment edge-runtime

import { convexTest } from "convex-test";
import { describe, expect, it } from "vitest";
import { api } from "./_generated/api";
import publicActions from "../tests/fixtures/public-actions.json";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");

const identity = {
  issuer: "test",
  subject: "user-1",
  tokenIdentifier: "test|user-1",
};

describe("starter command execution", () => {
  it("applies a typed command through the public action and persists an entry for the authenticated owner", async () => {
    const t = convexTest(schema, modules).withIdentity(identity);
    const contract = publicActions.actions["commands:submitCommand"];
    const request = {
      ...contract.request,
      source: contract.request.source as "typed" | "voice",
    };

    const response = await t.action(api.commands.submitCommand, request);

    expect(response).toMatchObject({
      status: contract.success.status,
      summary: contract.success.summary,
      operations: contract.success.operations,
    });
    expect(response.entries).toHaveLength(1);
    expect(response.entries[0]).toMatchObject({
      body: contract.success.entries[0]?.body,
      source: contract.success.entries[0]?.source,
    });
    expect(response.entries[0]?.id).toEqual(expect.any(String));
    expect(response).not.toHaveProperty("entryIds");

    const entries = await t.query(api.entries.listEntries, {});
    expect(entries).toEqual(response.entries);
    expect(entries[0]).not.toHaveProperty("_id");
    expect(entries[0]).not.toHaveProperty("ownerKey");
  });

  it("listEntries returns exact public DTOs without Convex document fields", async () => {
    const t = convexTest(schema, modules).withIdentity(identity);
    const contract = publicActions.queries["entries:listEntries"];

    await t.action(api.commands.submitCommand, {
      text: "Create a note saying hello",
      source: "typed",
    });

    const entries = await t.query(api.entries.listEntries, {});

    expect(entries).toHaveLength(1);
    expect(entries[0]).toMatchObject({
      body: contract.success[0]?.body,
      source: contract.success[0]?.source,
    });
    expect(entries[0]?.id).toEqual(expect.any(String));
    for (const entry of entries) {
      expect(entry).toEqual({ id: entry.id, body: entry.body, source: entry.source });
      expect(Object.keys(entry).sort()).toEqual(["body", "id", "source"]);
    }
  });

  it("rejects unauthenticated command submissions", async () => {
    const t = convexTest(schema, modules);

    await expect(
      t.action(api.commands.submitCommand, {
        text: "Create a note saying hello",
        source: "typed",
      }),
    ).rejects.toThrow("AUTH_REQUIRED");
  });

  it("rejects unsupported commands without partial writes", async () => {
    const t = convexTest(schema, modules).withIdentity(identity);

    await expect(
      t.action(api.commands.submitCommand, {
        text: "please reorganize everything",
        source: "typed",
      }),
    ).rejects.toThrow("UNSUPPORTED_COMMAND");

    await expect(t.query(api.entries.listEntries, {})).resolves.toEqual([]);
  });
});

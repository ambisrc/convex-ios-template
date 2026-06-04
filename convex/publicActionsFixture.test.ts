/// <reference types="vite/client" />

import { describe, expect, it } from "vitest";
import publicActions from "../tests/fixtures/public-actions.json";

describe("public Swift/Convex contract fixture", () => {
  it("covers the complete starter public endpoint surface", () => {
    expect(Object.keys(publicActions.actions).sort()).toEqual([
      "commands:deleteAccount",
      "commands:submitCommand",
      "commands:transcribeVoiceCommand",
      "reflections:generateNow",
    ]);
    expect(Object.keys(publicActions.queries).sort()).toEqual([
      "entries:listEntries",
      "reflections:listLatest",
    ]);
    expect(Object.keys(publicActions.mutations).sort()).toEqual(["entries:updateEntry"]);
  });

  it("keeps updateEntry as a public mutation DTO with stable id/body/source fields", () => {
    const mutation = publicActions.mutations["entries:updateEntry"];

    expect(Object.keys(mutation.request).sort()).toEqual(["body", "id"]);
    expect(Object.keys(mutation.success).sort()).toEqual(["body", "id", "source"]);
    expect(mutation.success).toEqual({
      id: mutation.request.id,
      body: mutation.request.body,
      source: "typed",
    });
  });
});

import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  profiles: defineTable({
    ownerKey: v.string(),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_ownerKey", ["ownerKey"]),

  entries: defineTable({
    ownerKey: v.string(),
    body: v.string(),
    source: v.union(v.literal("typed"), v.literal("voice")),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_ownerKey_and_createdAt", ["ownerKey", "createdAt"]),

  commandHistory: defineTable({
    ownerKey: v.string(),
    source: v.union(v.literal("typed"), v.literal("voice")),
    transcript: v.string(),
    status: v.union(v.literal("applied"), v.literal("rejected"), v.literal("failed")),
    summary: v.optional(v.string()),
    operations: v.optional(v.array(v.object({
      type: v.literal("create_entry"),
      body: v.string(),
    }))),
    errorCode: v.optional(v.string()),
    createdAt: v.number(),
  }).index("by_ownerKey_and_createdAt", ["ownerKey", "createdAt"]),

  appleSignInCredentials: defineTable({
    ownerKey: v.string(),
    clientId: v.string(),
    refreshToken: v.string(),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_ownerKey", ["ownerKey"]),

  usageEvents: defineTable({
    ownerKey: v.string(),
    eventName: v.string(),
    properties: v.optional(v.record(v.string(), v.union(v.string(), v.number(), v.boolean(), v.null()))),
    createdAt: v.number(),
  }).index("by_ownerKey_and_createdAt", ["ownerKey", "createdAt"]),

  accountDeletionJobs: defineTable({
    ownerKey: v.string(),
    status: v.union(
      v.literal("deleting"),
      v.literal("cleanup_pending"),
      v.literal("cleanup_running"),
      v.literal("deleted"),
      v.literal("failed"),
    ),
    deleted: v.object({
      profiles: v.number(),
      entries: v.number(),
      commandHistory: v.number(),
      appleSignInCredentials: v.number(),
      usageEvents: v.number(),
    }),
    batches: v.number(),
    cleanup: v.optional(v.object({
      posthog: v.union(
        v.object({ status: v.literal("skipped"), reason: v.literal("missing_config") }),
        v.object({ status: v.literal("requested") }),
      ),
      sentry: v.union(
        v.object({ status: v.literal("skipped"), reason: v.literal("missing_config") }),
        v.object({ status: v.literal("reported") }),
      ),
    })),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_ownerKey", ["ownerKey"]),
});

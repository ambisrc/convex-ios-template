import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import {
  accountDeletionCleanupValidator,
  accountDeletionJobStatusValidator,
  deleteCountsValidator,
} from "./lib/accountDeletionContract";

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
    promptId: v.optional(v.id("reflectionPrompts")),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_ownerKey_and_createdAt", ["ownerKey", "createdAt"]),

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
    status: accountDeletionJobStatusValidator,
    deleted: deleteCountsValidator,
    batches: v.number(),
    cleanup: v.optional(accountDeletionCleanupValidator),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_ownerKey", ["ownerKey"]),
});

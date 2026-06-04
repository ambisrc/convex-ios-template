import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import {
  action,
  internalAction,
  internalMutation,
  internalQuery,
  query,
} from "./_generated/server";
import { requireOwnerKey } from "./lib/auth";
import type { ReflectionPromptPublic } from "./lib/apply";
import { generateReflectionQuestions } from "./lib/reflectionGenerator";

const reflectionPromptPublicValidator = v.object({
  id: v.string(),
  question: v.string(),
  status: v.union(v.literal("open"), v.literal("answered")),
  createdAt: v.number(),
});

const generateNowResponseValidator = v.union(
  v.object({
    status: v.literal("generated"),
    prompts: v.array(reflectionPromptPublicValidator),
  }),
  v.object({
    status: v.literal("skipped"),
    reason: v.literal("no_new_entries"),
    prompts: v.array(reflectionPromptPublicValidator),
  }),
  v.object({
    status: v.literal("configuration_missing"),
    missing: v.literal("GROQ_API_KEY"),
    prompts: v.array(reflectionPromptPublicValidator),
  }),
);

export const listLatest = query({
  args: {},
  returns: v.array(reflectionPromptPublicValidator),
  handler: async (ctx): Promise<ReflectionPromptPublic[]> => {
    const ownerKey = await requireOwnerKey(ctx);
    const rows = await ctx.db
      .query("reflectionPrompts")
      .withIndex("by_ownerKey_and_createdAt", (q) => q.eq("ownerKey", ownerKey))
      .order("desc")
      .take(20);
    return rows
      .slice()
      .sort((left, right) => right.createdAt - left.createdAt || left._id.localeCompare(right._id))
      .map(toPublicPrompt);
  },
});

export const generateNow = action({
  args: {},
  returns: generateNowResponseValidator,
  handler: async (ctx): Promise<
    | { status: "generated"; prompts: ReflectionPromptPublic[] }
    | { status: "skipped"; reason: "no_new_entries"; prompts: ReflectionPromptPublic[] }
    | { status: "configuration_missing"; missing: "GROQ_API_KEY"; prompts: ReflectionPromptPublic[] }
  > => {
    const ownerKey = await requireOwnerKey(ctx);
    return await ctx.runAction(internal.reflections.generateForOwner, { ownerKey });
  },
});

export const getGenerationContext = internalQuery({
  args: {
    ownerKey: v.string(),
  },
  returns: v.object({
    entryBodies: v.array(v.string()),
    entryWindowStart: v.number(),
    entryWindowEnd: v.number(),
  }),
  handler: async (ctx, args) => {
    const latestRun = await ctx.db
      .query("reflectionRuns")
      .withIndex("by_ownerKey_and_createdAt", (q) => q.eq("ownerKey", args.ownerKey))
      .order("desc")
      .first();

    const windowStart = latestRun?.entryWindowEnd ?? 0;
    const entries = await ctx.db
      .query("entries")
      .withIndex("by_ownerKey_and_createdAt", (q) => q.eq("ownerKey", args.ownerKey))
      .order("desc")
      .collect();

    const newEntries = entries.filter((entry) => entry.createdAt > windowStart);
    const entryWindowEnd = newEntries.reduce(
      (max, entry) => Math.max(max, entry.createdAt),
      windowStart,
    );

    return {
      entryBodies: newEntries.map((entry) => entry.body),
      entryWindowStart: windowStart,
      entryWindowEnd,
    };
  },
});

export const generateForOwner = internalAction({
  args: {
    ownerKey: v.string(),
  },
  returns: generateNowResponseValidator,
  handler: async (ctx, args) => {
    const context = await ctx.runQuery(internal.reflections.getGenerationContext, {
      ownerKey: args.ownerKey,
    });

    if (context.entryBodies.length === 0) {
      await ctx.runMutation(internal.lib.apply.recordSkippedReflectionRun, {
        ownerKey: args.ownerKey,
        entryWindowStart: context.entryWindowStart,
        entryWindowEnd: context.entryWindowEnd,
      });
      return {
        status: "skipped" as const,
        reason: "no_new_entries" as const,
        prompts: [],
      };
    }

    const result = await generateReflectionQuestions(context.entryBodies);
    if (result.status === "configuration_missing") {
      return {
        status: "configuration_missing" as const,
        missing: result.missing,
        prompts: [],
      };
    }

    const prompts: ReflectionPromptPublic[] = await ctx.runMutation(
      internal.lib.apply.persistReflectionGeneration,
      {
        ownerKey: args.ownerKey,
        entryWindowStart: context.entryWindowStart,
        entryWindowEnd: context.entryWindowEnd,
        questions: result.questions,
      },
    );

    return {
      status: "generated" as const,
      prompts,
    };
  },
});

export const generateDailyForActiveProfiles = internalMutation({
  args: {},
  handler: async (ctx) => {
    const profiles = await ctx.db.query("profiles").take(25);
    for (const profile of profiles) {
      const recentEntry = await ctx.db
        .query("entries")
        .withIndex("by_ownerKey_and_createdAt", (q) => q.eq("ownerKey", profile.ownerKey))
        .order("desc")
        .first();
      if (!recentEntry) {
        continue;
      }
      const oneDayAgo = Date.now() - 24 * 60 * 60 * 1000;
      if (recentEntry.createdAt < oneDayAgo) {
        continue;
      }
      await ctx.scheduler.runAfter(0, internal.reflections.generateForOwner, {
        ownerKey: profile.ownerKey,
      });
    }
  },
});

function toPublicPrompt(row: Doc<"reflectionPrompts">): ReflectionPromptPublic {
  return {
    id: row._id,
    question: row.question,
    status: row.status,
    createdAt: row.createdAt,
  };
}

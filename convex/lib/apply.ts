import { v } from "convex/values";
import type { Id } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";
import { internalMutation } from "../_generated/server";
import { commandSourceValidator, operationValidator, type CommandSource } from "./operations";

export type AppliedEntry = {
  id: Id<"entries">;
  body: string;
  source: CommandSource;
};

export type ApplyCommandResult = {
  commandId: string;
  entryIds: string[];
  entries: AppliedEntry[];
};

export type ReflectionPromptPublic = {
  id: string;
  question: string;
  status: "open" | "answered";
  createdAt: number;
};

export const applyCommand = internalMutation({
  args: {
    ownerKey: v.string(),
    transcript: v.string(),
    source: commandSourceValidator,
    operations: v.array(operationValidator),
    summary: v.string(),
    promptId: v.optional(v.id("reflectionPrompts")),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    await ensureProfile(ctx, args.ownerKey, now);

    const commandId = await ctx.db.insert("commandHistory", {
      ownerKey: args.ownerKey,
      source: args.source,
      transcript: args.transcript,
      status: "applied",
      summary: args.summary,
      operations: args.operations,
      createdAt: now,
    });

    const entryIds: string[] = [];
    const entries: AppliedEntry[] = [];
    for (const operation of args.operations) {
      if (operation.type !== "create_entry") {
        throw new Error("UNSUPPORTED_OPERATION");
      }
      const entryId = await ctx.db.insert("entries", {
        ownerKey: args.ownerKey,
        body: operation.body,
        source: args.source,
        promptId: args.promptId,
        createdAt: now,
        updatedAt: now,
      });
      entryIds.push(entryId);
      entries.push({
        id: entryId,
        body: operation.body,
        source: args.source,
      });

      if (args.promptId) {
        await markReflectionPromptAnswered(ctx, {
          ownerKey: args.ownerKey,
          promptId: args.promptId,
          entryId,
          now,
        });
      }
    }

    await ctx.db.insert("usageEvents", {
      ownerKey: args.ownerKey,
      eventName: "command.applied",
      properties: {
        source: args.source,
        operationCount: args.operations.length,
      },
      createdAt: now,
    });

    return { commandId, entryIds, entries };
  },
});

export const updateEntryBody = internalMutation({
  args: {
    ownerKey: v.string(),
    entryId: v.id("entries"),
    body: v.string(),
  },
  handler: async (ctx, args): Promise<AppliedEntry> => {
    return await updateEntryBodyForOwner(ctx, args);
  },
});

export async function updateEntryBodyForOwner(
  ctx: MutationCtx,
  args: {
    ownerKey: string;
    entryId: Id<"entries">;
    body: string;
  },
): Promise<AppliedEntry> {
  const entry = await ctx.db.get(args.entryId);
  if (!entry || entry.ownerKey !== args.ownerKey) {
    throw new Error("ENTRY_NOT_FOUND");
  }

  const body = args.body.trim();
  if (!body) {
    throw new Error("EMPTY_ENTRY_BODY");
  }

  await ctx.db.patch(args.entryId, {
    body,
    updatedAt: Date.now(),
  });

  return {
    id: args.entryId,
    body,
    source: entry.source,
  };
}

export const persistReflectionGeneration = internalMutation({
  args: {
    ownerKey: v.string(),
    entryWindowStart: v.number(),
    entryWindowEnd: v.number(),
    questions: v.array(v.string()),
  },
  handler: async (ctx, args): Promise<ReflectionPromptPublic[]> => {
    const now = Date.now();
    await ensureProfile(ctx, args.ownerKey, now);

    const runId = await ctx.db.insert("reflectionRuns", {
      ownerKey: args.ownerKey,
      entryWindowStart: args.entryWindowStart,
      entryWindowEnd: args.entryWindowEnd,
      status: "generated",
      promptCount: args.questions.length,
      createdAt: now,
    });

    const prompts: ReflectionPromptPublic[] = [];
    for (const question of args.questions) {
      const promptId = await ctx.db.insert("reflectionPrompts", {
        ownerKey: args.ownerKey,
        runId,
        question,
        status: "open",
        createdAt: now,
        updatedAt: now,
      });
      prompts.push({
        id: promptId,
        question,
        status: "open",
        createdAt: now,
      });
    }

    return prompts;
  },
});

export const recordSkippedReflectionRun = internalMutation({
  args: {
    ownerKey: v.string(),
    entryWindowStart: v.number(),
    entryWindowEnd: v.number(),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    await ensureProfile(ctx, args.ownerKey, now);
    await ctx.db.insert("reflectionRuns", {
      ownerKey: args.ownerKey,
      entryWindowStart: args.entryWindowStart,
      entryWindowEnd: args.entryWindowEnd,
      status: "skipped",
      promptCount: 0,
      createdAt: now,
    });
  },
});

async function markReflectionPromptAnswered(
  ctx: MutationCtx,
  args: {
    ownerKey: string;
    promptId: Id<"reflectionPrompts">;
    entryId: Id<"entries">;
    now: number;
  },
) {
  const prompt = await ctx.db.get(args.promptId);
  if (!prompt || prompt.ownerKey !== args.ownerKey) {
    throw new Error("REFLECTION_PROMPT_NOT_FOUND");
  }
  await ctx.db.patch(args.promptId, {
    status: "answered",
    answeredEntryId: args.entryId,
    updatedAt: args.now,
  });
}

async function ensureProfile(
  ctx: MutationCtx,
  ownerKey: string,
  now: number,
) {
  const existing = await ctx.db
    .query("profiles")
    .withIndex("by_ownerKey", (q) => q.eq("ownerKey", ownerKey))
    .unique();
  if (existing) {
    await ctx.db.patch(existing._id, { updatedAt: now });
    return existing._id;
  }
  return await ctx.db.insert("profiles", {
    ownerKey,
    createdAt: now,
    updatedAt: now,
  });
}

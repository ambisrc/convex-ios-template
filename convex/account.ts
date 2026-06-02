import { v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import { internal } from "./_generated/api";
import type { ActionCtx, MutationCtx } from "./_generated/server";
import { internalAction, internalMutation } from "./_generated/server";
import {
  accountDeletionCleanupValidator,
  type AccountDeletionCleanup,
  type DeleteAccountResponse,
  type DeleteCounts,
  type PosthogCleanupResult,
  type SentryCleanupResult,
} from "./lib/accountDeletionContract";

const DELETE_BATCH_LIMIT = 50;
const MAX_SYNCHRONOUS_DELETE_BATCHES = 20;

type DeleteBatchResult = {
  deleted: DeleteCounts;
  hasMore: boolean;
};

type DeletionRunMode = "sync" | "scheduled";

type DeletionJobDoc = Doc<"accountDeletionJobs">;

export const recordAppleSignInAuthorization = internalMutation({
  args: {
    ownerKey: v.string(),
    clientId: v.string(),
    refreshToken: v.string(),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const existing = await ctx.db
      .query("appleSignInCredentials")
      .withIndex("by_ownerKey", (q) => q.eq("ownerKey", args.ownerKey))
      .unique();

    if (existing) {
      await ctx.db.patch(existing._id, {
        clientId: args.clientId,
        refreshToken: args.refreshToken,
        updatedAt: now,
      });
      return { status: "updated" as const };
    }

    await ctx.db.insert("appleSignInCredentials", {
      ownerKey: args.ownerKey,
      clientId: args.clientId,
      refreshToken: args.refreshToken,
      createdAt: now,
      updatedAt: now,
    });
    return { status: "recorded" as const };
  },
});

export const deleteAccountForOwner = internalAction({
  args: {
    ownerKey: v.string(),
  },
  handler: async (ctx, args): Promise<DeleteAccountResponse> => {
    let result = await ctx.runMutation(internal.account.requestAccountDeletion, {
      ownerKey: args.ownerKey,
    });

    if (result.kind === "already_deleted") {
      return deletionJobToDeletedResponse(result.job);
    }
    if (result.kind === "in_progress") {
      return {
        status: "deletion_in_progress",
        deleted: result.deleted,
        batches: result.batches,
        jobStatus: result.jobStatus,
      };
    }

    while (result.kind === "batch_done" && result.hasMore && result.batches < MAX_SYNCHRONOUS_DELETE_BATCHES) {
      result = await ctx.runMutation(internal.account.runAccountDeletionBatch, {
        ownerKey: args.ownerKey,
      });
    }

    if (result.kind === "batch_done" && result.hasMore) {
      await ctx.runMutation(internal.account.scheduleAccountDeletionContinuation, {
        ownerKey: args.ownerKey,
      });
      return {
        status: "deletion_in_progress",
        deleted: result.deleted,
        batches: result.batches,
        jobStatus: result.jobStatus,
      };
    }
    if (result.kind === "ready_for_inline_cleanup") {
      const cleanup = await runAccountDeletionVendorCleanup(ctx, args.ownerKey);
      await ctx.runMutation(internal.account.finalizeAccountDeletion, {
        ownerKey: args.ownerKey,
        cleanup,
      });
      return {
        status: "deleted",
        deleted: result.deleted,
        batches: result.batches,
        cleanup,
      };
    }

    throw new Error("UNEXPECTED_ACCOUNT_DELETION_RESULT");
  },
});

export const requestAccountDeletion = internalMutation({
  args: {
    ownerKey: v.string(),
  },
  handler: async (ctx, args) => {
    const existing = await getDeletionJob(ctx, args.ownerKey);
    if (existing?.status === "deleted") {
      return { kind: "already_deleted" as const, job: existing };
    }
    if (existing && isActiveDeletionJob(existing.status)) {
      return {
        kind: "in_progress" as const,
        deleted: existing.deleted,
        batches: existing.batches,
        jobStatus: existing.status,
      };
    }

    const now = Date.now();
    const jobId = existing?._id ?? await ctx.db.insert("accountDeletionJobs", {
      ownerKey: args.ownerKey,
      status: "deleting",
      deleted: emptyDeleteCounts(),
      batches: 0,
      createdAt: now,
      updatedAt: now,
    });

    return await runDeletionBatch(ctx, {
      jobId,
      ownerKey: args.ownerKey,
      mode: "sync",
    });
  },
});

export const runAccountDeletionBatch = internalMutation({
  args: {
    ownerKey: v.string(),
  },
  handler: async (ctx, args) => {
    const job = await getDeletionJob(ctx, args.ownerKey);
    if (!job || job.status !== "deleting") {
      throw new Error("ACCOUNT_DELETION_JOB_NOT_DELETING");
    }

    return await runDeletionBatch(ctx, {
      jobId: job._id,
      ownerKey: args.ownerKey,
      mode: "sync",
    });
  },
});

export const scheduleAccountDeletionContinuation = internalMutation({
  args: {
    ownerKey: v.string(),
  },
  handler: async (ctx, args) => {
    const job = await getDeletionJob(ctx, args.ownerKey);
    if (!job || job.status !== "deleting") {
      return;
    }
    await ctx.scheduler.runAfter(0, internal.account.continueAccountDeletion, {
      ownerKey: args.ownerKey,
    });
  },
});

export const continueAccountDeletion = internalMutation({
  args: {
    ownerKey: v.string(),
  },
  handler: async (ctx, args) => {
    const job = await getDeletionJob(ctx, args.ownerKey);
    if (!job || job.status !== "deleting") {
      return null;
    }

    return await runDeletionBatch(ctx, {
      jobId: job._id,
      ownerKey: args.ownerKey,
      mode: "scheduled",
    });
  },
});

export const beginAccountDeletionCleanup = internalMutation({
  args: {
    ownerKey: v.string(),
  },
  handler: async (ctx, args) => {
    const job = await getDeletionJob(ctx, args.ownerKey);
    if (!job) {
      return false;
    }
    if (job.status === "deleted" || job.status === "cleanup_running") {
      return false;
    }
    if (job.status !== "cleanup_pending") {
      return false;
    }
    await ctx.db.patch(job._id, {
      status: "cleanup_running",
      updatedAt: Date.now(),
    });
    return true;
  },
});

export const finalizeAccountDeletion = internalMutation({
  args: {
    ownerKey: v.string(),
    cleanup: accountDeletionCleanupValidator,
  },
  handler: async (ctx, args) => {
    const job = await getDeletionJob(ctx, args.ownerKey);
    if (!job) {
      return null;
    }
    await ctx.db.patch(job._id, {
      status: "deleted",
      cleanup: args.cleanup,
      updatedAt: Date.now(),
    });
    return await ctx.db.get(job._id);
  },
});

export const runAccountDeletionCleanup = internalAction({
  args: {
    ownerKey: v.string(),
  },
  handler: async (ctx, args) => {
    const shouldRun = await ctx.runMutation(internal.account.beginAccountDeletionCleanup, {
      ownerKey: args.ownerKey,
    });
    if (!shouldRun) {
      return;
    }

    const cleanup = await runAccountDeletionVendorCleanup(ctx, args.ownerKey);

    await ctx.runMutation(internal.account.finalizeAccountDeletion, {
      ownerKey: args.ownerKey,
      cleanup,
    });
  },
});

async function runAccountDeletionVendorCleanup(
  ctx: Pick<ActionCtx, "runAction">,
  ownerKey: string,
): Promise<AccountDeletionCleanup> {
  const posthog = await runCleanupStep(async () => {
    const result: PosthogCleanupResult = await ctx.runAction(internal.posthog.deletePerson, { ownerKey });
    return result;
  });
  const sentry = await runCleanupStep(async () => {
    const result: SentryCleanupResult = await ctx.runAction(internal.sentry.recordAccountCleanup, { ownerKey });
    return result;
  });

  return { posthog, sentry };
}

async function runCleanupStep<T extends PosthogCleanupResult | SentryCleanupResult>(
  cleanup: () => Promise<T>,
): Promise<T | { status: "failed"; reason: string }> {
  try {
    return await cleanup();
  } catch (error) {
    return { status: "failed", reason: cleanupErrorReason(error) };
  }
}

function cleanupErrorReason(error: unknown) {
  if (error instanceof Error && error.message.trim()) {
    return error.message;
  }
  return "UNKNOWN_CLEANUP_ERROR";
}

async function runDeletionBatch(
  ctx: MutationCtx,
  args: {
    jobId: Id<"accountDeletionJobs">;
    ownerKey: string;
    mode: DeletionRunMode;
  },
) {
  const job = await ctx.db.get(args.jobId);
  if (!job || job.status !== "deleting") {
    throw new Error("ACCOUNT_DELETION_JOB_NOT_DELETING");
  }

  const batch = await deleteOwnedDataBatch(ctx, args.ownerKey);
  const deleted = addDeleteCounts(job.deleted, batch.deleted);
  const batches = job.batches + 1;
  const now = Date.now();
  const schedule = args.mode === "scheduled";

  if (batch.hasMore) {
    await ctx.db.patch(args.jobId, {
      deleted,
      batches,
      updatedAt: now,
    });
    if (schedule) {
      await ctx.scheduler.runAfter(0, internal.account.continueAccountDeletion, {
        ownerKey: args.ownerKey,
      });
    }
    return {
      kind: "batch_done" as const,
      deleted,
      batches,
      hasMore: true,
      jobStatus: "deleting" as const,
    };
  }

  await ctx.db.patch(args.jobId, {
    status: "cleanup_pending",
    deleted,
    batches,
    updatedAt: now,
  });

  if (schedule) {
    await ctx.scheduler.runAfter(0, internal.account.runAccountDeletionCleanup, {
      ownerKey: args.ownerKey,
    });
    return {
      kind: "cleanup_scheduled" as const,
      deleted,
      batches,
      hasMore: false,
    };
  }

  return {
    kind: "ready_for_inline_cleanup" as const,
    deleted,
    batches,
    hasMore: false,
  };
}

async function deleteOwnedDataBatch(ctx: MutationCtx, ownerKey: string): Promise<DeleteBatchResult> {
  const profiles = await deleteProfiles(ctx, ownerKey);
  const entries = await deleteEntries(ctx, ownerKey);
  const commandHistory = await deleteCommandHistory(ctx, ownerKey);
  const appleSignInCredentials = await deleteAppleCredentials(ctx, ownerKey);
  const usageEvents = await deleteUsageEvents(ctx, ownerKey);

  return {
    deleted: {
      profiles: profiles.deleted,
      entries: entries.deleted,
      commandHistory: commandHistory.deleted,
      appleSignInCredentials: appleSignInCredentials.deleted,
      usageEvents: usageEvents.deleted,
    },
    hasMore:
      profiles.hasMore
      || entries.hasMore
      || commandHistory.hasMore
      || appleSignInCredentials.hasMore
      || usageEvents.hasMore,
  };
}

async function deleteProfiles(ctx: MutationCtx, ownerKey: string) {
  const rows = await ctx.db
    .query("profiles")
    .withIndex("by_ownerKey", (q) => q.eq("ownerKey", ownerKey))
    .take(DELETE_BATCH_LIMIT + 1);
  return await deleteRows(ctx, rows);
}

async function deleteEntries(ctx: MutationCtx, ownerKey: string) {
  const rows = await ctx.db
    .query("entries")
    .withIndex("by_ownerKey_and_createdAt", (q) => q.eq("ownerKey", ownerKey))
    .take(DELETE_BATCH_LIMIT + 1);
  return await deleteRows(ctx, rows);
}

async function deleteCommandHistory(ctx: MutationCtx, ownerKey: string) {
  const rows = await ctx.db
    .query("commandHistory")
    .withIndex("by_ownerKey_and_createdAt", (q) => q.eq("ownerKey", ownerKey))
    .take(DELETE_BATCH_LIMIT + 1);
  return await deleteRows(ctx, rows);
}

async function deleteAppleCredentials(ctx: MutationCtx, ownerKey: string) {
  const rows = await ctx.db
    .query("appleSignInCredentials")
    .withIndex("by_ownerKey", (q) => q.eq("ownerKey", ownerKey))
    .take(DELETE_BATCH_LIMIT + 1);
  return await deleteRows(ctx, rows);
}

async function deleteUsageEvents(ctx: MutationCtx, ownerKey: string) {
  const rows = await ctx.db
    .query("usageEvents")
    .withIndex("by_ownerKey_and_createdAt", (q) => q.eq("ownerKey", ownerKey))
    .take(DELETE_BATCH_LIMIT + 1);
  return await deleteRows(ctx, rows);
}

async function deleteRows(ctx: MutationCtx, rows: Array<{ _id: Parameters<MutationCtx["db"]["delete"]>[0] }>) {
  const rowsToDelete = rows.slice(0, DELETE_BATCH_LIMIT);
  for (const row of rowsToDelete) {
    await ctx.db.delete(row._id);
  }
  return {
    deleted: rowsToDelete.length,
    hasMore: rows.length > DELETE_BATCH_LIMIT,
  };
}

async function getDeletionJob(ctx: MutationCtx, ownerKey: string) {
  return await ctx.db
    .query("accountDeletionJobs")
    .withIndex("by_ownerKey", (q) => q.eq("ownerKey", ownerKey))
    .unique();
}

function isActiveDeletionJob(status: DeletionJobDoc["status"]) {
  return status === "deleting"
    || status === "cleanup_pending"
    || status === "cleanup_running";
}

function emptyDeleteCounts(): DeleteCounts {
  return {
    profiles: 0,
    entries: 0,
    commandHistory: 0,
    appleSignInCredentials: 0,
    usageEvents: 0,
  };
}

function addDeleteCounts(total: DeleteCounts, batch: DeleteCounts): DeleteCounts {
  return {
    profiles: total.profiles + batch.profiles,
    entries: total.entries + batch.entries,
    commandHistory: total.commandHistory + batch.commandHistory,
    appleSignInCredentials: total.appleSignInCredentials + batch.appleSignInCredentials,
    usageEvents: total.usageEvents + batch.usageEvents,
  };
}

export function deletionJobToDeletedResponse(job: DeletionJobDoc) {
  if (job.status !== "deleted" || !job.cleanup) {
    throw new Error("ACCOUNT_DELETION_JOB_NOT_FINALIZED");
  }
  return {
    status: "deleted" as const,
    deleted: job.deleted,
    batches: job.batches,
    cleanup: job.cleanup,
  };
}

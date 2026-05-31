import { v } from "convex/values";
import { internal } from "./_generated/api";
import { action } from "./_generated/server";
import { deletionJobToDeletedResponse, runAccountDeletionVendorCleanup } from "./account";
import { requireOwnerKey } from "./lib/auth";
import { commandSourceValidator, type AssistantOperation, type CommandSource } from "./lib/operations";
import { interpretCommand } from "./lib/commandInterpreter";
import { withSentry } from "./lib/sentry";
import { transcribeVoice } from "./lib/voiceTranscription";

const MAX_SYNCHRONOUS_DELETE_BATCHES = 20;

export type CommandResponse = {
  status: "applied";
  summary: string;
  operations: AssistantOperation[];
  entries: Array<{
    body: string;
    source: CommandSource;
  }>;
};

type AppleAuthorizationResponse = {
  status: "recorded" | "updated";
};

type DeleteCounts = {
  profiles: number;
  entries: number;
  commandHistory: number;
  appleSignInCredentials: number;
  usageEvents: number;
};

type CleanupResult =
  | { status: "skipped"; reason: "missing_config" }
  | { status: "requested" }
  | { status: "failed"; reason: string };

type SentryCleanupResult =
  | { status: "skipped"; reason: "missing_config" }
  | { status: "reported" }
  | { status: "failed"; reason: string };

type DeleteAccountDeletedResponse = {
  status: "deleted";
  deleted: DeleteCounts;
  batches: number;
  cleanup: {
    posthog: CleanupResult;
    sentry: SentryCleanupResult;
  };
};

type DeleteAccountInProgressResponse = {
  status: "deletion_in_progress";
  deleted: DeleteCounts;
  batches: number;
  jobStatus: "deleting" | "cleanup_pending" | "cleanup_running";
};

export type DeleteAccountResponse = DeleteAccountDeletedResponse | DeleteAccountInProgressResponse;

export const submitCommand = action({
  args: {
    text: v.string(),
    source: commandSourceValidator,
  },
  handler: async (ctx, args): Promise<CommandResponse> => {
    return await withSentry("commands:submitCommand", ctx, async () => {
      const ownerKey = await requireOwnerKey(ctx);
      const transcript = args.text.trim();
      const { operations, summary } = interpretCommand(transcript);

      const applyResult = await ctx.runMutation(internal.lib.apply.applyCommand, {
        ownerKey,
        transcript,
        source: args.source,
        operations,
        summary,
      });

      return {
        status: "applied",
        summary,
        operations,
        entries: applyResult.entries,
      };
    });
  },
});

export const recordAppleSignInAuthorization = action({
  args: {
    clientId: v.string(),
    refreshToken: v.string(),
  },
  handler: async (ctx, args): Promise<AppleAuthorizationResponse> => {
    return await withSentry("commands:recordAppleSignInAuthorization", ctx, async () => {
      const ownerKey = await requireOwnerKey(ctx);
      const response: AppleAuthorizationResponse = await ctx.runMutation(internal.account.recordAppleSignInAuthorization, {
        ownerKey,
        clientId: args.clientId,
        refreshToken: args.refreshToken,
      });
      return response;
    });
  },
});

export const deleteAccount = action({
  args: {},
  handler: async (ctx): Promise<DeleteAccountResponse> => {
    return await withSentry("commands:deleteAccount", ctx, async () => {
      const ownerKey = await requireOwnerKey(ctx);
      let result = await ctx.runMutation(internal.account.requestAccountDeletion, { ownerKey });

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
        result = await ctx.runMutation(internal.account.runAccountDeletionBatch, { ownerKey });
      }

      if (result.kind === "batch_done" && result.hasMore) {
        await ctx.runMutation(internal.account.scheduleAccountDeletionContinuation, { ownerKey });
        return {
          status: "deletion_in_progress",
          deleted: result.deleted,
          batches: result.batches,
          jobStatus: result.jobStatus,
        };
      }
      if (result.kind === "ready_for_inline_cleanup") {
        const cleanup = await runAccountDeletionVendorCleanup(ctx, ownerKey);
        await ctx.runMutation(internal.account.finalizeAccountDeletion, {
          ownerKey,
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
    });
  },
});

export const transcribeVoiceCommand = action({
  args: {
    audioBase64: v.string(),
    mimeType: v.string(),
  },
  handler: async (ctx, args) => {
    return await withSentry("commands:transcribeVoiceCommand", ctx, async () => {
      await requireOwnerKey(ctx);
      return await transcribeVoice(args);
    });
  },
});

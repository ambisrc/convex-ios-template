import { v } from "convex/values";
import { internal } from "./_generated/api";
import { action } from "./_generated/server";
import type { DeleteAccountResponse } from "./lib/accountDeletionContract";
import { requireOwnerKey } from "./lib/auth";
import { commandSourceValidator, type AssistantOperation, type CommandSource } from "./lib/operations";
import { interpretCommand } from "./lib/commandInterpreter";
import { withSentry } from "./lib/sentry";
import { transcribeVoice } from "./lib/voiceTranscription";

export type { DeleteAccountResponse } from "./lib/accountDeletionContract";

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
      return await ctx.runAction(internal.account.deleteAccountForOwner, { ownerKey });
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

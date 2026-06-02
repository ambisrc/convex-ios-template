import { internal } from "./_generated/api";
import { mutation, query } from "./_generated/server";
import { requireOwnerKey } from "./lib/auth";
import { commandSourceValidator } from "./lib/operations";
import { v } from "convex/values";

export const entryListItemValidator = v.object({
  id: v.string(),
  body: v.string(),
  source: commandSourceValidator,
});

export type EntryListItem = {
  id: string;
  body: string;
  source: "typed" | "voice";
};

export const listEntries = query({
  args: {},
  returns: v.array(entryListItemValidator),
  handler: async (ctx): Promise<EntryListItem[]> => {
    const ownerKey = await requireOwnerKey(ctx);
    const rows = await ctx.db
      .query("entries")
      .withIndex("by_ownerKey_and_createdAt", (q) => q.eq("ownerKey", ownerKey))
      .order("desc")
      .take(50);
    return rows.map(({ _id, body, source }) => ({ id: _id, body, source }));
  },
});

export const updateEntry = mutation({
  args: {
    id: v.id("entries"),
    body: v.string(),
  },
  returns: entryListItemValidator,
  handler: async (ctx, args): Promise<EntryListItem> => {
    const ownerKey = await requireOwnerKey(ctx);
    return await ctx.runMutation(internal.lib.apply.updateEntryBody, {
      ownerKey,
      entryId: args.id,
      body: args.body,
    });
  },
});

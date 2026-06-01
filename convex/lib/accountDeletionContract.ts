import { v, type Infer } from "convex/values";

export const deleteCountsValidator = v.object({
  profiles: v.number(),
  entries: v.number(),
  commandHistory: v.number(),
  appleSignInCredentials: v.number(),
  usageEvents: v.number(),
});

export type DeleteCounts = Infer<typeof deleteCountsValidator>;

export const posthogCleanupResultValidator = v.union(
  v.object({ status: v.literal("skipped"), reason: v.literal("missing_config") }),
  v.object({ status: v.literal("requested") }),
  v.object({ status: v.literal("failed"), reason: v.string() }),
);

export const sentryCleanupResultValidator = v.union(
  v.object({ status: v.literal("skipped"), reason: v.literal("missing_config") }),
  v.object({ status: v.literal("reported") }),
  v.object({ status: v.literal("failed"), reason: v.string() }),
);

export const accountDeletionCleanupValidator = v.object({
  posthog: posthogCleanupResultValidator,
  sentry: sentryCleanupResultValidator,
});

export type PosthogCleanupResult = Infer<typeof posthogCleanupResultValidator>;
export type SentryCleanupResult = Infer<typeof sentryCleanupResultValidator>;
export type AccountDeletionCleanup = Infer<typeof accountDeletionCleanupValidator>;

export const accountDeletionJobStatusValidator = v.union(
  v.literal("deleting"),
  v.literal("cleanup_pending"),
  v.literal("cleanup_running"),
  v.literal("deleted"),
);

export type AccountDeletionJobStatus = Infer<typeof accountDeletionJobStatusValidator>;

export const activeDeletionJobStatusValidator = v.union(
  v.literal("deleting"),
  v.literal("cleanup_pending"),
  v.literal("cleanup_running"),
);

export type ActiveDeletionJobStatus = Infer<typeof activeDeletionJobStatusValidator>;

export type DeleteAccountDeletedResponse = {
  status: "deleted";
  deleted: DeleteCounts;
  batches: number;
  cleanup: AccountDeletionCleanup;
};

export type DeleteAccountInProgressResponse = {
  status: "deletion_in_progress";
  deleted: DeleteCounts;
  batches: number;
  jobStatus: ActiveDeletionJobStatus;
};

export type DeleteAccountResponse = DeleteAccountDeletedResponse | DeleteAccountInProgressResponse;

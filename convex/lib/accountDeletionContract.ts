import { v, type Infer } from "convex/values";

export const accountDeletionOwnedTableNames = [
  "profiles",
  "entries",
  "commandHistory",
  "appleSignInCredentials",
  "usageEvents",
] as const;

export type AccountDeletionOwnedTableName = typeof accountDeletionOwnedTableNames[number];

const deleteCountValidators = {
  profiles: v.number(),
  entries: v.number(),
  commandHistory: v.number(),
  appleSignInCredentials: v.number(),
  usageEvents: v.number(),
} satisfies Record<AccountDeletionOwnedTableName, ReturnType<typeof v.number>>;

export const deleteCountsValidator = v.object(deleteCountValidators);

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

const deletingStatusValidator = v.literal("deleting");
const cleanupPendingStatusValidator = v.literal("cleanup_pending");
const cleanupRunningStatusValidator = v.literal("cleanup_running");
const deletedStatusValidator = v.literal("deleted");

export const accountDeletionJobStatusValidator = v.union(
  deletingStatusValidator,
  cleanupPendingStatusValidator,
  cleanupRunningStatusValidator,
  deletedStatusValidator,
);

export type AccountDeletionJobStatus = Infer<typeof accountDeletionJobStatusValidator>;

export const activeDeletionJobStatusValidator = v.union(
  deletingStatusValidator,
  cleanupPendingStatusValidator,
  cleanupRunningStatusValidator,
);

export type ActiveDeletionJobStatus = Exclude<AccountDeletionJobStatus, "deleted">;

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

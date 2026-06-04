import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

crons.daily(
  "generate daily reflection prompts",
  { hourUTC: 13, minuteUTC: 0 },
  internal.reflections.generateDailyForActiveProfiles,
);

export default crons;

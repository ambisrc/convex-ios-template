import { describe, expect, it } from "vitest";
import { findReadinessIssues, isDefaultScannedPath } from "./verify-template-readiness.mjs";

describe("template readiness checks", () => {
  it("accepts placeholder env values and ignored local secret files", () => {
    const issues = findReadinessIssues({
      files: [
        {
          path: ".env.example",
          content: [
            "GROQ_API_KEY=replace-with-groq-api-key",
            "SENTRY_DSN=https://public-key@o0.ingest.sentry.io/0",
            "POSTHOG_PERSONAL_API_KEY=<posthog-personal-api-key>",
          ].join("\n"),
        },
      ],
      ignoredPaths: new Set([".env", ".env.local", "ios/Local.xcconfig"]),
    });

    expect(issues).toEqual([]);
  });

  it("reports tracked source-app paths, private keys, and live secret-looking values", () => {
    const issues = findReadinessIssues({
      files: [
        {
          path: "README.md",
          content: "Use brilliant-minnow-935 and YapTask.xcodeproj for setup.",
        },
        {
          path: "AuthKey_1234567890.p8",
          content: "-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----",
        },
        {
          path: "docs/deployment.md",
          content: "GROQ_API_KEY=gsk_live_value",
        },
      ],
      ignoredPaths: new Set([".env"]),
    });

    expect(issues).toEqual([
      {
        type: "missing_ignore",
        path: ".env.local",
        message: ".env.local must be ignored",
      },
      {
        type: "missing_ignore",
        path: "ios/Local.xcconfig",
        message: "ios/Local.xcconfig must be ignored",
      },
      {
        type: "source_app_reference",
        path: "README.md",
        line: 1,
        message: "brilliant-minnow deployment reference must not be tracked",
      },
      {
        type: "source_app_reference",
        path: "README.md",
        line: 1,
        message: "YapTask Xcode project reference must not be tracked",
      },
      {
        type: "private_key_material",
        path: "AuthKey_1234567890.p8",
        line: 1,
        message: "Apple private key material must not be tracked",
      },
      {
        type: "private_key_file",
        path: "AuthKey_1234567890.p8",
        message: "Apple .p8 private key files must not be tracked",
      },
      {
        type: "live_secret_assignment",
        path: "docs/deployment.md",
        line: 1,
        message: "GROQ_API_KEY looks like a live secret assignment",
      },
    ]);
  });

  it("scans the tracked Xcode project for stale source-app project references", () => {
    expect(isDefaultScannedPath("VoiceAgentTemplate.xcodeproj/project.pbxproj")).toBe(true);

    const issues = findReadinessIssues({
      files: [
        {
          path: "VoiceAgentTemplate.xcodeproj/project.pbxproj",
          content: "SOURCE_APP_PROJECT = yaptask.xcodeproj;",
        },
      ],
      ignoredPaths: new Set([".env", ".env.local", "ios/Local.xcconfig"]),
    });

    expect(issues).toEqual([
      {
        type: "source_app_reference",
        path: "VoiceAgentTemplate.xcodeproj/project.pbxproj",
        line: 1,
        message: "YapTask Xcode project reference must not be tracked",
      },
    ]);
  });
});

#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { relative } from "node:path";
import { fileURLToPath } from "node:url";

const REQUIRED_IGNORED_PATHS = [".env", ".env.local", "ios/Local.xcconfig"];
const DEFAULT_SCANNED_PATHS = [
  ".env.example",
  ".gitignore",
  "AGENTS.md",
  "BRAND.md",
  "CONTEXT.md",
  "CUSTOMIZE.md",
  "ENGINEERING.md",
  "README.md",
  "TEMPLATE_VARIABLES.md",
  "VoiceAgentTemplate.xcodeproj",
  "convex",
  "docs",
  "ios",
  "package.json",
  "scripts",
  "tests",
];
const HISTORICAL_PLAN_PATTERN = /^docs\/plans\/(?:AMB-|resumable-account-deletion)/;
const SELF_TEST_PATTERN = /^scripts\/verify-template-readiness\.(?:mjs|test\.mjs)$/;

export function findReadinessIssues({ files, ignoredPaths }) {
  const issues = [];

  for (const path of REQUIRED_IGNORED_PATHS) {
    if (!ignoredPaths.has(path)) {
      issues.push({
        type: "missing_ignore",
        path,
        message: `${path} must be ignored`,
      });
    }
  }

  for (const file of files) {
    if (file.path.endsWith(".p8")) {
      scanContent(file, issues);
      issues.push({
        type: "private_key_file",
        path: file.path,
        message: "Apple .p8 private key files must not be tracked",
      });
      continue;
    }

    scanContent(file, issues);
  }

  return issues;
}

function scanContent(file, issues) {
  const lines = file.content.split(/\r?\n/);
  lines.forEach((line, index) => {
    const lineNumber = index + 1;

    if (line.includes("brilliant-minnow")) {
      issues.push({
        type: "source_app_reference",
        path: file.path,
        line: lineNumber,
        message: "brilliant-minnow deployment reference must not be tracked",
      });
    }

    if (/yaptask\.xcodeproj/i.test(line)) {
      issues.push({
        type: "source_app_reference",
        path: file.path,
        line: lineNumber,
        message: "YapTask Xcode project reference must not be tracked",
      });
    }

    if (/-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(line)) {
      issues.push({
        type: "private_key_material",
        path: file.path,
        line: lineNumber,
        message: "Apple private key material must not be tracked",
      });
    }

    const envAssignment = line.match(
      /^\s*(?:export\s+)?([A-Z0-9_]*(?:API_KEY|TOKEN|SECRET|DSN)[A-Z0-9_]*)\s*=\s*([^\s#]+)/,
    );
    if (envAssignment && looksLikeLiveSecretValue(envAssignment[2])) {
      issues.push({
        type: "live_secret_assignment",
        path: file.path,
        line: lineNumber,
        message: `${envAssignment[1]} looks like a live secret assignment`,
      });
    }
  });
}

function looksLikeLiveSecretValue(rawValue) {
  const value = rawValue.replace(/^['"]|['"]$/g, "");
  if (value === "" || value === "00000") {
    return false;
  }
  if (value.includes("replace-with")) {
    return false;
  }
  if (value.startsWith("<") && value.endsWith(">")) {
    return false;
  }
  if (value.startsWith("https://public-key@")) {
    return false;
  }
  return true;
}

function trackedFiles() {
  const output = execFileSync("git", ["ls-files", "-z"], { encoding: "utf8" });
  return output
    .split("\0")
    .filter(Boolean)
    .filter(isDefaultScannedPath)
    .filter((path) => !HISTORICAL_PLAN_PATTERN.test(path))
    .filter((path) => !SELF_TEST_PATTERN.test(path))
    .map((path) => ({
      path,
      content: readFileSync(path, "utf8"),
    }));
}

export function isDefaultScannedPath(path) {
  return DEFAULT_SCANNED_PATHS.some((root) => path === root || path.startsWith(`${root}/`));
}

function ignoredPaths() {
  const ignored = new Set();
  for (const path of REQUIRED_IGNORED_PATHS) {
    try {
      execFileSync("git", ["check-ignore", "-q", path], { stdio: "ignore" });
      ignored.add(path);
    } catch {
      // Missing entries are reported by findReadinessIssues.
    }
  }
  return ignored;
}

function runCli() {
  const issues = findReadinessIssues({
    files: trackedFiles(),
    ignoredPaths: ignoredPaths(),
  });

  if (issues.length === 0) {
    console.log("Template readiness checks passed.");
    return 0;
  }

  console.error("Template readiness checks failed:");
  for (const issue of issues) {
    const location = issue.line ? `${issue.path}:${issue.line}` : issue.path;
    console.error(`- ${location}: ${issue.message}`);
  }
  return 1;
}

const invokedPath = process.argv[1] ? relative(process.cwd(), process.argv[1]) : "";
const modulePath = relative(process.cwd(), fileURLToPath(import.meta.url));
if (invokedPath === modulePath) {
  process.exitCode = runCli();
}

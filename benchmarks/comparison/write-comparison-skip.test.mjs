// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const comparisonDirectory = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(comparisonDirectory, "..", "..");
const writer = path.join(root, "scripts", "write-comparison-skip.mjs");

function run(track, extraEnvironment = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "flyology-json-skip-"));
  const output = path.join(directory, "skip.json");
  const result = spawnSync(process.execPath, [writer, root, track, output], {
    encoding: "utf8",
    env: { ...process.env, ...extraEnvironment },
  });
  const record = result.status === 0 ? JSON.parse(fs.readFileSync(output, "utf8")) : null;
  fs.rmSync(directory, { recursive: true, force: true });
  return { result, record };
}

test("local skip identity distinguishes the build track", () => {
  const { result, record } = run("native", {
    GITHUB_ACTIONS: "false",
    GITHUB_JOB: "ignored",
    RUNNER_OS: "ignored",
    RUNNER_ARCH: "ignored",
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(record.ci.job, "local-native");
});

test("GitHub skip identity distinguishes OS, architecture, and build track", () => {
  const { result, record } = run("portable", {
    GITHUB_ACTIONS: "true",
    GITHUB_EVENT_NAME: "schedule",
    GITHUB_JOB: "benchmark",
    RUNNER_OS: "macOS",
    RUNNER_ARCH: "ARM64",
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(record.ci.job, "benchmark:macOS:ARM64:portable");
});

test("GitHub skip identity rejects incomplete runner provenance", () => {
  const { result } = run("portable", {
    GITHUB_ACTIONS: "true",
    GITHUB_EVENT_NAME: "schedule",
    GITHUB_JOB: "benchmark",
    RUNNER_OS: "macOS",
    RUNNER_ARCH: "",
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /RUNNER_ARCH is required/);
});

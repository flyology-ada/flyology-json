#!/usr/bin/env node
// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { execFileSync } from "node:child_process";
import { requireReviewedNode } from "../benchmarks/comparison/node-toolchain.mjs";
import { parseStrictJson } from "../benchmarks/comparison/strict-json.mjs";

requireReviewedNode();

if (process.argv.length !== 5) {
  console.error("usage: node scripts/write-comparison-skip.mjs ROOT TRACK OUTPUT.json");
  process.exit(2);
}

const [, , rootArgument, track, outputPath] = process.argv;
if (track !== "portable" && track !== "native") {
  throw new Error(`unsupported build track: ${track}`);
}

const root = path.resolve(rootArgument);
const comparison = path.join(root, "benchmarks", "comparison");
const capabilityPath = path.join(
  root,
  "benchmarks",
  "competitors",
  "rust",
  "capabilities",
  "serde_json.json",
);

function digest(filePath) {
  return crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}

function contractDigest(name) {
  return digest(path.join(comparison, name));
}

function trigger() {
  if (process.env.GITHUB_ACTIONS !== "true") {
    return "local";
  }
  switch (process.env.GITHUB_EVENT_NAME) {
    case "schedule":
      return "weekly";
    case "workflow_dispatch":
      return "manual";
    case "pull_request":
      return "pull_request";
    case "push":
      return "push";
    default:
      throw new Error(`unsupported GitHub trigger: ${process.env.GITHUB_EVENT_NAME}`);
  }
}

function jobIdentity() {
  if (process.env.GITHUB_ACTIONS !== "true") {
    return `local-${track}`;
  }

  const required = ["GITHUB_JOB", "RUNNER_OS", "RUNNER_ARCH"];
  for (const name of required) {
    if (process.env[name] === undefined || process.env[name] === "") {
      throw new Error(`${name} is required for a GitHub Actions skip record`);
    }
  }

  return `${process.env.GITHUB_JOB}:${process.env.RUNNER_OS}:${process.env.RUNNER_ARCH}:${track}`;
}

const capability = parseStrictJson(fs.readFileSync(capabilityPath));
const attemptText = process.env.GITHUB_RUN_ATTEMPT;
const attempt = attemptText === undefined ? null : Number(attemptText);
if (attempt !== null && (!Number.isSafeInteger(attempt) || attempt < 1)) {
  throw new Error("GITHUB_RUN_ATTEMPT is not a positive integer");
}

const record = {
  contract: {
    capability_schema_sha256: contractDigest("capability.schema.json"),
    skip_schema_sha256: contractDigest("skip.schema.json"),
    sources_lock_sha256: contractDigest("sources.lock.tsv"),
    validator_sha256: contractDigest("validate-records.mjs"),
    strict_json_sha256: contractDigest("strict-json.mjs"),
    node_toolchain_sha256: contractDigest("node-toolchain.mjs"),
    node_package_manifest_sha256: contractDigest("package.json"),
    node_package_lock_sha256: contractDigest("package-lock.json"),
    tooling_licenses_sha256: contractDigest("tooling-licenses.lock.tsv"),
    harness_commit: execFileSync("git", ["-C", root, "rev-parse", "HEAD"], {
      encoding: "utf8",
    }).trim(),
  },
  ci: {
    trigger: trigger(),
    provider: process.env.GITHUB_ACTIONS === "true" ? "github-actions" : "local",
    workflow: process.env.GITHUB_WORKFLOW ?? "local",
    job: jobIdentity(),
    run_id: process.env.GITHUB_RUN_ID ?? "local",
    attempt,
  },
  implementation: {
    implementation_id: capability.implementation_id,
    source_id: capability.source_id,
    source_revision: capability.source_revision,
    capability_sha256: digest(capabilityPath),
  },
  unsupported: {
    reason: "unsupported_fixture",
    os: null,
    architecture: null,
    toolchain: null,
    lane: "parse_dom",
    fixture: "deep_nesting",
  },
  detail:
    "The maintained fixture has depth 256; serde_json Value with the admitted default features rejects depth 128.",
};

fs.writeFileSync(outputPath, `${JSON.stringify(record)}\n`, { flag: "wx" });

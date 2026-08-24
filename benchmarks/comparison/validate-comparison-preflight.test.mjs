// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { comparisonIdentities } from "./comparison-matrix.mjs";

const comparisonDirectory = path.dirname(fileURLToPath(import.meta.url));
const validator = path.resolve(
  comparisonDirectory,
  "..",
  "..",
  "scripts",
  "validate-comparison-preflight.mjs",
);

function validLines() {
  return comparisonIdentities().map(
    ({ implementation, fixture }, index) =>
      `implementation=${implementation} fixture=${fixture} value=${index + 1}`,
  );
}

function run(contents) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "flyology-json-preflight-"));
  const input = path.join(directory, "preflight.txt");
  fs.writeFileSync(input, contents);
  const result = spawnSync(process.execPath, [validator, input], { encoding: "utf8" });
  fs.rmSync(directory, { recursive: true, force: true });
  return result;
}

test("accepts the exact comparison preflight matrix", () => {
  const result = run(`${validLines().join("\n")}\n`);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /validated 63 exact comparison preflight populations/);
});

test("rejects a missing comparison preflight population", () => {
  const lines = validLines();
  lines.pop();
  assert.notEqual(run(`${lines.join("\n")}\n`).status, 0);
});

test("rejects a duplicate comparison preflight population", () => {
  const lines = validLines();
  lines.push(lines[0]);
  assert.notEqual(run(`${lines.join("\n")}\n`).status, 0);
});

test("rejects malformed comparison preflight output", () => {
  const lines = validLines();
  lines[0] = "unexpected text";
  assert.notEqual(run(`${lines.join("\n")}\n`).status, 0);
});

test("rejects comparison preflight output without a final newline", () => {
  assert.notEqual(run(validLines().join("\n")).status, 0);
});

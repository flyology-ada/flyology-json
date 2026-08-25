// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { parserIdentities, withParserStorage } from "./parser-matrix.mjs";

const comparisonDirectory = path.dirname(fileURLToPath(import.meta.url));
const validator = path.resolve(
  comparisonDirectory,
  "..",
  "..",
  "scripts",
  "validate-parser-preflight.mjs",
);

function run(lines, finalNewline = true) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "flyology-json-parser-preflight-"));
  const input = path.join(directory, "preflight.txt");
  fs.writeFileSync(input, `${lines.join("\n")}${finalNewline ? "\n" : ""}`);
  const result = spawnSync(process.execPath, [validator, input], { encoding: "utf8" });
  fs.rmSync(directory, { recursive: true, force: true });
  return result;
}

function validLines() {
  return parserIdentities().map((identity) => withParserStorage(identity, 1));
}

test("accepts the exact parser preflight matrix", () => {
  const result = run(validLines());
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /validated 45 exact parser preflight populations/);
});

test("rejects a missing parser preflight population", () => {
  assert.notEqual(run(validLines().slice(1)).status, 0);
});

test("rejects a duplicate parser preflight population", () => {
  const lines = validLines();
  lines.push(lines[0]);
  assert.notEqual(run(lines).status, 0);
});

test("rejects parser preflight output without a final newline", () => {
  assert.notEqual(run(validLines(), false).status, 0);
});

test("rejects a nonpositive parser storage measurement", () => {
  const lines = validLines();
  lines[0] = lines[0].replace("parser_bytes=1", "parser_bytes=0");
  assert.notEqual(run(lines).status, 0);
});

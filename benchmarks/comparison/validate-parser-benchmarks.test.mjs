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
  "validate-parser-benchmarks.mjs",
);

function validRecords() {
  return parserIdentities().map((identity) => ({
    name: withParserStorage(identity, 1),
    iterations: 1,
    samples: 50,
    median_ns: 1,
    cv_percent: 0,
  }));
}

function run(records) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "flyology-json-parser-matrix-"));
  const input = path.join(directory, "input.jsonl");
  fs.writeFileSync(input, `${records.map((record) => JSON.stringify(record)).join("\n")}\n`);
  const result = spawnSync(process.execPath, [validator, input], { encoding: "utf8" });
  fs.rmSync(directory, { recursive: true, force: true });
  return result;
}

test("accepts the exact standalone parser matrix", () => {
  const result = run(validRecords());
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /validated 45 exact parser populations/);
});

test("rejects a missing parser population", () => {
  const records = validRecords();
  records.pop();
  assert.notEqual(run(records).status, 0);
});

test("rejects a duplicate parser population", () => {
  const records = validRecords();
  records.push(records[0]);
  assert.notEqual(run(records).status, 0);
});

test("rejects a changed parser identity", () => {
  const records = validRecords();
  records[0] = { ...records[0], name: records[0].name.replace("bytes=37", "bytes=38") };
  assert.notEqual(run(records).status, 0);
});

test("rejects a nonpositive parser storage measurement", () => {
  const records = validRecords();
  records[0] = { ...records[0], name: records[0].name.replace("parser_bytes=1", "parser_bytes=0") };
  assert.notEqual(run(records).status, 0);
});

test("rejects a negative coefficient of variation", () => {
  const records = validRecords();
  records[0] = { ...records[0], cv_percent: -1 };
  assert.notEqual(run(records).status, 0);
});

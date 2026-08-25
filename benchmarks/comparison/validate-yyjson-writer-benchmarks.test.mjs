// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { yyjsonWriterIdentities } from "./yyjson-writer-matrix.mjs";

const comparisonDirectory = path.dirname(fileURLToPath(import.meta.url));
const validator = path.resolve(
  comparisonDirectory,
  "..",
  "..",
  "scripts",
  "validate-yyjson-writer-benchmarks.mjs",
);

function validRecords() {
  return yyjsonWriterIdentities.map((name) => ({
    name,
    iterations: 1,
    samples: 50,
    median_ns: 1,
    cv_percent: 0,
  }));
}

function run(records) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "flyology-json-yyjson-writer-"));
  const input = path.join(directory, "input.jsonl");
  fs.writeFileSync(input, `${records.map((record) => JSON.stringify(record)).join("\n")}\n`);
  const result = spawnSync(process.execPath, [validator, input], { encoding: "utf8" });
  fs.rmSync(directory, { recursive: true, force: true });
  return result;
}

test("accepts the exact yyjson writer matrix", () => {
  const result = run(validRecords());
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /validated 2 exact yyjson writer populations/);
});

test("rejects a missing yyjson writer population", () => {
  const records = validRecords();
  records.pop();
  assert.notEqual(run(records).status, 0);
});

test("rejects a duplicate yyjson writer population", () => {
  const records = validRecords();
  records.push(records[0]);
  assert.notEqual(run(records).status, 0);
});

test("rejects a changed yyjson writer identity", () => {
  const records = validRecords();
  records[0] = { ...records[0], name: records[0].name.replace("1048578", "1048579") };
  assert.notEqual(run(records).status, 0);
});

test("rejects an invalid yyjson writer distribution", () => {
  const records = validRecords();
  records[0] = { ...records[0], median_ns: 0 };
  assert.notEqual(run(records).status, 0);
});

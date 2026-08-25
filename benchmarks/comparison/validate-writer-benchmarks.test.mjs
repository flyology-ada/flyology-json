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
const validator = path.resolve(
  comparisonDirectory,
  "..",
  "..",
  "scripts",
  "validate-writer-benchmarks.mjs",
);

const fixtures = [
  ["small_null", 0, ["bulk"]],
  ["small_boolean", 0, ["bulk"]],
  ["small_number", 0, ["bulk", "1"]],
  ["small_string", 0, ["bulk", "1"]],
  ["large_raw_string", 0, ["bulk", "1"]],
  ["escape_heavy_string", 0, ["bulk", "1"]],
  ["number_heavy_array", 1, ["bulk", "1"]],
  ["nested_structures", 3, ["bulk"]],
];

function validRecords() {
  const records = [];
  for (const [fixture, depth, fragments] of fixtures) {
    for (const fragment of fragments) {
      records.push({
        name: `writer/api=public_writing/fixture=${fixture}/fragment=${fragment}`
          + "/logical_octets=1/output_octets=1/writer_calls=1/destination_calls=1"
          + `/maximum_depth=${depth}/writer_bytes=1/allocations_per_operation=0-contract`
          + "/output_fnv1a64=0123456789abcdef",
        iterations: 1,
        samples: 50,
        median_ns: 1,
      });
    }
  }
  return records;
}

function run(records) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "flyology-json-writer-"));
  const input = path.join(directory, "input.jsonl");
  fs.writeFileSync(input, `${records.map((record) => JSON.stringify(record)).join("\n")}\n`);
  const result = spawnSync(process.execPath, [validator, input], { encoding: "utf8" });
  fs.rmSync(directory, { recursive: true, force: true });
  return result;
}

test("accepts the exact public writer matrix", () => {
  const result = run(validRecords());
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /validated 13 public writer populations/);
});

test("rejects a missing public writer population", () => {
  const records = validRecords();
  records.pop();
  assert.notEqual(run(records).status, 0);
});

test("rejects a duplicate public writer population", () => {
  const records = validRecords();
  records.push(records[0]);
  assert.notEqual(run(records).status, 0);
});

test("rejects a changed writer profile field", () => {
  const records = validRecords();
  records[0] = { ...records[0], name: records[0].name.replace("maximum_depth=0", "maximum_depth=1") };
  assert.notEqual(run(records).status, 0);
});

test("rejects an invalid writer distribution", () => {
  const records = validRecords();
  records[0] = { ...records[0], median_ns: 0 };
  assert.notEqual(run(records).status, 0);
});

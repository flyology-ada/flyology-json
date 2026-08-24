// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import {
  comparisonIdentities,
  fixtureBytes,
} from "./comparison-matrix.mjs";

const comparisonDirectory = path.dirname(fileURLToPath(import.meta.url));
const summarizer = path.resolve(
  comparisonDirectory,
  "..",
  "..",
  "scripts",
  "summarize-comparison-benchmarks.mjs",
);
function validRecords() {
  return comparisonIdentities().map(({ fixture, implementation, lane }) => ({
    name:
      `comparison/lane=${lane}/implementation=${implementation}`
      + `/fixture=${fixture}/bytes=${fixtureBytes.get(fixture)}`,
    samples: 50,
    iterations: 1,
    median_ns: 1,
    cv_percent: 0,
  }));
}

function runInput(contents) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "flyology-json-summary-test-"));
  const input = path.join(directory, "input.jsonl");
  fs.writeFileSync(input, contents);
  const result = spawnSync(process.execPath, [summarizer, "portable", input], {
    encoding: "utf8",
  });
  fs.rmSync(directory, { recursive: true, force: true });
  return result;
}

function run(records) {
  return runInput(`${records.map((record) => JSON.stringify(record)).join("\n")}\n`);
}

test("accepts the exact maintained comparison matrix", () => {
  const result = run(validRecords());
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim().split("\n").length, 64);
});

test("rejects a missing population", () => {
  const records = validRecords();
  records.pop();
  assert.notEqual(run(records).status, 0);
});

test("rejects a duplicate population", () => {
  const records = validRecords();
  records.push(records[0]);
  assert.notEqual(run(records).status, 0);
});

test("rejects a wrong lane", () => {
  const records = validRecords();
  records[0] = { ...records[0], name: records[0].name.replace("parse_events", "parse_dom") };
  assert.notEqual(run(records).status, 0);
});

test("rejects a mismatched fixture size", () => {
  const records = validRecords();
  records[0] = { ...records[0], name: records[0].name.replace("bytes=37", "bytes=38") };
  assert.notEqual(run(records).status, 0);
});

test("rejects a mismatched sample count", () => {
  const records = validRecords();
  records[0] = { ...records[0], samples: 49 };
  assert.notEqual(run(records).status, 0);
});

test("rejects an invalid iteration count", () => {
  const records = validRecords();
  records[0] = { ...records[0], iterations: 0.5 };
  assert.notEqual(run(records).status, 0);
});

test("rejects a negative coefficient of variation", () => {
  const records = validRecords();
  records[0] = { ...records[0], cv_percent: -1 };
  assert.notEqual(run(records).status, 0);
});

test("rejects duplicate JSON record fields", () => {
  const lines = validRecords().map((record) => JSON.stringify(record));
  lines[0] = `{"name":"duplicate",${lines[0].slice(1)}`;
  assert.notEqual(runInput(`${lines.join("\n")}\n`).status, 0);
});

test("rejects malformed UTF-8 before parsing records", () => {
  assert.notEqual(runInput(Buffer.from([0x7b, 0x22, 0xc0, 0xaf, 0x0a])).status, 0);
});

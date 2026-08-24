#!/usr/bin/env node
// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

import fs from "node:fs";
import { requireReviewedNode } from "../benchmarks/comparison/node-toolchain.mjs";
import { parseStrictJson } from "../benchmarks/comparison/strict-json.mjs";
import {
  comparisonIdentities,
  fixtureBytes,
} from "../benchmarks/comparison/comparison-matrix.mjs";

requireReviewedNode();

if (process.argv.length !== 4) {
  console.error("usage: node scripts/summarize-comparison-benchmarks.mjs TRACK INPUT.jsonl");
  process.exit(2);
}

const [, , track, inputPath] = process.argv;
if (track !== "portable" && track !== "native") {
  throw new Error(`unsupported build track: ${track}`);
}

const input = fs.readFileSync(inputPath);
if (input.length === 0 || input[input.length - 1] !== 0x0a) {
  throw new Error("comparison JSONL must end with a newline");
}

const records = [];
let lineStart = 0;
for (let index = 0; index < input.length; index += 1) {
  if (input[index] === 0x0a) {
    try {
      records.push(parseStrictJson(input.subarray(lineStart, index)));
    } catch (error) {
      throw new Error(`invalid JSON on line ${records.length + 1}: ${error.message}`);
    }
    lineStart = index + 1;
  }
}

const namePattern =
  /^comparison\/lane=([^/]+)\/implementation=([^/]+)\/fixture=([^/]+)\/bytes=([0-9]+)$/;
const seen = new Set();
const expected = new Set();
for (const { fixture, implementation, lane } of comparisonIdentities()) {
  expected.add(`${lane}\0${implementation}\0${fixture}`);
}

const rows = records.map((record, index) => {
  const match = namePattern.exec(record.name);
  if (!match) {
    throw new Error(`invalid comparison identity on line ${index + 1}`);
  }
  const [, lane, implementation, fixture, bytesText] = match;
  const identity = `${lane}\0${implementation}\0${fixture}`;
  if (seen.has(identity)) {
    throw new Error(`duplicate comparison identity on line ${index + 1}`);
  }
  if (!expected.delete(identity)) {
    throw new Error(`unexpected comparison identity on line ${index + 1}`);
  }
  seen.add(identity);

  const bytes = Number(bytesText);
  if (!Number.isSafeInteger(bytes) || bytes < 0) {
    throw new Error(`invalid input size on line ${index + 1}`);
  }
  if (bytes !== fixtureBytes.get(fixture)) {
    throw new Error(`unexpected fixture size on line ${index + 1}`);
  }
  for (const field of ["median_ns", "cv_percent"]) {
    if (typeof record[field] !== "number" || !Number.isFinite(record[field])) {
      throw new Error(`invalid ${field} on line ${index + 1}`);
    }
  }
  if (record.median_ns <= 0) {
    throw new Error(`nonpositive median_ns on line ${index + 1}`);
  }
  if (record.cv_percent < 0) {
    throw new Error(`negative cv_percent on line ${index + 1}`);
  }
  if (record.samples !== 50) {
    throw new Error(`unexpected samples on line ${index + 1}`);
  }
  if (!Number.isSafeInteger(record.iterations) || record.iterations < 1) {
    throw new Error(`invalid iterations on line ${index + 1}`);
  }

  const throughput = (bytes * 1_000_000_000) / record.median_ns / 1_048_576;
  if (!Number.isFinite(throughput)) {
    throw new Error(`nonfinite throughput on line ${index + 1}`);
  }

  return {
    track,
    fixture,
    bytes,
    lane,
    implementation,
    median_ns: record.median_ns,
    mib_per_second: throughput,
    cv_percent: record.cv_percent,
  };
});

if (expected.size !== 0) {
  throw new Error(`missing comparison identities: ${[...expected].join(", ")}`);
}

console.log(
  "track\tfixture\tbytes\tlane\timplementation\tmedian_ns\tMiB_per_second\tCV_percent",
);
for (const row of rows) {
  console.log(
    [
      row.track,
      row.fixture,
      row.bytes,
      row.lane,
      row.implementation,
      row.median_ns.toFixed(3),
      row.mib_per_second.toFixed(3),
      row.cv_percent.toFixed(3),
    ].join("\t"),
  );
}

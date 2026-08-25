#!/usr/bin/env node
// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

import fs from "node:fs";
import { requireReviewedNode } from "../benchmarks/comparison/node-toolchain.mjs";
import { parseStrictJson } from "../benchmarks/comparison/strict-json.mjs";
import { yyjsonWriterIdentities } from
  "../benchmarks/comparison/yyjson-writer-matrix.mjs";

requireReviewedNode();

if (process.argv.length !== 3) {
  console.error("usage: node scripts/validate-yyjson-writer-benchmarks.mjs INPUT.jsonl");
  process.exit(2);
}

const expected = new Set(yyjsonWriterIdentities);
const input = fs.readFileSync(process.argv[2]);
if (input.length === 0 || input[input.length - 1] !== 0x0a) {
  throw new Error("yyjson writer JSONL must end with a newline");
}

let lineStart = 0;
let records = 0;
for (let index = 0; index < input.length; index += 1) {
  if (input[index] !== 0x0a) {
    continue;
  }
  let record;
  try {
    record = parseStrictJson(input.subarray(lineStart, index));
  } catch (error) {
    throw new Error(`invalid JSON on line ${records + 1}: ${error.message}`);
  }
  records += 1;
  lineStart = index + 1;

  if (typeof record.name !== "string" || !expected.delete(record.name)) {
    throw new Error(`unexpected or duplicate yyjson writer identity on line ${records}`);
  }
  if (record.samples !== 50 || !Number.isSafeInteger(record.iterations)
      || record.iterations < 1) {
    throw new Error(`invalid yyjson writer sampling policy on line ${records}`);
  }
  for (const field of ["median_ns", "cv_percent"]) {
    if (typeof record[field] !== "number" || !Number.isFinite(record[field])) {
      throw new Error(`invalid ${field} on line ${records}`);
    }
  }
  if (record.median_ns <= 0 || record.cv_percent < 0) {
    throw new Error(`invalid yyjson writer distribution on line ${records}`);
  }
}

if (expected.size !== 0) {
  throw new Error(`missing yyjson writer identities: ${[...expected].join(", ")}`);
}

console.log(`validated ${records} exact yyjson writer populations`);

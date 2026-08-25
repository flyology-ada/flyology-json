#!/usr/bin/env node
// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

import fs from "node:fs";
import { parseStrictJson } from "../benchmarks/comparison/strict-json.mjs";

if (process.argv.length !== 3) {
  console.error("usage: node scripts/validate-writer-benchmarks.mjs INPUT.jsonl");
  process.exit(2);
}

const fixtures = new Map([
  ["small_null", { depth: 0, fragments: ["bulk"] }],
  ["small_boolean", { depth: 0, fragments: ["bulk"] }],
  ["small_number", { depth: 0, fragments: ["bulk", "1"] }],
  ["small_string", { depth: 0, fragments: ["bulk", "1"] }],
  ["large_raw_string", { depth: 0, fragments: ["bulk", "1"] }],
  ["escape_heavy_string", { depth: 0, fragments: ["bulk", "1"] }],
  ["number_heavy_array", { depth: 1, fragments: ["bulk", "1"] }],
  ["nested_structures", { depth: 3, fragments: ["bulk"] }],
]);

const expected = new Set();
for (const [fixture, definition] of fixtures) {
  for (const fragment of definition.fragments) {
    expected.add(`${fixture}/${fragment}`);
  }
}

const identityPattern =
  /^writer\/api=public_writing\/fixture=([^/]+)\/fragment=([^/]+)$/;
const numericField = /^[0-9]+$/;
const hashField = /^[0-9a-f]{16}$/;
const input = fs.readFileSync(process.argv[2]);
if (input.length === 0 || input[input.length - 1] !== 0x0a) {
  throw new Error("writer JSONL must end with a newline");
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

  if (typeof record.name !== "string") {
    throw new Error(`writer record ${records} has no string name`);
  }
  const fields = record.name.split("/");
  const identity = fields.slice(0, 4).join("/");
  const match = identityPattern.exec(identity);
  if (match === null) {
    throw new Error(`invalid writer identity on line ${records}`);
  }
  const [, fixture, fragment] = match;
  const definition = fixtures.get(fixture);
  const population = `${fixture}/${fragment}`;
  if (definition === undefined || !expected.delete(population)) {
    throw new Error(`unexpected or duplicate writer population ${population}`);
  }

  const values = new Map();
  for (const field of fields.slice(4)) {
    const separator = field.indexOf("=");
    if (separator < 1 || values.has(field.slice(0, separator))) {
      throw new Error(`invalid writer identity field on line ${records}`);
    }
    values.set(field.slice(0, separator), field.slice(separator + 1));
  }
  for (const field of [
    "logical_octets",
    "output_octets",
    "writer_calls",
    "destination_calls",
    "maximum_depth",
    "writer_bytes",
  ]) {
    if (!numericField.test(values.get(field) ?? "")) {
      throw new Error(`invalid ${field} on line ${records}`);
    }
  }
  if (Number(values.get("maximum_depth")) !== definition.depth) {
    throw new Error(`unexpected maximum_depth on line ${records}`);
  }
  for (const field of ["logical_octets", "output_octets", "writer_calls", "writer_bytes"]) {
    if (Number(values.get(field)) < 1) {
      throw new Error(`nonpositive ${field} on line ${records}`);
    }
  }
  if (values.get("allocations_per_operation") !== "0-contract") {
    throw new Error(`writer allocation contract changed on line ${records}`);
  }
  if (!hashField.test(values.get("output_fnv1a64") ?? "")) {
    throw new Error(`invalid output checksum on line ${records}`);
  }
  if (record.samples !== 50 || !Number.isSafeInteger(record.iterations)
      || record.iterations < 1 || typeof record.median_ns !== "number"
      || !Number.isFinite(record.median_ns) || record.median_ns <= 0) {
    throw new Error(`invalid writer sampling result on line ${records}`);
  }
}

if (expected.size !== 0) {
  throw new Error(`missing writer populations: ${[...expected].join(", ")}`);
}

console.log(`validated ${records} public writer populations`);

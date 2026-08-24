#!/usr/bin/env node
// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

import fs from "node:fs";
import process from "node:process";
import { requireReviewedNode } from "../benchmarks/comparison/node-toolchain.mjs";
import { comparisonIdentities } from "../benchmarks/comparison/comparison-matrix.mjs";

requireReviewedNode();

if (process.argv.length !== 3) {
  console.error("usage: node scripts/validate-comparison-preflight.mjs INPUT.txt");
  process.exit(2);
}

const input = fs.readFileSync(process.argv[2], "utf8");
if (!input.endsWith("\n")) {
  throw new Error("comparison preflight output must end with a newline");
}

const expected = new Set(
  comparisonIdentities().map(({ implementation, fixture }) => `${implementation}\0${fixture}`),
);
const lines = input.slice(0, -1).split("\n");
const pattern = /^implementation=([^ ]+) fixture=([^ ]+) value=([0-9]+)$/;
for (const [index, line] of lines.entries()) {
  const match = pattern.exec(line);
  if (!match) {
    throw new Error(`invalid comparison preflight line ${index + 1}`);
  }
  const identity = `${match[1]}\0${match[2]}`;
  if (!expected.delete(identity)) {
    throw new Error(`duplicate or unexpected comparison preflight line ${index + 1}`);
  }
}

if (expected.size !== 0) {
  throw new Error(`missing comparison preflight identities: ${[...expected].join(", ")}`);
}

console.log(`validated ${lines.length} exact comparison preflight populations`);

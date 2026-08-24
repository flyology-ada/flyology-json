#!/usr/bin/env node
// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

import fs from "node:fs";
import process from "node:process";
import {
  parseParserIdentity,
  parserIdentities,
} from "../benchmarks/comparison/parser-matrix.mjs";
import { requireReviewedNode } from "../benchmarks/comparison/node-toolchain.mjs";

requireReviewedNode();

if (process.argv.length !== 3) {
  console.error("usage: node scripts/validate-parser-preflight.mjs INPUT.txt");
  process.exit(2);
}

const input = fs.readFileSync(process.argv[2], "utf8");
if (!input.endsWith("\n")) {
  throw new Error("parser preflight output must end with a newline");
}

const expected = new Set(parserIdentities());
const lines = input.slice(0, -1).split("\n");
for (const [index, line] of lines.entries()) {
  let identity;
  try {
    identity = parseParserIdentity(line).identity;
  } catch (error) {
    throw new Error(`invalid parser preflight line ${index + 1}: ${error.message}`);
  }
  if (!expected.delete(identity)) {
    throw new Error(`duplicate or unexpected parser preflight line ${index + 1}`);
  }
}

if (expected.size !== 0) {
  throw new Error(`missing parser preflight identities: ${[...expected].join(", ")}`);
}

console.log(`validated ${lines.length} exact parser preflight populations`);

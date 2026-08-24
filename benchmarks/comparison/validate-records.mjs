// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";
import { requireReviewedNode } from "./node-toolchain.mjs";
import { parseStrictJson } from "./strict-json.mjs";

requireReviewedNode();

const argumentsAfterNode = process.argv.slice(2);
const schemaOnly = argumentsAfterNode[0] === "--schema-only";
const schemaArgument = argumentsAfterNode[schemaOnly ? 1 : 0];
const recordArguments = argumentsAfterNode.slice(schemaOnly ? 2 : 1);

if (
  schemaArgument === undefined ||
  (!schemaOnly && recordArguments.length === 0) ||
  (schemaOnly && recordArguments.length !== 0)
) {
  console.error("usage: node validate-records.mjs [--schema-only] SCHEMA [RECORD...]");
  process.exit(2);
}

function parseJson(filePath) {
  return parseStrictJson(fs.readFileSync(filePath));
}

const schemaPath = path.resolve(schemaArgument);
const schema = parseJson(schemaPath);
const capabilityMode = path.basename(schemaPath) === "capability.schema.json";

function readSourceLocks() {
  const manifestPath = path.join(path.dirname(schemaPath), "sources.lock.tsv");
  const locks = new Map();
  for (const [index, line] of fs.readFileSync(manifestPath, "utf8").split(/\r?\n/).entries()) {
    if (line.length === 0 || line.startsWith("#")) {
      continue;
    }
    const fields = line.split("|");
    if (fields.length !== 11) {
      throw new Error(`${manifestPath}:${index + 1}: expected 11 source-lock fields`);
    }
    const [sourceId, , revision] = fields;
    if (locks.has(sourceId)) {
      throw new Error(`${manifestPath}:${index + 1}: duplicate source_id ${sourceId}`);
    }
    locks.set(sourceId, revision);
  }
  return locks;
}

const sourceLocks = capabilityMode ? readSourceLocks() : null;

function auditSchemaNumericConstraints(value, location = "#") {
  if (value === null || typeof value !== "object") {
    return;
  }
  for (const [key, child] of Object.entries(value)) {
    const childLocation = `${location}/${key}`;
    if (["maximum", "exclusiveMaximum", "multipleOf"].includes(key)) {
      throw new Error(`${schemaPath}: unsupported exact numeric constraint at ${childLocation}`);
    }
    if (
      ["minimum", "exclusiveMinimum"].includes(key) &&
      !Number.isSafeInteger(child)
    ) {
      throw new Error(`${schemaPath}: numeric lower bound is not an exact integer`);
    }
    if (
      (key === "const" && typeof child === "number") ||
      (key === "enum" && Array.isArray(child) && child.some((item) => typeof item === "number"))
    ) {
      throw new Error(`${schemaPath}: numeric ${key} requires a lossless schema validator`);
    }
    auditSchemaNumericConstraints(child, childLocation);
  }
}

auditSchemaNumericConstraints(schema);
const ajv = new Ajv2020({ allErrors: true, strict: true });
addFormats(ajv);
const validator = ajv.compile(schema);

if (schemaOnly) {
  console.log(`${schemaPath}: schema compiled`);
  process.exit(0);
}

let valid = true;
const recordPaths = [];

function collectRecords(candidate) {
  const candidatePath = path.resolve(candidate);
  if (!fs.existsSync(candidatePath)) {
    throw new Error(`record path does not exist: ${candidatePath}`);
  }

  const metadata = fs.statSync(candidatePath);
  if (!metadata.isDirectory()) {
    recordPaths.push(candidatePath);
    return;
  }

  for (const entry of fs.readdirSync(candidatePath, { withFileTypes: true })) {
    const entryPath = path.join(candidatePath, entry.name);
    if (
      entry.isDirectory() &&
      // Generated build and acquired-source directories never own records.
      !["alire", "bin", "node_modules", "obj", "target", "upstream"].includes(entry.name)
    ) {
      collectRecords(entryPath);
    } else if (
      entry.name === "capability.json" ||
      (path.basename(candidatePath) === "capabilities" && entry.name.endsWith(".json"))
    ) {
      recordPaths.push(entryPath);
    }
  }
}

for (const argument of recordArguments) {
  collectRecords(argument);
}

if (recordPaths.length === 0) {
  throw new Error("no records found");
}

function uniqueIds(records, field, label, recordPath) {
  const seen = new Set();
  for (const record of records) {
    const identifier = record[field];
    if (seen.has(identifier)) {
      throw new Error(`${recordPath}: duplicate ${label} identifier: ${identifier}`);
    }
    seen.add(identifier);
  }
  return seen;
}

function validateCapabilityReferences(record, recordPath, capabilitySchema) {
  const lockedRevision = sourceLocks.get(record.source_id);
  if (lockedRevision === undefined) {
    throw new Error(`${recordPath}: unknown source_id ${record.source_id}`);
  }
  if (record.source_revision !== lockedRevision) {
    throw new Error(
      `${recordPath}: source_revision ${record.source_revision} does not match locked ${lockedRevision}`,
    );
  }

  const lanes = uniqueIds(record.lanes, "lane", "lane", recordPath);
  const profiles = uniqueIds(record.profiles, "profile_id", "profile", recordPath);
  const outputPolicies = uniqueIds(
    record.output_policies,
    "output_policy_id",
    "output policy",
    recordPath,
  );

  const expectedLanes = new Set(capabilitySchema.$defs.lane.properties.lane.enum);
  const writerLanes = new Set(
    [...expectedLanes].filter((lane) => lane.startsWith("write_") || lane === "parse_write"),
  );
  const missingLanes = [...expectedLanes].filter((lane) => !lanes.has(lane));
  if (lanes.size !== expectedLanes.size || missingLanes.length !== 0) {
    throw new Error(
      `${recordPath}: capability must declare every schema lane; missing ${missingLanes.join(", ")}`,
    );
  }

  for (const lane of record.lanes) {
    if (lane.supported) {
      if (lane.api.length === 0 || lane.observable_result.length === 0) {
        throw new Error(`${recordPath}: supported lane ${lane.lane} lacks an API or observation`);
      }
      if (lane.profile_ids.length === 0) {
        throw new Error(`${recordPath}: supported lane ${lane.lane} lacks an applied profile`);
      }
      if (writerLanes.has(lane.lane) && lane.output_policy_ids.length === 0) {
        throw new Error(`${recordPath}: supported writer lane ${lane.lane} lacks an output policy`);
      }
    } else if (lane.profile_ids.length !== 0 || lane.output_policy_ids.length !== 0) {
      throw new Error(`${recordPath}: unsupported lane ${lane.lane} declares admitted bindings`);
    }

    for (const profile of lane.profile_ids) {
      if (!profiles.has(profile)) {
        throw new Error(`${recordPath}: lane ${lane.lane} references unknown profile ${profile}`);
      }
    }
    for (const policy of lane.output_policy_ids) {
      if (!outputPolicies.has(policy)) {
        throw new Error(
          `${recordPath}: lane ${lane.lane} references unknown output policy ${policy}`,
        );
      }
    }
  }
}

const implementationIds = new Set();
for (const recordPath of recordPaths.sort()) {
  const record = parseJson(recordPath);
  if (!validator(record)) {
    valid = false;
    console.error(`${recordPath}: schema validation failed`);
    console.error(JSON.stringify(validator.errors, null, 2));
  } else if (capabilityMode) {
    if (implementationIds.has(record.implementation_id)) {
      throw new Error(
        `${recordPath}: duplicate implementation identifier: ${record.implementation_id}`,
      );
    }
    implementationIds.add(record.implementation_id);
    validateCapabilityReferences(record, recordPath, schema);
  }
}

if (!valid) {
  process.exitCode = 1;
}

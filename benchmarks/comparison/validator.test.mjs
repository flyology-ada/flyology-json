// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { requireReviewedNode } from "./node-toolchain.mjs";
import { parseStrictJson } from "./strict-json.mjs";

requireReviewedNode();

const root = import.meta.dirname;
const schema = path.join(root, "capability.schema.json");
const sourceCapability = path.join(root, "../competitors/yyjson/capability.json");

function validate(recordPath) {
  return spawnSync(process.execPath, [path.join(root, "validate-records.mjs"), schema, recordPath], {
    encoding: "utf8",
  });
}

function withCapability(change, check) {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "flyology-json-validator-"));
  try {
    const capability = parseStrictJson(fs.readFileSync(sourceCapability));
    change(capability);
    const recordPath = path.join(temporary, "capability.json");
    fs.writeFileSync(recordPath, `${JSON.stringify(capability)}\n`);
    check(validate(recordPath));
  } finally {
    fs.rmSync(temporary, { recursive: true });
  }
}

test("all committed schemas compile in strict mode", () => {
  for (const name of ["capability.schema.json", "result.schema.json", "skip.schema.json"]) {
    const result = spawnSync(
      process.execPath,
      [path.join(root, "validate-records.mjs"), "--schema-only", path.join(root, name)],
      { encoding: "utf8" },
    );
    assert.equal(result.status, 0, result.stderr);
  }
});

test("schema-only mode rejects extra operands and unsupported exact constraints", () => {
  const extra = spawnSync(
    process.execPath,
    [path.join(root, "validate-records.mjs"), "--schema-only", schema, sourceCapability],
    { encoding: "utf8" },
  );
  assert.equal(extra.status, 2);

  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "flyology-json-validator-"));
  try {
    const schemaPath = path.join(temporary, "schema.json");
    fs.writeFileSync(schemaPath, '{"type":"number","maximum":1}');
    const result = spawnSync(
      process.execPath,
      [path.join(root, "validate-records.mjs"), "--schema-only", schemaPath],
      { encoding: "utf8" },
    );
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /unsupported exact numeric constraint/);
  } finally {
    fs.rmSync(temporary, { recursive: true });
  }
});

test("missing and empty record locations fail", () => {
  const missing = validate(path.join(os.tmpdir(), "flyology-json-record-does-not-exist"));
  assert.notEqual(missing.status, 0);
  assert.match(missing.stderr, /record path does not exist/);

  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "flyology-json-validator-"));
  try {
    const empty = validate(temporary);
    assert.notEqual(empty.status, 0);
    assert.match(empty.stderr, /no records found/);
  } finally {
    fs.rmSync(temporary, { recursive: true });
  }
});

test("valid capability passes", () => {
  const result = validate(sourceCapability);
  assert.equal(result.status, 0, result.stderr);
});

test("capability source identity must match the reviewed lock", () => {
  withCapability(
    (capability) => {
      capability.source_revision = "unreviewed";
    },
    (result) => {
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /does not match locked/);
    },
  );
});

test("implementation identifiers are unique across one validation", () => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "flyology-json-validator-"));
  try {
    const capabilities = path.join(temporary, "capabilities");
    fs.mkdirSync(capabilities);
    const capability = fs.readFileSync(sourceCapability);
    fs.writeFileSync(path.join(capabilities, "first.json"), capability);
    fs.writeFileSync(path.join(capabilities, "second.json"), capability);
    const result = validate(capabilities);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /duplicate implementation identifier/);
  } finally {
    fs.rmSync(temporary, { recursive: true });
  }
});

test("duplicate decoded keys fail before schema validation", () => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "flyology-json-validator-"));
  try {
    const recordPath = path.join(temporary, "capability.json");
    fs.writeFileSync(recordPath, '{"implementation_id":"a","\\u0069mplementation_id":"b"}');
    const result = validate(recordPath);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /duplicate object name/);
  } finally {
    fs.rmSync(temporary, { recursive: true });
  }
});

test("supported lanes require observations and applied profiles", () => {
  withCapability(
    (capability) => {
      capability.lanes.find((lane) => lane.supported).api = "";
    },
    (result) => {
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /lacks an API or observation/);
    },
  );
});

test("unsupported lanes cannot declare admitted bindings", () => {
  withCapability(
    (capability) => {
      capability.lanes.find((lane) => !lane.supported).profile_ids = [
        capability.profiles[0].profile_id,
      ];
    },
    (result) => {
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /unsupported lane/);
    },
  );
});

test("dangling profiles and missing lanes fail", () => {
  withCapability(
    (capability) => {
      capability.lanes.find((lane) => lane.supported).profile_ids = ["missing-profile"];
    },
    (result) => {
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /unknown profile/);
    },
  );
  withCapability(
    (capability) => {
      capability.lanes.pop();
    },
    (result) => {
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /must declare every schema lane/);
    },
  );
});

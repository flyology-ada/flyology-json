// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

import assert from "node:assert/strict";
import test from "node:test";
import { requireReviewedNode } from "./node-toolchain.mjs";
import { parseStrictJson } from "./strict-json.mjs";

requireReviewedNode();

test("accepts strict JSON including empty object names", () => {
  assert.deepEqual(parseStrictJson(Buffer.from('{"":{"x":1},"a":[true,null]}')), {
    "": { x: 1 },
    a: [true, null],
  });
});

test("rejects decoded duplicate names", () => {
  assert.throws(() => parseStrictJson(Buffer.from('{"a":1,"\\u0061":2}')), /duplicate/);
});

test("rejects non-JSON escapes and whitespace", () => {
  assert.throws(() => parseStrictJson(Buffer.from('{"a":"\\x61"}')), SyntaxError);
  assert.throws(() => parseStrictJson(Buffer.from("{\u00a0}")), SyntaxError);
});

test("rejects a UTF-8 BOM and malformed UTF-8", () => {
  assert.throws(() => parseStrictJson(Buffer.from([0xef, 0xbb, 0xbf, 0x7b, 0x7d])), SyntaxError);
  assert.throws(() => parseStrictJson(Buffer.from([0x7b, 0xff, 0x7d])), TypeError);
});

test("rejects unpaired surrogate escapes", () => {
  assert.throws(() => parseStrictJson(Buffer.from('{"x":"\\ud800"}')), /surrogate/);
  assert.throws(() => parseStrictJson(Buffer.from('{"x":"\\udc00"}')), /surrogate/);
  assert.deepEqual(parseStrictJson(Buffer.from('{"x":"\\ud83d\\ude80"}')), { x: "🚀" });
});

test("rejects numeric precision loss before schema validation", () => {
  assert.throws(() => parseStrictJson(Buffer.from('{"x":0.99999999999999999}')), /precision/);
  assert.deepEqual(parseStrictJson(Buffer.from('{"x":1e400,"y":-1e400}')), {
    x: Number.MAX_VALUE,
    y: -Number.MAX_VALUE,
  });
  assert.deepEqual(parseStrictJson(Buffer.from('{"x":1.25,"y":9007199254740992}')), {
    x: 1.25,
    y: 9007199254740992,
  });
});

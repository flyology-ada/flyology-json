// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

import { TextDecoder } from "node:util";

// Preserve a leading U+FEFF so JSON.parse rejects a UTF-8 BOM instead of
// letting TextDecoder silently strip it.
const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });

function skipWhitespace(text, start) {
  let index = start;
  while (
    index < text.length &&
    (text[index] === " " || text[index] === "\t" || text[index] === "\n" || text[index] === "\r")
  ) {
    index += 1;
  }
  return index;
}

function requireUnicodeScalars(value) {
  for (let index = 0; index < value.length; index += 1) {
    const unit = value.charCodeAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const next = value.charCodeAt(index + 1);
      if (!(next >= 0xdc00 && next <= 0xdfff)) {
        throw new SyntaxError("JSON record contains an unpaired high surrogate");
      }
      index += 1;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw new SyntaxError("JSON record contains an unpaired low surrogate");
    }
  }
}

function validateNumberLexeme(lexeme) {
  const match = /^(-?)([0-9]+)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$/.exec(lexeme);
  if (match === null) {
    return;
  }

  const fraction = match[3] ?? "";
  const exponent = Number(match[4] ?? "0");
  const scale = fraction.length - exponent;
  const digits = `${match[2]}${fraction}`;
  const removed = scale > 0 ? digits.slice(Math.max(0, digits.length - scale)) : "";
  const mathematicalInteger = scale <= 0 || removed.length === 0 || /^0+$/.test(removed);
  const converted = Number(lexeme);

  if (!mathematicalInteger && Number.isInteger(converted)) {
    throw new RangeError("JSON record fraction loses precision before schema validation");
  }
}

function replaceNonFiniteIntegers(value) {
  if (typeof value === "number" && !Number.isFinite(value)) {
    return value < 0 ? -Number.MAX_VALUE : Number.MAX_VALUE;
  }
  if (Array.isArray(value)) {
    for (let index = 0; index < value.length; index += 1) {
      value[index] = replaceNonFiniteIntegers(value[index]);
    }
  } else if (value !== null && typeof value === "object") {
    for (const key of Object.keys(value)) {
      value[key] = replaceNonFiniteIntegers(value[key]);
    }
  }
  return value;
}

function scanString(text, start) {
  let index = start + 1;
  while (text[index] !== '"') {
    if (text[index] === "\\") {
      index += 1;
    }
    index += 1;
  }
  const end = index + 1;
  const value = JSON.parse(text.slice(start, end));
  requireUnicodeScalars(value);
  return [value, end];
}

function scanValue(text, start) {
  let index = skipWhitespace(text, start);
  if (text[index] === '"') {
    return scanString(text, index)[1];
  }
  if (text[index] === "[") {
    index = skipWhitespace(text, index + 1);
    if (text[index] === "]") {
      return index + 1;
    }
    while (true) {
      index = skipWhitespace(text, scanValue(text, index));
      if (text[index] === "]") {
        return index + 1;
      }
      index = skipWhitespace(text, index + 1);
    }
  }
  if (text[index] === "{") {
    const names = new Set();
    index = skipWhitespace(text, index + 1);
    if (text[index] === "}") {
      return index + 1;
    }
    while (true) {
      const [name, afterName] = scanString(text, index);
      if (names.has(name)) {
        throw new SyntaxError(`duplicate object name: ${JSON.stringify(name)}`);
      }
      names.add(name);
      index = skipWhitespace(text, afterName);
      index = skipWhitespace(text, index + 1);
      index = skipWhitespace(text, scanValue(text, index));
      if (text[index] === "}") {
        return index + 1;
      }
      index = skipWhitespace(text, index + 1);
    }
  }

  const primitiveStart = index;
  while (index < text.length && !" \t\r\n,]}".includes(text[index])) {
    index += 1;
  }
  validateNumberLexeme(text.slice(primitiveStart, index));
  return index;
}

export function parseStrictJson(bytes) {
  const text = decoder.decode(bytes);
  const value = JSON.parse(text);
  const end = skipWhitespace(text, scanValue(text, 0));
  if (end !== text.length) {
    throw new SyntaxError("JSON record has unconsumed input");
  }
  // Ajv uses JavaScript numbers. The schema validator separately rejects
  // exact constraints that could distinguish a huge integer's magnitude;
  // retain its sign as a finite integer proxy for type and lower-bound checks.
  return replaceNonFiniteIntegers(value);
}

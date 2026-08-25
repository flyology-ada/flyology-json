import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const fixtures = ["structure", "escaping", "depth", "annotations"];

for (const fixture of fixtures) {
  const source = await readFile(
    new URL(`./golden/${fixture}.hex`, import.meta.url),
    "utf8",
  );
  const hex = source.trim();

  assert.match(hex, /^(?:[0-9a-f]{2})+$/, `${fixture}: malformed hex oracle`);
  const bytes = Buffer.from(hex, "hex");
  assert.notEqual(bytes[0], 0xef, `${fixture}: unexpected UTF-8 BOM`);
  assert.notEqual(bytes[bytes.length - 1], 0x0a, `${fixture}: unexpected final LF`);

  const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  JSON.parse(text);
}

console.log(`writer independent oracle: ${fixtures.length} golden documents accepted by Node JSON.parse`);

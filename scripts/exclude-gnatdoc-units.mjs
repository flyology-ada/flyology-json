#!/usr/bin/env node

import { readFile, unlink, writeFile } from "node:fs/promises";
import { basename, join, resolve } from "node:path";

if (process.argv.length !== 4) {
  console.error(
    "usage: node scripts/exclude-gnatdoc-units.mjs <api-directory> <excluded-units>",
  );
  process.exit(2);
}

const apiRoot = resolve(process.argv[2]);
const excludedSource = await readFile(resolve(process.argv[3]), "utf8");
const excluded = excludedSource
  .split(/\r?\n/)
  .map((line) => line.trim())
  .filter((line) => line !== "" && !line.startsWith("#"));
const indexPath = join(apiRoot, "index.html");
let index = await readFile(indexPath, "utf8");

for (const unit of excluded) {
  const escaped = unit.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const expression = new RegExp(
    `<li><a\\s+href=(?:"([^"#]+\\.html)"|'([^'#]+\\.html)'|([^\\s>#]+\\.html))[^>]*>` +
      `${escaped}<\\/a>`,
    "g",
  );
  const matches = [...index.matchAll(expression)];
  if (matches.length !== 1) {
    throw new Error(`expected exactly one generated page for excluded unit ${unit}`);
  }
  const href = matches[0][1] || matches[0][2] || matches[0][3];
  if (basename(href) !== href) throw new Error(`unsafe generated unit page path: ${href}`);
  index = index.replace(matches[0][0], "");
  await unlink(join(apiRoot, href));
}

await writeFile(indexPath, index);
console.log(`Excluded ${excluded.length} generated non-API unit page(s).`);

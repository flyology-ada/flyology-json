#!/usr/bin/env node

import { readdir, readFile, stat } from "node:fs/promises";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const websiteRoot = resolve(process.argv[2] || join(projectRoot, "website"));

if (!(await stat(websiteRoot).catch(() => null))?.isDirectory()) {
  throw new Error(`website directory does not exist: ${websiteRoot}`);
}

async function walk(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await walk(path));
    else files.push(path);
  }
  return files;
}

function decodeHtml(value) {
  const named = new Map([
    ["amp", "&"], ["apos", "'"], ["gt", ">"], ["lt", "<"], ["quot", '"'],
  ]);
  return value.replace(/&(#(?:x[0-9a-f]+|[0-9]+)|[a-z]+);/gi, (match, entity) => {
    if (!entity.startsWith("#")) return named.get(entity.toLowerCase()) ?? match;
    const hexadecimal = entity[1].toLowerCase() === "x";
    const codePoint = Number.parseInt(entity.slice(hexadecimal ? 2 : 1), hexadecimal ? 16 : 10);
    if (!Number.isInteger(codePoint) || codePoint < 0 || codePoint > 0x10ffff) return match;
    return String.fromCodePoint(codePoint);
  });
}

function attribute(attributes, name) {
  const match = attributes.match(
    new RegExp(`\\b${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)')`, "i"),
  );
  return match ? decodeHtml(match[1] ?? match[2]) : null;
}

function sourceRegion(source, name, sourcePath) {
  const lines = source.split(/(?<=\n)/);
  const begin = `--  BEGIN ${name}\n`;
  const end = `--  END ${name}\n`;
  const beginIndexes = lines.flatMap((line, index) => line.trimStart() === begin ? [index] : []);
  const endIndexes = lines.flatMap((line, index) => line.trimStart() === end ? [index] : []);
  if (beginIndexes.length !== 1 || endIndexes.length !== 1 || endIndexes[0] <= beginIndexes[0]) {
    throw new Error(`${sourcePath}: expected one ordered BEGIN/END marker pair for ${name}`);
  }
  return lines.slice(beginIndexes[0] + 1, endIndexes[0]).join("");
}

let verified = 0;
for (const htmlPath of (await walk(websiteRoot)).filter((path) => path.endsWith(".html"))) {
  const html = await readFile(htmlPath, "utf8");
  const blocks = html.matchAll(/<code\b([^>]*)>([\s\S]*?)<\/code>/gi);
  for (const block of blocks) {
    const sourceName = attribute(block[1], "data-example-source");
    const regionName = attribute(block[1], "data-example-region");
    if (!sourceName && !regionName) continue;
    if (!sourceName || !regionName) {
      throw new Error(`${htmlPath}: executable example requires source and region attributes`);
    }
    if (!sourceName.startsWith("examples/") || sourceName.split("/").includes("..")) {
      throw new Error(`${htmlPath}: unsafe example source path: ${sourceName}`);
    }
    if (!/^[A-Za-z0-9_-]+$/.test(regionName)) {
      throw new Error(`${htmlPath}: invalid example region name: ${regionName}`);
    }
    if (/<[^>]+>/.test(block[2])) {
      throw new Error(`${htmlPath}: executable example code must not contain nested HTML`);
    }

    const sourcePath = resolve(projectRoot, sourceName);
    const fromRoot = relative(projectRoot, sourcePath);
    if (fromRoot === ".." || fromRoot.startsWith(`..${sep}`)) {
      throw new Error(`${htmlPath}: example source escapes the project root`);
    }
    const source = (await readFile(sourcePath, "utf8")).replaceAll("\r\n", "\n");
    const expected = sourceRegion(source, regionName, sourceName);
    const actual = decodeHtml(block[2]).replaceAll("\r\n", "\n");
    if (actual !== expected) {
      throw new Error(
        `${htmlPath}: example ${sourceName} region ${regionName} does not match source bytes`,
      );
    }
    verified += 1;
  }
}

if (verified === 0) throw new Error("website contains no source-verified examples");
console.log(`Verified ${verified} website example block(s) against maintained sources.`);

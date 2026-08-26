#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

if (process.argv.length !== 6) {
  console.error(
    "usage: node scripts/check-gnatdoc-diagnostics.mjs " +
      "<log> <expected-diagnostics> <public-units> <project-root>",
  );
  process.exit(2);
}

const [logPath, expectedPath, publicUnitsPath, projectRootArgument] = process.argv.slice(2);
const projectRoot = resolve(projectRootArgument);
const log = (await readFile(logPath, "utf8")).replaceAll("\r\n", "\n");
const expectedSource = (await readFile(expectedPath, "utf8")).replaceAll("\r\n", "\n");
const publicUnitsSource = (await readFile(publicUnitsPath, "utf8")).replaceAll("\r\n", "\n");

function normalize(value) {
  return value
    .replaceAll(projectRoot, "$PROJECT_ROOT")
    .replaceAll("\\", "/")
    .trim();
}

const warnings = [];
const publicWarnings = [];
const omissions = [];
const publicSourceNames = new Set(
  publicUnitsSource
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line !== "" && !line.startsWith("#"))
    .map((unitName) => `${unitName.toLowerCase().replaceAll(".", "-")}.ads`),
);
const lines = log.split("\n");
for (let index = 0; index < lines.length; index += 1) {
  const line = lines[index];
  if (/warning:/i.test(line)) {
    const normalizedLine = normalize(line);
    warnings.push("warning\t" + normalizedLine);
    const sourceName = normalizedLine.match(/(?:^|\/)([^/:]+\.ads):\d+:\d+: warning:/i)?.[1];
    if (sourceName && publicSourceNames.has(sourceName.toLowerCase())) {
      publicWarnings.push(normalizedLine);
    }
  }

  if (/raised GNATDOC\.[A-Z_]+/.test(line)) {
    const declaration = line.match(/\["([^"]+)"\]/)?.[1] || "<unknown declaration>";
    omissions.push("omission\t" + normalize(declaration));
  } else if (/GNATdoc.*internal error|internal error.*GNATdoc/i.test(line)) {
    console.error("GNATdoc reported an internal error: " + normalize(line));
    process.exit(1);
  }
}

if (publicWarnings.length !== 0) {
  console.error("GNATdoc reported undocumented entities in installed public units:");
  for (const warning of publicWarnings) console.error(`  ${warning}`);
  process.exit(1);
}

const expectedLines = expectedSource
  .split("\n")
  .map((line) => line.trim())
  .filter((line) => line !== "" && !line.startsWith("#"));
const expectedCount = Number.parseInt(
  expectedLines.find((line) => line.startsWith("warning-count="))?.split("=", 2)[1] || "",
  10,
);
const expectedDigest = expectedLines
  .find((line) => line.startsWith("warning-sha256="))
  ?.split("=", 2)[1];
const expectedOmissions = expectedLines.filter((line) => line.startsWith("omission\t"));

if (!Number.isInteger(expectedCount) || !/^[0-9a-f]{64}$/.test(expectedDigest || "")) {
  throw new Error("GNATdoc diagnostics file needs an exact warning count and SHA-256");
}

warnings.sort();
omissions.sort();
expectedOmissions.sort();
const warningDigest = createHash("sha256")
  .update(warnings.length === 0 ? "" : `${warnings.join("\n")}\n`)
  .digest("hex");

if (warnings.length !== expectedCount || warningDigest !== expectedDigest) {
  console.error("GNATdoc diagnostics differ from docs/gnatdoc-diagnostics.txt.");
  console.error(`Expected warnings: ${expectedCount}, SHA-256 ${expectedDigest}`);
  console.error(`Actual warnings:   ${warnings.length}, SHA-256 ${warningDigest}`);
  process.exit(1);
}

if (JSON.stringify(omissions) !== JSON.stringify(expectedOmissions)) {
  console.error("GNATdoc omitted declarations differ from the exact reviewed list.");
  console.error("Expected omissions:");
  for (const line of expectedOmissions) console.error("  " + line);
  console.error("Actual omissions:");
  for (const line of omissions) console.error("  " + line);
  process.exit(1);
}

console.log(
  `GNATdoc diagnostics match exactly: ${warnings.length} warning(s), ` +
    `${omissions.length} reviewed omission(s), 0 public warning(s).`,
);

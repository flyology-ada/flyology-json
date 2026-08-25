#!/usr/bin/env node

import { readFile, stat } from "node:fs/promises";
import { join, resolve } from "node:path";

const siteRoot = resolve(process.argv[2]);
const llmsPath = join(siteRoot, "llms.txt");
const supportPath = join(siteRoot, "support/index.html");
const llms = await readFile(llmsPath, "utf8");
const supportHtml = await readFile(supportPath, "utf8");
const support = supportHtml
  .replace(/<script\b[\s\S]*?<\/script>/gi, " ")
  .replace(/<style\b[\s\S]*?<\/style>/gi, " ")
  .replace(/<[^>]+>/g, " ")
  .replace(/\s+/g, " ");

const requiredRoutes = [
  "/",
  "/guide/",
  "/guide/getting-started/",
  "/guide/parsing/",
  "/guide/writing/",
  "/guide/tokens-and-numbers/",
  "/guide/profiles-and-errors/",
  "/architecture/",
  "/support/",
  "/api/",
];

for (const route of requiredRoutes) {
  const absolute = `https://json.flyology.org${route}`;
  if (!llms.includes(absolute) && !llms.includes(`(${route})`)) {
    throw new Error(`llms.txt does not list ${route}`);
  }
  const target = route === "/" ? join(siteRoot, "index.html") : join(siteRoot, route, "index.html");
  if (!(await stat(target).catch(() => null))?.isFile()) {
    throw new Error(`llms.txt route has no built page: ${route}`);
  }
}

const boundaryPhrases = [
  "experimental",
  "0.1.0-dev",
  "Flyology Alire index",
  "signed",
  "unsigned",
  "Binary64",
  "decimal",
  "accounting",
  "canonical",
  "DOM",
  "Type IR",
  "Wire",
];
for (const phrase of boundaryPhrases) {
  if (!llms.toLowerCase().includes(phrase.toLowerCase())) {
    throw new Error(`llms.txt omits boundary phrase: ${phrase}`);
  }
  if (!support.toLowerCase().includes(phrase.toLowerCase())) {
    throw new Error(`support page omits boundary phrase: ${phrase}`);
  }
}

for (const forbidden of ["Serde"]) {
  if (llms.toLowerCase().includes(forbidden.toLowerCase())) {
    throw new Error(`llms.txt mentions unreleased consumer: ${forbidden}`);
  }
  if (support.toLowerCase().includes(forbidden.toLowerCase())) {
    throw new Error(`support page mentions unreleased consumer: ${forbidden}`);
  }
}

console.log(
  `Verified llms.txt routes and ${boundaryPhrases.length} support-boundary phrase(s).`,
);

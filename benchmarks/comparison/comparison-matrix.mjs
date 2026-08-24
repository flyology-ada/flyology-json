// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

export const fixtureBytes = new Map([
  ["small_mixed", 37],
  ["large_mixed", 564_139],
  ["string_heavy", 1_081_355],
  ["number_heavy", 286_721],
  ["long_mantissa_numbers", 884_737],
  ["deep_nesting", 513],
  ["large_array", 294_913],
  ["large_object", 283_803],
]);

export const implementationLanes = new Map([
  ["flyology_json", "parse_events"],
  ["rapidjson-sax", "parse_events"],
  ["yyjson", "parse_validate"],
  ["simdjson", "parse_dom"],
  ["rapidjson", "parse_dom"],
  ["serde_json", "parse_dom"],
  ["sonic-rs", "parse_dom"],
  ["simd-json", "parse_dom"],
]);

export function isSupported(implementation, fixture) {
  return !(implementation === "serde_json" && fixture === "deep_nesting");
}

export function comparisonIdentities() {
  const identities = [];
  for (const fixture of fixtureBytes.keys()) {
    for (const [implementation, lane] of implementationLanes) {
      if (isSupported(implementation, fixture)) {
        identities.push({ fixture, implementation, lane });
      }
    }
  }
  return identities;
}

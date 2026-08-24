// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

export const parserMatrix = [
  ["small_mixed", 37, 1, 7, 3, [[20, 21], [33, 70], [22, 25], [20, 21], [20, 21]]],
  [
    "large_mixed",
    564_139,
    3,
    18,
    4,
    [[262_148, 262_149], [523_182, 1_087_321], [278_295, 313_554],
      [263_156, 265_360], [262_213, 262_351]],
  ],
  [
    "string_heavy",
    1_081_355,
    1,
    4,
    1,
    [[16_394, 16_395], [1_081_356, 2_162_711], [86_026, 153_611],
      [20_746, 24_971], [16_666, 16_931]],
  ],
  [
    "number_heavy",
    286_721,
    1,
    0,
    0,
    [[147_460, 147_461], [335_876, 622_597], [159_236, 177_157],
      [148_196, 149_317], [147_506, 147_577]],
  ],
  [
    "long_mantissa_numbers",
    884_737,
    1,
    0,
    0,
    [[98_308, 98_309], [917_508, 1_802_245], [149_508, 204_805],
      [101_508, 104_965], [98_508, 98_725]],
  ],
  [
    "deep_nesting",
    513,
    256,
    0,
    0,
    [[517, 518], [517, 1_030], [517, 550], [517, 520], [517, 518]],
  ],
  [
    "large_array",
    294_913,
    1,
    0,
    0,
    [[98_308, 98_309], [98_308, 393_221], [98_308, 116_741],
      [98_308, 99_461], [98_308, 98_381]],
  ],
  [
    "large_object",
    283_803,
    1,
    136_346,
    16_384,
    [[65_540, 65_541], [185_502, 469_305], [72_700, 90_438],
      [65_985, 67_094], [65_567, 65_637]],
  ],
];

export const parserChunks = ["monolith", "1", "16", "256", "4096"];

export function parserIdentities() {
  const identities = [];
  for (const [fixture, bytes, depth, nameOctets, names, observations]
    of parserMatrix) {
    for (let index = 0; index < parserChunks.length; index += 1) {
      const [events, calls] = observations[index];
      identities.push(
        `parser_validation/${fixture}/chunk=${parserChunks[index]}`
        + `/bytes=${bytes}/depth=${depth}/events=${events}/calls=${calls}`
        + `/name_octets=${nameOctets}/names=${names}`,
      );
    }
  }
  return identities;
}

export function parseParserIdentity(name) {
  const storageMarker = "/parser_bytes=";
  const tailMarker = "/name_octets=";
  const storageStart = name.indexOf(storageMarker);
  const tailStart = name.indexOf(tailMarker, storageStart + storageMarker.length);
  if (storageStart < 1 || tailStart < 0) {
    throw new Error("parser identity lacks a parser_bytes field");
  }

  const storageText = name.slice(storageStart + storageMarker.length, tailStart);
  if (!/^[0-9]+$/.test(storageText)) {
    throw new Error("parser_bytes is not an unsigned decimal integer");
  }
  const parserBytes = Number(storageText);
  if (!Number.isSafeInteger(parserBytes) || parserBytes < 1) {
    throw new Error("parser_bytes is not a positive safe integer");
  }

  return {
    identity: name.slice(0, storageStart) + name.slice(tailStart),
    parserBytes,
  };
}

export function withParserStorage(identity, parserBytes) {
  const marker = "/name_octets=";
  const markerStart = identity.indexOf(marker);
  if (markerStart < 1) {
    throw new Error("parser semantic identity lacks a name_octets field");
  }
  return `${identity.slice(0, markerStart)}/parser_bytes=${parserBytes}${identity.slice(markerStart)}`;
}

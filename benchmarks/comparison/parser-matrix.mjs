// Copyright (c) 2026 Yurii Rashkovskii
// SPDX-License-Identifier: MIT OR Apache-2.0

export const parserMatrix = [
  ["small_mixed", 37, 1, 7, 3, [[20, 1], [33, 37], [22, 3], [20, 1], [20, 1]]],
  [
    "large_mixed",
    564_139,
    3,
    18,
    4,
    [[262_148, 1_025], [523_182, 564_139], [278_295, 35_259],
      [263_156, 2_204], [262_213, 1_102]],
  ],
  [
    "string_heavy",
    1_081_355,
    1,
    4,
    1,
    [[16_394, 65], [1_081_356, 1_081_355], [86_026, 67_585],
      [20_746, 4_225], [16_666, 265]],
  ],
  [
    "number_heavy",
    286_721,
    1,
    0,
    0,
    [[147_460, 577], [335_876, 286_721], [159_236, 17_921],
      [148_196, 1_121], [147_506, 631]],
  ],
  [
    "long_mantissa_numbers",
    884_737,
    1,
    0,
    0,
    [[98_308, 385], [917_508, 884_737], [149_508, 55_297],
      [101_508, 3_457], [98_508, 433]],
  ],
  [
    "deep_nesting",
    513,
    256,
    0,
    0,
    [[517, 3], [517, 513], [517, 33], [517, 5], [517, 3]],
  ],
  [
    "large_array",
    294_913,
    1,
    0,
    0,
    [[98_308, 385], [98_308, 294_913], [98_308, 18_433],
      [98_308, 1_153], [98_308, 433]],
  ],
  [
    "large_object",
    283_803,
    1,
    136_346,
    16_384,
    [[65_540, 257], [185_502, 283_803], [72_700, 17_738],
      [65_985, 1_109], [65_567, 281]],
  ],
];

export const parserChunks = ["monolith", "1", "16", "256", "4096"];
export const parserDrainEventCapacity = 256;
export const parserCallerEventBytes = 6_144;

export function parserIdentities() {
  const identities = [];
  for (const [fixture, bytes, depth, nameOctets, names, observations]
    of parserMatrix) {
    for (let index = 0; index < parserChunks.length; index += 1) {
      const [events, calls] = observations[index];
      identities.push(
        `parser_validation/api=public_drain/${fixture}/duplicates=reject`
        + `/chunk=${parserChunks[index]}`
        + `/bytes=${bytes}/depth=${depth}/events=${events}/calls=${calls}`
        + `/drain_event_capacity=${parserDrainEventCapacity}`
        + `/caller_event_bytes=${parserCallerEventBytes}`
        + `/name_octets=${nameOctets}/names=${names}`,
      );
    }
  }
  const largeObject = parserMatrix.find(([fixture]) => fixture === "large_object");
  const [fixture, bytes, depth, , , observations] = largeObject;
  for (let index = 0; index < parserChunks.length; index += 1) {
    const [events, calls] = observations[index];
    identities.push(
      `parser_validation/api=public_drain/${fixture}/duplicates=preserve`
      + `/chunk=${parserChunks[index]}`
      + `/bytes=${bytes}/depth=${depth}/events=${events}/calls=${calls}`
      + `/drain_event_capacity=${parserDrainEventCapacity}`
      + `/caller_event_bytes=${parserCallerEventBytes}`
      + "/name_octets=0/names=0",
    );
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

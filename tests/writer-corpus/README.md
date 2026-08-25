# Ordinary compact writer corpus

This maintained lane drives `Flyology_JSON.Writing` through project-owned Ada
event tapes and compares every emission byte-for-byte with the corresponding
hex oracle under `golden/`. Hex makes the absence of a BOM, whitespace, and a
final line feed explicit while keeping the repository files friendly to text
tooling.

The tapes cover nested objects and arrays, empty and nonempty strings, every
short escape, a required `\u0000` escape, quote and reverse-solidus escapes,
an unescaped solidus, two-, three-, and four-octet UTF-8 scalars, exact integer
and exponent spellings, Boolean/null values, deep nesting, OCI-style annotation
names, and deliberately unknown fields. For each text/name/number token the Ada
runner exercises a whole fragment, one-octet fragments, every possible single
split (including empty prefix and suffix), and four deterministic randomized
fragment schedules. It reparses each emitted document with the public strict
parser, then separately exercises every single parser chunk split, one-octet
parser chunks, and deterministic randomized parser chunks.

`verify-independent.mjs` decodes the same golden octets as fatal UTF-8 and asks
Node's independent built-in JSON parser to accept them. The existing yyjson,
RapidJSON, and Rust comparison adapters currently expose benchmark validation
lanes rather than a reusable correctness-oracle command, so this lane does not
claim differential writer equivalence with them yet. Their integration remains
an explicit release gap, not an inferred result from Node agreement.

All tapes and golden bytes are original project material under the repository's
MIT OR Apache-2.0 license; no external corpus is vendored here.

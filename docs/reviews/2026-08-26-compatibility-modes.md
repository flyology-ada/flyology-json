# Explicit comment and trailing-comma compatibility review

Date: 2026-08-26

Reviewed base commit: `5e4307a34f585baf7029bde916cbf2779876d78d`

This review covers the `0.1.0-dev` parser extension families authorized by the
user. It does not add a release tag, canonical output policy, comment event,
DOM, or another nonstandard JSON spelling.

## Decision

`Compatibility_Family` has four independently selected families:

- `No_Extensions` accepts only the existing RFC JSON grammar;
- `Comments` additionally accepts `//` line comments and non-nested `/* */`
  block comments where JSON whitespace is legal;
- `Trailing_Commas` additionally accepts one trailing comma after the final
  item or member of a nonempty container; and
- `Comments_And_Trailing_Commas` admits both named extensions.

Comments are validated UTF-8 trivia. They produce no parser events, because
the public event grammar describes JSON values rather than source trivia.
Every comment octet still advances the absolute source coordinate. A future
lossless-source or comment-preservation surface would require a separately
reviewed opt-in policy and event grammar.

These are new family identities at compatibility version 1, not new behavior
under `No_Extensions`. Parser initialization validates and freezes the exact
family before byte zero. The Alire crate remains `0.1.0-dev`, as explicitly
authorized; a reviewed successor index origin can replace the current
development snapshot without a Git tag.

## Implementation

The parser holds a five-state resumable trivia machine for a possible comment
opener, line body, block body, and possible block terminator. Text tokens and
comments are mutually exclusive and share the parser's existing incremental
UTF-8 decoder. This preserves the strict parser object's 296-byte size.

The strict hot path caches the resolved comment policy for a complete engine
call and retains a separate whitespace loop. Token completion treats `/` as a
delimiter only when comments are selected. Trailing-comma acceptance is
limited to the post-comma array and object phases; first-element/member phases
remain unchanged.

Reviewed implementation identities:

| Artifact | SHA-256 |
| --- | --- |
| `src/flyology_json-profiles.ads` | `4ca3e2d58fb450b09a3bf825c29bd313b499ec3995fc7b034ef84f3c1362ead1` |
| `src/flyology_json-parsing.adb` | `795489c8c1c4e7f27c7f4342b623441b6559fb85e4b5d451d0da83c447a3bdf2` |
| `src/flyology_json-parser_core.ads` | `737b88a6b410c73e2b41391fd0e7eb4dffa06ed9a3daa8407225a402b2a6bf35` |
| `src/flyology_json-parser_core.adb` | `299af47d62bf4f9a9ead3cd6b0141a3f1cda019f828d7bfbb3d6c1640b029fab` |
| `tests/flyology_json-parser_core_tests.adb` | `11884a3a4a7cc6ffd0f5ebf970822dba2191b8a594e06007f4df24f112ccfa27` |
| `tests/flyology_json-parser_core-offset_tests.adb` | `b312a8d0e1984747621692e03dea79dd9be8b62843cd3867caea21cf10847ee5` |
| `tests/flyology_json-public_foundation_tests.adb` | `c24ea1f1977ecff80926ad8d374f23d717bc05ad683e4b4049aaa12c96303c0a` |
| `tests/flyology_json-public_parsing_tests.adb` | `f12c630ba985e37a3d668879bd7ef3e3e29981465bbe77400b987edd1b70af93` |

## Verification

GNAT 16.2.0 and GPRbuild 26.0.0 on arm64 macOS 26.5.2 passed:

- the complete maintained parser, writer, public-consumer, exact-offset, and
  transactional test suite;
- exhaustive two-chunk splits and every partition for bounded compatibility
  fixtures, plus one-byte and deterministic randomized schedules;
- CR, LF, CRLF, and final-input line endings; non-nested block termination;
  markers inside strings; direct token/comment boundaries; malformed openers;
  truncation; malformed UTF-8; exact offset exhaustion; compatibility-family
  isolation; lifecycle abort/reset; and strict leading/doubled comma rejection;
- 394 pinned corpus fixtures under monolithic, one-byte, and randomized
  schedules with zero unexpected results: JSONTestSuite 314 and JSON Schema
  Test Suite 80, with three pinned WPT files retained as provenance evidence;
- four writer golden documents replayed through the public parser and accepted
  by the independent Node `JSON.parse` oracle;
- public strict/preserve parser and public writer assembly gates;
- the generated site, 81 authored API links, 10 public GNATdoc units, and zero
  undocumented installed-public-unit warnings; and
- APM 0.28.0 frozen installation and audit with all 10 checks passing. The
  organization policy endpoint was unavailable, so APM reported and skipped
  remote policy enforcement; the cache-only lock replay and drift audit passed.

The extension fixtures are executable contract cases, not majority-oracle
specification. The pinned strict corpora remain strict-profile evidence and
verify that `No_Extensions` did not silently become permissive.

## Strict-path performance gate

The benchmark compared the candidate with a release build from the reviewed
base commit. Runs alternated sequentially after functional work stopped. The
workload was public `Drain`, `large_array`, monolithic input, duplicate
rejection, 294,913 bytes, 98,308 events, 385 drain calls, and a 256-event
caller buffer.

| Build | Four run medians | Median of run medians |
| --- | --- | ---: |
| Base | 378.901, 380.823, 379.610, 378.520 us | 379.256 us |
| Candidate | 376.343, 374.902, 372.344, 378.050 us | 375.623 us |

The candidate result is 0.958% lower latency in this pair, about 0.785 decimal
GB/s or 748.8 MiB/s. This is a no-regression result, not an optimization claim.
Both builds report a 296-byte parser object.

## P0/P1/P2 findings

Rubric: P0 is an unsafe or irreversible blocker; P1 is a correctness,
boundedness, lifetime, interoperability, or public-contract blocker; P2 is an
important pre-milestone quality, documentation, or performance defect.

- P0: none.
- P1: none after fixes. An early implementation consumed the newline of a
  split line comment in the ordinary whitespace loop; the comment-enabled loop
  now consumes whitespace only while no comment is active. Every split and
  one-byte tests reproduce the repaired boundary.
- P2: fixed. A separate comment UTF-8 decoder enlarged every parser object from
  296 to 336 bytes and initially measured about 3.1% slower. Sharing the
  mutually exclusive decoder restored 296 bytes and the strict benchmark gate.
- P2: fixed. Focused coverage originally omitted CR/CRLF line endings and
  explicit first-terminator/string-marker cases. The bounded exhaustive
  fixtures now cover them.
- P2: fixed. New private declarations increased GNATdoc's warning baseline.
  They are now documented; the warning count remains 379 and installed public
  units remain at zero warnings. The attestation digest changed only because
  source line coordinates moved.

The final self-review sweep found no remaining actionable P0, P1, or P2 in
this compatibility milestone. Consumer review of the exact pushed declaration
commit remains required before the indexed development origin is replaced.

### Post-push generated-instruction repair

The first Agent Resources run on pushed head `dc05a7e` found a P1 in the local
APM reproduction evidence. APM scans ignored build trees; the local SIMD spike
cache retained an unrelated Flyology checkout whose allocator instruction
packages were consequently placed in the root generated `AGENTS.md`. A clean
CI checkout did not contain those ignored artifacts and generated the correct
eight-pattern instruction set, so the committed aggregate did not reproduce.

The ignored, reproducible benchmark cache was moved out of the checkout and a
single serialized `apm compile --target codex` regenerated the same build ID
and instruction set as clean CI. No APM source package or lock changed. The
repair removes only the unrelated generated scopes; parser source and the
reviewed compatibility declarations are unchanged.

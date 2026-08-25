# SIMD parser spike

Date: 2026-08-24

This review records scratch-only SIMD experiments based on exact scalar
milestone `9ddf00774dbe99e0d3eeefd71753ecac668ebbad`. No SIMD dependency,
parser change, source pin, public threshold, or build default is adopted by
this review.

## Correctness boundary

All viable candidates preserve the existing parser event grammar, exact
offsets, arbitrary `Stream_Element_Array` bounds, chunk behavior, and scalar
fallback. Each viable candidate passed the six maintained parser executables.
Baseline and the viable fused candidates produced identical:

- focused seam transcript SHA-256
  `dfbe0b13a5f0d2de3da23f7cf43d90457d6f88bd57c8b1a07a94226bc01aaeee`;
- 380-case split, chunk, and near-`Stream_Element_Offset'Last` transcript
  SHA-256
  `d90cd5aa5c0596cc05fee9e53b1c5ca3479d07a40a839b93c086c841fc00f51d`;
- maintained comparison preflight SHA-256
  `021d314f15d6e9a0fe76009d259a00616d6eaac69be5e73678498f90513a60d4`;
- chunked-long preflight SHA-256
  `50550c91100e274a658c6a5f5503e55627c7a0d5872b9ba5519fcefc0fcd7229`.

The environment was the same portable GNAT 16.1 macOS AArch64 environment as
the compact-event review. Measurements are directional local evidence, not a
cross-platform claim.

## Rejected indexed search seam

The first candidate called indexed `flyology_simd=0.1.1-dev`
`Stream_Element_Arrays.Native.Find_First_Of` for quote and backslash, then ran
a second exact ASCII validation scan. On the maintained 1,081,355-byte
`string_heavy` fixture, two clean rounds measured:

| Variant | Median range, ms | Result versus baseline |
| --- | ---: | ---: |
| scalar baseline | 1.456--1.461 | baseline |
| indexed native double scan | 1.603--1.635 | 10--12% slower |
| indexed forced-scalar double scan | 1.929--1.952 | 32--34% slower |

The indexed `0.1.1-dev` path also raised `Constraint_Error` in
`flyology_simd-algorithms-generic_indexed_bytes.adb:19` for an arbitrary-high
SEA bound once its native long path became reachable. This is a P1 upstream
finding. Flyology_JSON does not hide it with copying, rebasing, an unsafe
overlay, or a local pin. Flyology_SIMD fixed, reviewed, and published the issue
as distinct indexed successor `0.1.2-dev`: source origin
`32cdb477080e6bb822df91918971e5981fd92d6b`, PR 18, and Flyology Alire index
commit `61a792c64fc4d5b8cfa4b588f7fd7d2db7099cda`. Clean index resolution, local
AArch64 GNAT 13--16 focused tests, GNAT 16 macOS/Linux CI, Linux sanitizer
coverage, arbitrary-high-bound cases, and AArch64 code-generation evidence
pass. Flyology_JSON does not add the successor as an unused dependency because
the available two-scan operation remains a parser regression and the useful
fused operation is not yet public.

A later source milestone, Flyology_SIMD PR 19 at origin commit
`172aa9087ac76e6eb4e18ae9a595a55f6eb34b66`, adds a SPARK foundation without
changing the indexed release cited above. GNATprove FSF 16.1 discharges all
eight checks with no justified or unproved checks and no `pragma Assume`. The
proof boundary covers SEA-specialized exact index arithmetic and termination,
and flow analysis covers the production scalar SEA search. Native raw loads
and backend leaves, plus the widest-index fallback, remain explicitly outside
this first proof boundary.

## Fused classifier experiments

A scratch fused classifier stops at quote, backslash, a control octet below
`16#20#`, or a non-ASCII octet. GNAT inlines and auto-vectorizes one loop into
one 16-byte load, two equality comparisons, one range comparison, mask ORs,
and reductions. There is no helper call. Explicit backend-mask primitives were
rejected because they compacted each predicate separately and generated more
work.

Unconditional fused scanning was about 5% slower on maintained
`string_heavy`, but showed that long direct spans have substantial SIMD
headroom. A 32-byte real-work scalar prefix followed by the fused tail measured:

| Direct span | Scalar median ns | Hybrid median ns | Speedup |
| ---: | ---: | ---: | ---: |
| 256 | 340.759 | 125.468 | 2.7x |
| 512 | 623.625 | 144.616 | 4.3x |
| 1,024 | 1,179.141 | 142.550 | 8.3x |
| 4,096 | 4,504.303 | 263.933 | 17.1x |
| 16,384 | 17,770.691 | 731.691 | 24.3x |

Prefix candidates of 32, 64, and 128 bytes all remained slower on the
maintained 124-byte direct-string distribution. A pre-count threshold was much
worse because it scanned short strings twice. These candidates are rejected as
unconditional parser paths.

Flyology_SIMD separately assessed a future generic
`Find_First_Of_Or_Outside_Range` mechanism with `Data`, two needles, and an
inclusive lower/upper range constrained by `Lower <= Upper`. Native and scalar
SEA twins would return the existing definite `Search_Result`, with the generic
indexed-byte layer owning the mechanism and no JSON policy. A direct scalar
loop is appropriate; a native vector implementation still requires evidence
for the intended one-load, two-equality, range, OR, and reduction code shape.
The API is not implemented or indexed, and the maintained 124-byte regression
cannot establish its performance. Availability alone would not justify
Flyology_JSON integration; an implementation would still have to eliminate
the maintained 124-byte regression.

## Continuation-only result

The final scratch candidate enters the fused loop only for non-final input
when the parser's existing state proves that more than 128 source octets of the
same text token have already been consumed and at least 16 current octets
remain. It adds no parser field or retained chunk identity. Short monolithic
strings keep the baseline byte loop.

Comparison binary SHA-256 values:

- baseline:
  `4fb2ed46bed48c1f6c1546eb1d9525ea19ad21c0fe2d803315df451079a1b23e`;
- continuation candidate:
  `e4c1dd7ba855979bacfa2f6a6f8bec6452ee51ae02d7dd5d7fc7390aaa7a0de7`.

Three counterbalanced `string_heavy` pairs found a small 0.5--1.9% candidate
latency regression. The path is therefore not suitable as an unconditional
default. On 256-byte chunked direct strings, clean paired populations measured:

| Direct span | Scalar median ns | Continuation median ns | Approx. speedup |
| ---: | ---: | ---: | ---: |
| 256 | 347--358 | 348--352 | neutral |
| 512 | 650--655 | 379--384 | 1.7x |
| 1,024 | 1,239--1,262 | 442--455 | 2.7--2.9x |
| 4,096 | 4,796--4,889 | 771--776 | 6.2--6.3x |
| 16,384 | 19,520--19,634 | 2,091--2,102 | 9.3x |

An earlier first-order population contained large preemption outliers and is
not used for the clean 4 KiB and 16 KiB ranges above.

## Disposition and next architecture

SIMD is not dismissed: long direct and chunked-continuation strings have large
headroom. No current candidate is adopted because ordinary maintained work
regresses, the assessed fused public SEA API is not implemented or indexed,
and only GNAT 16/macOS/AArch64 parser-integration evidence exists. The indexed
`0.1.2-dev` repair closes the generic SEA high-bound defect but does not change
the two-scan structure that measured slower.

A future caller-storage structural sidecar is technically plausible. It would
classify each exact current chunk into quote, backslash, structural,
whitespace, control, and non-ASCII masks with string/backslash carry. Masks
must remain advisory to the one existing grammar engine; UTF-8 and semantic
error ordering remain in that engine. The sidecar needs a separately reviewed
capacity, lifetime, fallback, and continuation contract before implementation.

Final scratch review: P0 none. The indexed arbitrary-bound P1 is fixed upstream
in `0.1.2-dev`. Remaining P1 integration blockers are the missing fused public
API, maintained-work regression, and lack of complete integration evidence for
any retained candidate. P2 findings are the experimental private 128-byte
tuning value and incomplete GNAT 13--15, Linux, and x86-64 parser-integration
evidence.

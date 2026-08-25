# Public API repair review

## Scope

Wire, Serde, and Type IR independently reviewed pushed commit
`d36c23dc1b63ba7fe8d739246f1a1697c07b61e7`. The repaired slate below is an
uncommitted successor and remains a review artifact until its exact committed
hash is sent back to those consumers. No integration or dependency is
authorized by this review.

Flyology_OCI subsequently supplied OCI Runtime Spec consumer requirements. Its
boundary adds release gates for exact checked uint32, uint64, and int64
conversion and an installed-public-units downstream spike. OCI retains typed
field handling and unknown-field or annotation policy; Flyology_JSON exposes
every member and does not require a DOM.

## Repaired findings

The review cycle found no P0. All P1 findings were repaired:

- discriminated parser and numeric out results became definite records with
  status-controlled field eligibility and valid unspecified failure payloads;
- raw resolution now honestly validates coordinate containment and requires the
  caller to supply the exact unchanged producing input, without claiming object
  identity or stale-event authentication;
- null and Boolean raw availability is conditional when a literal crosses an
  input window;
- parser lifecycle is total, including final-input retraction and an explicit
  `Failure_Pending` state;
- depth, name-octet, name-index, duplicate-work, denial timing, consumption,
  and blame coordinates have exact units and boundary rules;
- inline scalar and token storage use `Stream_Element_Array` subtypes, token
  overlap is forbidden, and failed collector storage remains unpublished;
- Binary64 uses an always-valid numeric bit encoding with bit 63 sign, bits
  62 through 52 biased exponent, and bits 51 through 0 fraction;
- the private writer closes destination/status precedence and every admitted
  mutating call is abort-deferred, with exactly-once unpublished cleanup;
- name-storage diagnostics now blame the member opening quote in every path.

All P2 findings were also repaired. Parser and collector asynchronous-transfer
limits are explicit; decimal/application packages are marked future; accessor
inlining is declared and checked; public coordinate authority is recorded; and
the architecture records writer cancellation latency.

## Exact repaired review slate

| Artifact | SHA-256 |
|---|---|
| `contracts.md` | `56411690f77e2a178f7ff36ac36ed7bf856fc29c0c5346ba5b84984fffda5fda` |
| `architecture.md` | `a14369839b172e10ec6c59eec4b8a6b6e5d7ed81b2626f955f8c86ef5415b14a` |
| `flyology_json-destinations.ads` | `45cdeca9a9c1a9c5374af3bb2f2b67284f984288a6df156e0f320bc2a5f0c7b8` |
| `flyology_json-errors.ads` | `c4c59c7c72e1f02b93087e45d1a9d7d423067334b2db034096c43c003fe322b8` |
| `flyology_json-numbers.ads` | `eff2743bf10ff14b46f54c69711e1e582e51b9fb9b446131849d77aac11826ef` |
| `flyology_json-numbers-binary64.ads` | `58c8dbd1a980d207dfa4b3ecf31c28b96a43764daffb92f08517956f67c2d885` |
| `flyology_json-numbers-signed_integers.ads` | `5bf1815ac3f7adce2f06250d9c75adc5f064c3ab621ccb159c44848fabf50ffc` |
| `flyology_json-numbers-unsigned_integers.ads` | `ff9f5bfa339862625a29781afcca43f76f30d1a3c81c17fc87b1b7a348a5a209` |
| `flyology_json-parsing.ads` | `cb3be9a8874b92e1e9aa070cbfd051212c94e145ecefb3fc9fdedee4c88fa4ae` |
| `flyology_json-profiles.ads` | `e2507a3a17b0df1e27d6274a4e73f2cb2d6d401b2d92c9a906562a0217d6e57d` |
| `flyology_json-tokens.ads` | `c8cbf25e1ac3a2cbafe9a592bcc23ee414e5f1469fa31dd724516739f9ac83a6` |
| `flyology_json-writing.ads` | `f29b9cc9c0143148a9b769f3d85d49bf3693e60fe131de4291421e4ab70c5c75` |

The final independent static sweep found P0 none, P1 none, and P2 none.

## Implementation evidence

The compact parser descriptor remains 24 octets. Exhaustive parity covers all
maintained transition fixtures, every split, randomized schedules, arbitrary
bounds, small output capacities, and resource failures. The maintained parser
suite and 394-fixture corpus campaign pass. Its accessor probe contains no
indirect branch or accessor call, and the parser hot loop has an identical
normalized assembly hash. A quiet paired portable `large_array` run measured
1.135 GB/s before and 1.199 GB/s after.

The writer strict suite passes five consecutive runs with validity, overflow,
assertion, warning, and exception-trace checks. Abnormal-transfer tests cover
begin, structural, name, string, number, scalar, and 4 KiB bulk operations with
exactly-once abort and no publication. The abort-safe guard does not enter the
per-octet scanner loop. Under a noisy host load, 1 MiB throughput changed from
0.1305 GB/s unguarded to 0.1289 GB/s guarded, while a one-byte call changed from
9.4 ns to 645.5 ns.

That fixed writer-call cost is material. The abort-safe slate is correct but is
not yet approved as the only public writer shape. A fast owner-cleanup shape and
an explicitly abort-safe shape require architecture and consumer re-review
before the public writer is frozen.

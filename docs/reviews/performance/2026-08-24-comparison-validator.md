# Comparison contract validator revision review

Date: 2026-08-24

Base contract commit: `becb971008982c36abcad1a262887defa1eb333e`

## Problem

The initial comparison contract defined Draft 2020-12 schemas but had no
maintained strict validator. Independent review demonstrated that ordinary
JavaScript parsing can silently replace malformed UTF-8, discard a BOM,
collapse duplicate names, accept unpaired surrogate escapes, and round a
fraction into an integer before schema validation. Strict Ajv compilation also
found missing object types in conditional schemas and an unsupported union.

## Resolution

The reviewed validator uses exact Node 24.19.0 and npm 11.17.0 with Ajv 8.20.0
and ajv-formats 3.0.1 from the committed npm lock. It rejects malformed UTF-8,
a BOM, non-JSON grammar, duplicate decoded object names, and unpaired
surrogates before Ajv. It rejects fractional lexemes that become JavaScript
integers through rounding.

JSON Schema integers have no IEEE-754 magnitude ceiling. A mathematically
integral lexeme beyond JavaScript's finite range is therefore represented to
Ajv by a finite integer of the same sign. The validator first audits the
schema: maximum, exclusive maximum, multiple-of, numeric const/enum, and an
inexact lower bound are rejected for separate lossless-validator review. The
current schemas use only integer/number classification and exact lower bounds
of zero or one, so the proxy preserves every numeric verdict without inventing
a record limit.

Capability validation additionally requires every lane enumerated by the
schema exactly once, unique profile/output identifiers, resolved bindings,
complete API/profile/observation declarations for supported lanes, output
policies for writer-producing lanes, and no admitted bindings on unsupported
lanes. Each source identity and revision must match `sources.lock.tsv`, and
implementation identifiers must be unique across the complete validation
set. Generated build, dependency, and acquired-source directories are not
searched for authority.

The npm tooling graph contains six packages. Every exact version, integrity,
license choice, evidence path, and evidence SHA-256 is locked; the online audit
reported zero known vulnerabilities. The validator and toolchain locks are now
explicit result/skip contract digests, so this revision cannot be pooled with
the initial contract.

## Reviewed identities

| File | SHA-256 |
| --- | --- |
| `benchmarks/comparison/README.md` | `c5832d2c87aaabc86fd850438f397d919d13c8e4aeeb6ffa10e6d7c0ce0425ab` |
| `capability.schema.json` | `de7f8e5cad82fa955133cd3e70f189f695a17561f3ff113c2168f5f10da7c200` |
| `result.schema.json` | `b5e1e0d1f2557f52d3ecbb36af9dc97eaca02e394e82ea677451ba28f0799779` |
| `skip.schema.json` | `aa256ce78a395214e86073fba203909f996030ce4e2b907ac9b0553c78cb8785` |
| `ci-protocol.md` | `3eaddcfcad448ebf0e439f44db8cba15385a4146b0b271b91aa9154c7043ad97` |
| `validate-records.mjs` | `acf0515903b2618d737b8835843e4846184a93c0b063ce375a4a5dd7c0c7563d` |
| `validator.test.mjs` | `7f593dd1bb31ee3dc54286515d0980b4a17af057c76582231df2ef15f0650b72` |
| `strict-json.mjs` | `0103b5d5f3195167906b16085bac7f0fbd9f0123fa7d5f6664bf7d20e5ad870d` |
| `strict-json.test.mjs` | `e9698b3797e293468c388dd02943a9ac64259b1e75a785944e4b59ad0b89af18` |
| `node-toolchain.mjs` | `a4cfb206af9fc9d4378e9f36d3fabfb468bea0dde0843aec9cb85e5b458ee196` |
| `package.json` | `8cd5fd809fbfbd1c91d3ff16c32c9f82d56ed3351a6898e89ccd819094077711` |
| `package-lock.json` | `bd3abd6059de8d7607a8b70cbab1335c944a7fc013c2f0e332d1e4dcadedaf4b` |
| `tooling-licenses.lock.tsv` | `57b4c3bf8c2e875fa549a9ef73f0da6b7b1033e152d87eef3db646b3f179ebb9` |
| `verify-tooling.sh` | `4b0b3d8563bce71af101f67ef5dfa0417b384422366a462ae1f9077f434c7417` |

## Evidence

Under exact Node 24.19.0 and npm 11.17.0:

- 16 strict/negative validator tests passed;
- all three schemas compiled in Ajv strict Draft 2020-12 mode;
- every checked-in capability passed structural and semantic validation;
- npm lock, package inventory, license evidence, and digests matched; and
- `npm audit --omit=optional` reported zero vulnerabilities.

The exact Node release identity and bundled npm version were checked against
the official Node distribution index dated 2026-08-03.

## Findings disposition

P0: none.

P1: none after the fixes above.

P2: none. The validator's numeric-schema exclusions are deliberate fail-closed
review gates, not accepted feature limitations or record limits.

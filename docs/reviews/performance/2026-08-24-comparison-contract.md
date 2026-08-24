# External comparison contract review

Date: 2026-08-24

This review covers only the benchmark comparison contract, source and license
attestations, schemas, CI protocol, and acquisition verifier. It does not
review an adapter implementation or claim a performance result.

## Reviewed identities

- Comparison contract SHA-256:
  `d266f6593cce38bdd3583d7efd287552f6817174135cc1b95c965aac671d38d7`
- Parent benchmark policy SHA-256:
  `800958136f3ab4f8c10d499f2290b9cfa28cc1d1b870757a012025c09544d262`
- Capability schema SHA-256:
  `de7f8e5cad82fa955133cd3e70f189f695a17561f3ff113c2168f5f10da7c200`
- Result schema SHA-256:
  `dc547209e05cd6b090613fcb15013594e817a82bd9c1e1b2fdba731934ebc307`
- Skip schema SHA-256:
  `903e079413ad4824a89f0ab34c942f276540c0bc540fc32513e92779cdffdd06`
- Source lock SHA-256:
  `531d59f62fa80f5f291b874cc501d91341753bc43c6c493fbf6d5823c9ebf161`
- License lock SHA-256:
  `d67cb23815f42db61b14ed0cc33a47af7055d1c819875073e676bb5252120b5f`
- CI protocol SHA-256:
  `1eb8cbbf3a03613d275a7df5277e9c18eff8735c411c0d4ac0ea95617dd13023`
- Acquisition verifier SHA-256:
  `3a319e1d3d7cb0c23242fa08e2d5670cc233d94e71274c468b5a1a777cfec0eb`

## Evidence

The verifier downloaded all eight approved archives from their locked HTTPS
origins into an external temporary cache. It checked every exact byte length
and SHA-256, parsed each tar/crate/zip container, and independently hashed all
twelve locked license-evidence files. A second offline run passed against the
cache. The RapidJSON archive was confirmed to contain the reviewed
`bin/jsonchecker/` exclusion, and the verifier extracted no source.

All three JSON schemas parse as JSON with `jq`; the source and license manifests
have their exact field counts; the acquisition script passes `sh -n`; and
`git diff --check` is clean for the worktree.

The review checked independent parser/writer work, true incremental admission,
portable/native separation, copy/mutation/padding/allocation disclosure,
profile and output-policy identity, source provenance, ABI-boundary scope,
isolated-host evidence, ordinary versus controlled CI, capability skips,
weekly scorecard retention, and distribution-based regression review.

## Findings and disposition

Severity means: P0 invalidates safety or results; P1 blocks adopting or
publishing the contract; P2 is a material ambiguity or maintainability issue.

- P1 fixed: the RapidJSON archive was initially described only by the eligible
  implementation license. The lock now distinguishes the full mixed archive
  from the admitted MIT/BSD subset and makes `bin/jsonchecker/` exclusion
  normative.
- P1 fixed: writer results did not initially bind an explicit output policy.
  Capability records now declare output policies and lane bindings, while the
  result schema requires one for every writer-producing lane.
- P2 fixed: checksum work could have been hidden and unequal. Results now state
  the exact checksum method and timed quantity, and unlike observability work
  is a disclosed comparison limitation.
- P1 fixed: the CI and parent sampling policies were normative but absent from
  the result identity. Results now bind both policy files separately, avoiding
  ambiguous `readme` provenance.
- P2 fixed: CI skips were prose-only. The checked-in skip schema now restricts
  skips to capability-declared unsupported platforms, toolchains, or lanes and
  requires the matching scope value.

Final contract findings: P0 0, P1 0, P2 0.

Rust benchmark results remain inadmissible until the separately owned committed
`Cargo.lock` and every transitive dependency license pass review. Adapter and
CI implementation reviews must likewise close independently before producing
a scorecard; these are downstream admission gates, not deferred defects in
this contract.

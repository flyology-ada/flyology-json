# Flyology JSON

`flyology_json` is an Ada-first incremental JSON parser and streaming writer.
The bounded core uses caller-provided storage, performs no heap allocation, and
reports malformed input and resource failure without raising exceptions.

Version `0.1.0-dev` is the reviewed source candidate selected for publication
through the Flyology Alire index. Add the Flyology index ahead of the community
index once; the release resolves without a Git or path pin after its exact
development manifest is published:

```sh
alr index --reset-community
alr index --add=git+https://github.com/flyology-ada/alire-index.git \
  --name=flyology --before=community
alr with flyology_json=0.1.0-dev
```

## Public surface

- `Flyology_JSON.Parsing`: caller-driven `Step` and batched `Drain`, explicit
  profiles and capacities, provisional events, exact raw number/source ranges,
  strict decoded-name duplicate rejection or unchecked preservation.
- `Flyology_JSON.Tokens`: bounded caller-storage token collection.
- `Flyology_JSON.Numbers.Signed_Integers` and `.Unsigned_Integers`: checked
  exact-lexeme conversion without normalization or hidden allocation.
- `Flyology_JSON.Writing`: allocation-free semantic streaming calls over a
  caller destination whose `Begin`/`Write`/`Commit`/`Abort` transaction publishes
  only a complete document.

`Ordinary_Compact` preserves caller member order and exact validated number
lexemes. It is deterministic for the same call sequence, but is not canonical
JSON.

## Boundaries

- Flyology JSON owns JSON syntax, UTF-8 and escape handling, exact numeric
  lexemes, duplicate member-name detection, profiles, parsing, and writing.
- Flyology Serde owns format-neutral traversal and unpublished Ada candidates.
- Flyology Type IR owns its schema, validation, semantic projection,
  fingerprints, canonical interchange authority, and production authority.
- Flyology Wire runtime does not depend on this crate.

See [the architecture](docs/architecture.md) for the reviewed contracts and
state machines.

## Agent setup

This repository uses APM 0.28.0. Install the locked agent packages and generate
client instructions from the source packages:

```sh
apm install --frozen
apm compile --target codex
apm audit --ci
```

Do not treat generated `AGENTS.md` as source authority.

## License

Original project material is available under either the MIT license or the
Apache License 2.0.

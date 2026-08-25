# Flyology JSON website architecture

Date: 2026-08-25

Status: reviewed and implemented

## Decision

Publish a static project site at `https://json.flyology.org/`. The site combines
hand-written documentation with a generated public GNATdoc reference. It uses
the same pinned `flyology-ada/website-kit` revision as the current Flyology SIMD
and RDF sites: `7428fe9f3197c5f32ba64e460ff1c711c3ae102f`.

The website does not change the crate API, support claims, release status, or
runtime dependencies. It documents the current reviewed public units and reads
release status from verified repository and index evidence.

## Authored information architecture

The committed `website/` tree contains:

- `/`: a landing page that explains incremental parsing, transactional writing,
  caller storage, exact lexemes, and the current release status;
- `/guide/`: a task-oriented guide index;
- `/guide/getting-started/`: installation status, explicit profiles, and a first
  parse;
- `/guide/parsing/`: `Step`, `Drain`, event lifetimes, chunk boundaries, final
  input, duplicate modes, and parser lifecycle;
- `/guide/writing/`: destination transactions, writer grammar, UTF-8 fragments,
  exact number lexemes, completion, abort, and reset;
- `/guide/tokens-and-numbers/`: bounded collection and checked signed or unsigned
  integer conversion;
- `/guide/profiles-and-errors/`: explicit profiles, strict behavior, diagnostics,
  coordinates, and resource failures;
- `/architecture/`: the implemented parser, writer, ownership, allocation, and
  integration boundaries established by current public specs, bodies, and
  tests;
- `/support/`: exact implementation status, tested compiler and operating-system
  evidence, exclusions, and release limitations;
- `/api/`: generated GNATdoc output; and
- `/llms.txt`: a concise machine-readable site map and boundary summary.

The primary navigation contains Overview, Guide, Architecture, Support, API,
and GitHub. Getting started, Parsing, Writing, Tokens and numbers, and Profiles
and errors are children of Guide. The site has no empty journal section.

## Generated API reference

`scripts/docs.sh` performs these operations in order:

1. locate Alire and GNATdoc without selecting a compiler provider revision;
2. build `flyology_json.gpr` through Alire;
3. render the shared GNATdoc theme from a committed JSON configuration;
4. generate public declarations with `--style=leading`, which matches the
   documentation comments before declarations in the current public specs;
5. normalize and compare every warning and omission against a committed exact
   allowlist, and reject every unexpected GNATdoc internal error even when the
   tool exits successfully;
6. normalize known GNATdoc link forms;
7. install the shared font, Ada highlighter, and Flyology mark;
8. build a checked API search index; and
9. assert the exact expected public compilation-unit set in that index.

Generated `docs/api/` and `docs/gnatdoc/` output remains ignored. The published
site receives a fresh copy during every build.

Authored API mentions use `data-api` identifiers. A build-time resolver reads
the generated search index, resolves each identifier to the exact unit or
declaration, and fails on missing or ambiguous targets. Authors do not guess
GNATdoc filenames or anchors.

## Site assembly and shared assets

`scripts/docs.sh` destructively replaces only `docs/api` and writes transient
GNATdoc theme files under `docs/gnatdoc/html`. It validates both paths before
removal or generation. `scripts/build-site.sh` destructively replaces only
`build/site`, after it validates that exact path. It regenerates GNATdoc, copies
the authored website, installs shared assets from the pinned website-kit,
resolves API links, adds content hashes to local CSS and JavaScript references,
writes `.nojekyll`, and runs the website-kit link checker.

The authored pages add one project stylesheet for JSON-specific diagrams and
layout. Shared navigation behavior, theme handling, typography, base layout,
Ada syntax highlighting, and link checks remain in website-kit.

## Publication and reproduction

A Pages workflow uses Ubuntu 24.04, Node 24.19.0, Alire 2.1.1, GNAT 16.1.0,
GPRbuild 26.0.1, and GNATdoc 26.0.0. It pins every GitHub Action by commit,
checks out submodules recursively, builds the site, checks links, and deploys
`build/site`.

The repository commits `website/CNAME` with the exact value
`json.flyology.org`. Site assembly asserts that content. DNS routing and the
GitHub Pages custom-domain setting are explicit external publication steps,
not properties of a successful local build. After deployment, the workflow
checks `https://json.flyology.org/` over HTTPS and requires the expected site
identity.

The root APM package gains one local website instruction package. Its claim
rules distinguish core allocation from destination behavior, provisional
events from document acceptance, ordinary compact output from canonical JSON,
and current evidence from future work. It also owns API-link rules and the
separate technical, editorial, and controlled-language reviews. APM generates
`website/AGENTS.md`; the generated file is committed but is never source
authority. Agent-resource CI reproduces both root and website instructions.

## Claim and example authority

Current website claims come from installed public specs, their bodies,
maintained tests, and the current README. `docs/architecture.md` supplies design
context only where those executable sources confirm it. Binary64 and decimal
conversion, accounting, canonical output, DOM support, and consumer adapters
are future work unless a public unit and maintained evidence exist when the
site builds.

Guide programs live in a maintained `examples/` project and run in the normal
site verification path. Each HTML example names a source file and marked source
region. A verifier decodes the HTML block and requires byte-for-byte equality
with that region. Application-selected capacities in examples are labelled as
example choices and never as library defaults.

## Verification

The change must provide evidence for:

- `apm install --frozen`, `apm compile --target codex`, and `apm audit --ci`;
- a successful crate build before GNATdoc;
- generated public API pages, the exact public unit set, and a nonempty search
  index;
- successful API-link resolution and website-kit link checking;
- desktop and mobile visual inspection in light and dark themes;
- keyboard navigation, visible focus, semantic headings, alternative text, and
  reduced-motion behavior;
- exact compilation or test provenance for every code example;
- a `website/llms.txt` route and boundary check against built pages; and
- independent technical, editorial, and controlled-language reviews of the
  settled multi-page draft.

The `llms.txt` verifier checks every listed local route in `build/site`. It also
checks that the stated release, current API, and future-work boundary agrees
with the rendered support page.

## Initial review slate

Severity rubric:

- P0: unsafe, irreversible, or authority-breaking publication defect;
- P1: incorrect contract, broken reproduction, inaccessible critical path, or
  misleading support/release claim;
- P2: important pre-publication usability, maintainability, or evidence gap.

No architecture finding is accepted as deferred by this proposal. All P0, P1,
and P2 findings must be fixed before the website milestone is committed.

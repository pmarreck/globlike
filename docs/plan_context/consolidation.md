# Library verification and consolidation context

## Implemented contract

The current implementation is the September 15 library contract described in
INTENT.md and README.md. It provides `*`, `?`, and `**`, bracket-framed regex
excerpts, explicit `glob:` and `regex:` modes, and typed diagnostics. It does
not implement standard glob character classes: `[abc]` means the sequence
`abc`. Strict unescaped bracket balancing remains the implemented framing rule.

The MIT license, README, parser, matcher, and target manifest already exist.
The old compound task to complete the library, publish documentation, adopt it,
and add a CLI conflated completed work with future integration. The active
plan now separates verification, language design, and adoption.

Historical verification reported 26 tests, allocation-failure sweeps, invalid
UTF-8 diagnostics, bounded DFA workspace, and hidden unsupported branches.
ReleaseFast builds and compilation for five target platforms passed on
September 15 at approximately 22:13 EDT. Linux execution uses musl; other
platforms had compilation evidence only. These are historical results, not
fresh verification claims.

## September 27 design discussion

Consolidation with the sibling `glob` command is under consideration. That
command is still Bash and delegates pathname expansion to Bash. The shared
language should preserve as much ordinary glob syntax and muscle memory as
possible, including character classes, while allowing explicit regex fragments.
The exact grammar, implementation language of a future CLI, and repository
arrangement have not been selected.

Candidate regex markers discussed were `[/.../]`, `[|...|]`, and Elixir-like
`~r` sigils with selectable paired delimiters. `%r` was proposed as a marker
without tilde expansion. The October 20 decision selected `%r` with a defined
set of paired delimiters, preserving standard glob character classes. The
accepted direction is recorded in INTENT.md; the original marker question is
resolved. Nesting, escaping, modifiers, migration, and filesystem traversal
still require a detailed specification.

The shell processes arguments before the CLI receives them. `set -f` disables
pathname expansion but does not disable brace expansion, tilde expansion,
escape processing, or shell operators. The library receives strings directly
and has no dependency on shell configuration. Quoted CLI patterns, or input
through a file, stdin, or an application-owned prompt, can support arbitrary
regex without requiring users to configure `set -f`. Quoted regex-like CLI
arguments were accepted in the October 20 direction and explicitly confirmed
October 23. Do not reopen the quotation or marker choice as an unanswered ask.

Before a syntax migration, settle regex framing, literal markers, case policy,
slash crossing, standard glob bracket edge cases, braces, and extended globs.
Keep regex quantifiers out of brace expansion. Preserve diagnostics as errors
rather than ordinary nonmatches. Retain the pure in-memory matcher boundary;
filesystem traversal and command execution belong to adapters.

## CI reconciliation

The historical plan reported a password-dependent webhook setup blocker.
Current provisioning documentation provides a credential-isolated service
under standing project onboarding authorization. Verify that service and the
existing exact-commit evidence before treating the old blocker as current.
Do not read signing secrets or change host policy as a fallback.

On October 14, the provisioning service returned success for both dry run and
provisioning. An exact-commit log query for `e99a330` returned no retained runs,
and the queue query returned no waiting or claimed jobs for that commit.
Provisioning success is not evidence of a passing build or signed push delivery.
Verify the next tested push independently before claiming remote CI success.

## Baseline verification

The previously queued October 14 `build-budget --project globlike -- ./test`
job completed at 14:58 EDT with exit code zero and a success receipt. The
receipt was recovered October 23. On October 23, `./build` also completed
successfully under the build budget in ReleaseFast. Changes since the passing
test are documentation and file annotations only; no matcher, test, or build
source changed. Exact-commit CI remains a separate check.

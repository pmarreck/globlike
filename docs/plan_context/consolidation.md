# Library verification and consolidation context

## October 23 implementation contract

Version 0.2 implements `%r[...]`, `%r{...}`, `%r(...)`, and `%r<...>`. The selected pair
balances lexically, including occurrences in regex classes and comments;
backslash shields the next byte from framing and is preserved for PCRE2.
Choose another delimiter when its characters occur unbalanced in the regex.
There are no trailing sigil flags: use PCRE2 inline flags such as `(?i)`.
Text immediately following the closing delimiter remains glob text.
Only `%r` followed by a supported opening delimiter starts an excerpt;
escape the percent sign to write a literal sigil. Glob classes are opaque to
sigil discovery. Excerpts remain independently compiled, case-sensitive by
default, and may cross path separators as ordinary regex permits.

Glob classes support positive sets, `!` or `^` negation, ranges, leading
literal `]`, escaped characters, and POSIX named classes. They consume one
Unicode character and never consume `/`. Brackets without a valid class
closing delimiter, or with a path separator inside, are literal glob text.
Locale collation/equivalence constructs are outside the portable class subset
and must report a diagnostic rather than silently receive regex semantics.
Ranges use Unicode code-point ordering, not locale collation.

This is a breaking library-language migration, with no legacy auto-detection:
old `[abc]` regex becomes `%r[abc]`; old `[[abc]]` can become `[abc]` or
`%r[[abc]]`. Full `regex:` mode remains unchanged. No persisted application
patterns are rewritten here. Filesystem CLI replacement, brace expansion,
and Bash extended globs remain separate work.

## Historical September 15 contract

The September 15 library provided `*`, `?`, and `**`, bracket-framed regex
excerpts, explicit `glob:` and `regex:` modes, and typed diagnostics. It did
not implement standard glob character classes: `[abc]` meant the sequence
`abc`. Version 0.2 replaces that framing with the contract above.

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
At that point, the exact grammar, implementation language of a future CLI,
and repository arrangement had not been selected.

Candidate regex markers discussed were `[/.../]`, `[|...|]`, and Elixir-like
`~r` sigils with selectable paired delimiters. `%r` was proposed as a marker
without tilde expansion. The October 20 decision selected `%r` with a defined
set of paired delimiters, preserving standard glob character classes. The
accepted direction is recorded in INTENT.md; the original marker question is
resolved. Version 0.2 specifies nesting, escaping, modifiers, and migration
above. Filesystem traversal remains separate work.

The shell processes arguments before the CLI receives them. `set -f` disables
pathname expansion but does not disable brace expansion, tilde expansion,
escape processing, or shell operators. The library receives strings directly
and has no dependency on shell configuration. Quoted CLI patterns, or input
through a file, stdin, or an application-owned prompt, can support arbitrary
regex without requiring users to configure `set -f`. Quoted regex-like CLI
arguments were accepted in the October 20 direction and explicitly confirmed
October 23. Do not reopen the quotation or marker choice as an unanswered ask.

Braces and extended globs remain future language work. Keep regex quantifiers
out of any future brace expansion. Preserve diagnostics as errors rather than
ordinary nonmatches. Retain the pure in-memory matcher boundary; filesystem
traversal and command execution belong to adapters.

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
successfully under the build budget in ReleaseFast. That documentation-only
baseline was committed as `6a33bad84d3b00f5d3c1cf6a2037deb4e7beb643`;
its exact-commit CI passed October 23 at 11:23 EDT. The version 0.2 implementation
requires fresh local and exact-commit verification.

## Version 0.2 verification

The new sigil/class tests first failed against the version 0.1 grammar. The
independent libc comparison then found a translation defect: ordinary class
punctuation could acquire PCRE2's special POSIX syntax. A focused regression
also failed before the translator escaped that punctuation. The corrected
`./test` passed all 35 tests on October 23 at 20:27 EDT. The test executable
took 58 ms; the Nix build phase took 1 minute 44 seconds, mostly compilation.
The ReleaseFast `./build` also passed at 20:28 EDT.

The differential oracle exhausts strings of length zero through three over a
fixed ASCII alphabet. It covers the common subset with musl `fnmatch`.
Backslashes inside classes and slash-containing brackets differ between musl
and Bash pathname expansion; separate tests preserve the observed Bash
behavior and explicitly check those musl differences. Unicode, sigils, case
scope, malformed input, source offsets, and allocation failures have their
own portable tests. Native execution evidence is Linux x86_64 only.

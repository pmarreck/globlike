# globlike

Provide one portable pattern language for RotShield, dirtree, and other callers
that currently maintain separate glob-to-PCRE2 translators. Patterns should
remain readable for ordinary path selection while allowing explicit regex use.

## Accepted language direction

The October 20 decision selects `%r` regex sigils with a defined set of paired
delimiters while preserving standard glob character classes. `[abc]` should
match one character from that set; regex excerpts will use an explicit sigil.
The library and CLI should interpret the same pattern language.

Regex-like CLI arguments are expected to be quoted, confirmed October 23.
No caller needs to configure Bash with `set -f`. The library receives strings
directly and has no shell dependency. Avoid changing pattern syntax merely to
evade shell processing; choose delimiters for readable regex instead.

The marker decision does not settle the exact delimiter set, nesting and
escape rules, flags, compatibility migration, or filesystem adapter design.
Specify those before replacing the current grammar. Consolidation with `glob`
remains a direction under discussion, not a completed repository merger.

## Implemented baseline

The September 15 implementation has `*`, `?`, and `**` as its only glob
operators, bracket-delimited inline regex excerpts, and backslash escaping of
literal glob-text brackets. It has not yet migrated to the accepted `%r`
direction. Bare patterns use glob mode; `glob:` and `regex:` select the mode
explicitly. Forward slashes are portable pattern separators.

The library is pure in-memory work. Applications own filesystem traversal,
basename matching policy, settings persistence, and presentation. PCRE2 owns
regex compilation and DFA matching. Its fork's compatibility query must reject
unsupported compiled constructs before applications accept saved patterns.
Resource and input failures remain errors, never ordinary nonmatches.

Build parser changes from failing edge-case tests. The baseline delimiter
scanner uses a small stack and follows the September 15 decision that unescaped
brackets balance independently of PCRE2's literal/comment rules. Literal
brackets require backslash escaping in both glob text and inline excerpts.
Full `regex:` mode bypasses excerpt framing and retains PCRE2 syntax. This
historical rule is not a settled framing rule for the future sigil grammar.

Success means shared classifier tests over candidate sets, precise malformed
pattern diagnostics, allocation-failure cleanup, and adoption in both callers.
MIT publication, a README, and RotShield adoption were authorized on September
15, 2026. A thin filesystem matching CLI may follow library integration; decide
its relationship to `glob` before introducing another command.

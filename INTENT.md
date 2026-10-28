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

The sibling `glob` command consumes this repository as a pinned dependency,
decided by Peter on October 28, 2026. `globlike` is its sole pattern engine;
filesystem traversal, brace expansion, command execution, and presentation
remain in that command's adapter rather than entering this library.

## Implemented language

Version 0.3 provides `*`, `?`, `**`, Bash-style extended globs, ordinary glob
character classes, and `%r[...]`, `%r{...}`, `%r(...)`, and `%r<...>` regex
excerpts. Bare patterns use glob mode; `glob:` and `regex:` select the mode
explicitly. Forward slashes are
portable pattern separators. Existing `[regex]` excerpts must be migrated to
`%r[regex]`; there is no ambiguous legacy auto-detection.

The library is pure in-memory work. Applications own filesystem traversal,
basename matching policy, settings persistence, and presentation. PCRE2 owns
regex compilation and DFA matching. Its fork's compatibility query must reject
unsupported compiled constructs before applications accept saved patterns.
Resource and input failures remain errors, never ordinary nonmatches.

Build parser changes from failing edge-case tests. The iterative excerpt
scanner balances the selected delimiter pair lexically, including occurrences
inside regex classes and comments. Backslash shields the next byte from
framing and remains in the regex body. Choose another delimiter when needed.
Flags use regex inline options, not sigil suffixes. Extended globs provide
`?(...)`, `*(...)`, `+(...)`, `@(...)`, and `!(...)`, with `|` alternatives and
nesting. Full `regex:` mode bypasses excerpt framing and retains PCRE2 syntax.
See README.md for bracket edge cases and the migration guide.

Success means shared classifier tests over candidate sets, precise malformed
pattern diagnostics, allocation-failure cleanup, and adoption in both callers.
MIT publication, a README, and RotShield adoption were authorized on September
15, 2026. Do not introduce a competing filesystem CLI here: the sibling `glob`
repository owns that adapter and pins this library.

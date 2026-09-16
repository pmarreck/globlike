# globlike

Provide one portable pattern language for RotShield, dirtree, and other callers
that currently maintain separate glob-to-PCRE2 translators. Patterns should
remain readable for ordinary path selection while allowing explicit regex use.

Peter approved `*`, `?`, and `**` as the only glob operators, bracket-delimited
inline regex excerpts, and backslash escaping of literal glob-text brackets on
September 15, 2026. Bare patterns use glob mode; `glob:` and `regex:` select
the mode explicitly. Forward slashes are portable pattern separators.

The library is pure in-memory work. Applications own filesystem traversal,
basename matching policy, settings persistence, and presentation. PCRE2 owns
regex compilation and DFA matching. Its fork's compatibility query must reject
unsupported compiled constructs before applications accept saved patterns.
Resource and input failures remain errors, never ordinary nonmatches.

Build the parser from failing edge-case tests. Delimiter discovery uses a
small stack. Peter confirmed on September 15, 2026 at 21:41 EDT that unescaped
brackets must balance independently of PCRE2's literal/comment rules. Literal
brackets require backslash escaping in both glob text and inline excerpts.
Full `regex:` mode bypasses excerpt framing and retains PCRE2 syntax.

Success means shared classifier tests over candidate sets, precise malformed
pattern diagnostics, allocation-failure cleanup, and adoption in both callers.
Keep this repository local until publication is requested.

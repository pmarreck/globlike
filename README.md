# globlike

A shared pattern library under development for RotShield and dirtree.
The first implemented component is a pure Zig delimiter scanner. Translation,
PCRE2 validation/matching, mode prefixes, and application adoption are pending.

The agreed language has three glob operators (`*`, `?`, `**`), `[regex]`
excerpts, and backslash escapes for literal glob brackets. Bare patterns and
`glob:` will use glob mode; `regex:` will select a full PCRE2 DFA regex.

## Delimiter scanner

`parse(allocator, source)` returns owned segment storage or a diagnostic with
a zero-based byte offset. Segments refer to the source by half-open offsets.
They exclude the outer regex markers and preserve all escape bytes. Call
`result.deinit(allocator)` to release storage; the source belongs to the caller.
An invalid delimiter returns no partial segments. Allocation failure remains
an error distinct from malformed syntax.

| Source | Segments or error |
| --- | --- |
| `[Users|home]/[\p{L}+]/**` | Regex, glob `/`, regex, glob `/**` |
| `file\[draft\].txt` | One glob segment with literal-bracket escapes |
| `[[a-z]]` | Regex `[a-z]` |
| `[ \]]` | Regex matching a space followed by `]` |
| `[ ]\]` | Regex space, then glob literal-bracket escape |
| `[ ]]` | Unexpected closing bracket at byte 3 |
| `[a][][b]` | Three separate excerpts; the middle excerpt is empty |
| `\\[a]` | Escaped glob backslash, followed by regex `a` |

The current scanner balances every unescaped square bracket using a heap
stack. A backslash shields the following byte from delimiter recognition.
Parsing takes O(input length) time, O(nesting depth) stack storage, and
O(segment count) output storage. It uses no recursion or filesystem operations.

This framing rule is independent of PCRE2's lexical rules. Inside excerpts,
use `[\]]` rather than `[]]` for a regex class matching `]`, and `[\[]`
rather than `[[]` for one matching `[`. Quotes and regex comments do not hide
brackets from the framing layer. Whether to add PCRE2-aware framing instead is
an open design question; this first milestone does not claim that support.
Full `regex:` mode will bypass glob excerpt framing entirely.

## Development

Run `./test` for the complete suite in ReleaseSafe and `./build` for the
ReleaseFast library build. Both use Nix and pinned Zig 0.16.0 from zig-overlay.
Use `nix develop -c zig build test -Doptimize=Debug` for local debugging.

Seven initial tests failed against a stub before implementation. The suite
also checks all allocation-failure points on successful and malformed input,
10,000 nested bracket pairs, Unicode offsets, and lossless source reconstruction.
These checks establish delimiter behavior; they do not establish regex validity
or matching semantics. See [PLAN.md](PLAN.md) for the remaining stages.

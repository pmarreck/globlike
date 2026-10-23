# globlike

A portable Zig pattern library for paths, with inline PCRE2 expressions and
structured diagnostics. PCRE2 is a pinned transitive dependency; applications
import the `globlike` module. RotShield and dirtree adoption is in progress.

The [accepted next language direction](INTENT.md) uses `%r` regex sigils and
standard glob character classes, with quoted regex-like CLI arguments. That
migration is not implemented yet; the syntax below describes the current code.

[![Mechatron Prime CI](https://img.shields.io/endpoint?url=https%3A%2F%2Fthelio-nixos.tail66c90.ts.net%2Fbadges%2Fgloblike.json&style=for-the-badge)](https://thelio-nixos.tail66c90.ts.net/mechatron-prime/)

The agreed language has three glob operators (`*`, `?`, `**`), `[regex]`
excerpts, and backslash escapes for literal glob brackets. Bare patterns and
`glob:` use glob mode; `regex:` selects a PCRE2 DFA regex.

## Matching

`*` matches zero or more non-slash characters, `?` matches one Unicode character
other than slash, and `**` also crosses slashes. `**/` matches zero or more
complete directory components. Glob patterns match the entire subject,
including its true end if it contains a newline. `/` is the separator on every
platform; callers normalize Windows paths before matching. A backslash escapes
the next character in glob text. Other punctuation is literal.

Inline excerpts are regex, so `[abc]` matches the sequence `abc`, while
`[[abc]]` matches one character from that set. Grouping, alternation, counted
repetition, Unicode properties, and scoped flags work inside excerpts. Each
excerpt must compile independently, preventing it from escaping its scope.
Excerpts default to case-sensitive matching even when glob text is caseless;
explicit regex flags can override this within the excerpt.

Full regex mode searches the subject unless the expression supplies anchors.
Use `regex:\Afoo\z` for an exact match. `regex:/foo/i` is also accepted; its
supported trailing flags are `i`, `m`, `s`, `x`, `U`, and `u`. A raw expression
starting with `/` therefore needs an escaped leading slash or a group around
the expression. PCRE2 inline flags, such as `(?-i)`, override the default case
option. UTF-8 and Unicode properties are always enabled.

```zig
const globlike = @import("globlike");
var result = try globlike.compile(allocator, "[Users|home]/[\\p{L}+]/**", .{});
switch (result) {
    .diagnostic => |diagnostic| report(diagnostic),
    .pattern => |*pattern| {
        defer pattern.deinit();
        switch (pattern.matches("home/Élodie/photos/a.jpg")) {
            .matched => |matched| useResult(matched),
            .diagnostic => |diagnostic| report(diagnostic),
        }
    },
}
```

`PatternSet.add(source, options)` validates before adding; an invalid addition
leaves existing rules intact. `matchesAny(path, optional_basename)` composes
patterns when possible and reports the responsible rule index on failure.
Each pattern/set owns mutable matching scratch storage; use separate instances
for concurrent callers. All owned storage has an explicit `deinit`.

## Error handling

Diagnostics retain a typed category, native PCRE2 code where applicable, and
an optional source byte offset. `diagnostic.message(buffer)` returns readable
wording. Library-only failures have engine code zero; enum values distinguish
them without inventing a native error code. Allocation failures during compile
or set addition return Zig `error.OutOfMemory`.

Compilation catches syntax errors. A compiled-instruction preflight rejects
unsupported DFA features, including backreferences, variable-length lookbehind,
recursion, and subroutine calls. It examines hidden branches without needing
sample subjects. This is a conservative check, not a formal completeness proof.

Matching can still encounter invalid UTF-8, memory/workspace limits, or other
engine resource errors. These return diagnostics and are never reported as
nonmatches. An application can log the path, pattern, code, and message, and
continue independent work while marking its overall result incomplete.
Revalidate persisted patterns whenever the engine or options change.

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
brackets from the framing layer. This stricter framing rule was confirmed by
Peter on September 15, 2026. Full `regex:` mode bypasses glob excerpt
framing entirely.

## Development

Run `./test` for the complete suite in ReleaseSafe and `./build` for the
ReleaseFast library build. Both use Nix and pinned Zig 0.16.0 from zig-overlay.
Use `nix develop -c zig build test -Doptimize=Debug` for local debugging.

Seven initial tests failed against a stub before implementation. The suite
also checks all allocation-failure points on successful and malformed input,
10,000 nested bracket pairs, Unicode offsets, and lossless source reconstruction.
Matching tests classify candidate sets, check case isolation and true path
boundaries, exercise DFA preflight, and distinguish resource/input errors from
nonmatches. `nix build .#checks.x86_64-linux.cross` compiles the suite for Linux
and Windows on x86_64/ARM64, plus macOS ARM64; compilation is not native execution.
See [PLAN.md](PLAN.md) for application integration and the optional thin CLI.

## License

globlike is [MIT licensed](LICENSE). Its PCRE2 dependency retains its own
[BSD license and notices](PCRE2-LICENSE.md), installed with the library build.

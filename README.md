# globlike

A portable Zig pattern library for paths, with inline PCRE2 expressions and
structured diagnostics. PCRE2 is a pinned transitive dependency; applications
import the `globlike` module. RotShield and dirtree adoption is in progress.

[![Mechatron Prime CI](https://img.shields.io/endpoint?url=https%3A%2F%2Fthelio-nixos.tail66c90.ts.net%2Fbadges%2Fgloblike.json&style=for-the-badge)](https://thelio-nixos.tail66c90.ts.net/mechatron-prime/)

The language combines glob operators (`*`, `?`, `**`), ordinary glob character
classes, and `%r` regex excerpts. Bare patterns and `glob:` use glob mode;
`regex:` selects a PCRE2 DFA regex. Version 0.2.0 changes bracket semantics;
see the migration examples below before upgrading saved patterns.

## Matching

`*` matches zero or more non-slash characters, `?` matches one Unicode character
other than slash, and `**` also crosses slashes. `**/` matches zero or more
complete directory components. Glob patterns match the entire subject,
including its true end if it contains a newline. `/` is the separator on every
platform; callers normalize Windows paths before matching. A backslash escapes
the next character in glob text. Braces and Bash extended globs are not
expanded; punctuation is literal except for glob classes and `%r` markers.

`[abc]` matches one character from that set. Classes also support ranges such
as `[a-z]`, negation with `[!abc]` or `[^abc]`, POSIX named classes such as
`[[:digit:]]`, leading literal `]` as in `[]a]`, and escaped characters. An
escaped `d` in `[\d]` is the letter `d`, not a regex digit escape. Classes
never match `/`, including negated classes. Matching is Unicode-aware, with
code-point ranges independent of the process locale. Locale collating and
equivalence forms (`[[.a.]]`, `[[=a=]]`) return `unsupported_glob_class`.
An unmatched `[` or `]` is literal. A bracket expression containing a path
separator is also literal, so `[/abc/]` denotes that literal path.

Regex excerpts use `%r[...]`, `%r{...}`, `%r(...)`, or `%r<...>`. Thus `%r[abc]`
matches the sequence `abc`, and `%r[[abc]]` is the regex character class.
Grouping, alternation, counted repetition, Unicode properties, and inline
flags work inside excerpts. Each excerpt must compile independently,
preventing it from escaping its scope. Regex may consume `/`; its delimiters
are not path separators. The enclosing glob still matches the whole subject.
Excerpts default to case-sensitive matching even when glob text is caseless;
explicit regex flags can override this within the excerpt, for example
`%r{(?i)abc}`. There are no trailing excerpt flags: `%r[abc]i` matches `abci`.
Escape the percent sign to write a literal sigil, as in `\%r{abc}`. `%r` only
opens an excerpt when immediately followed by one of the four opening
delimiters. Sigils inside a glob character class are ordinary class text.

Full regex mode searches the subject unless the expression supplies anchors.
Use `regex:\Afoo\z` for an exact match. `regex:/foo/i` is also accepted; its
supported trailing flags are `i`, `m`, `s`, `x`, `U`, and `u`. A raw expression
starting with `/` therefore needs an escaped leading slash or a group around
the expression. PCRE2 inline flags, such as `(?-i)`, override the default case
option. UTF-8 and Unicode properties are always enabled.

```zig
const globlike = @import("globlike");
var result = try globlike.compile(allocator, "%r[Users|home]/%r{\\p{L}+}/**", .{});
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
| `%r[Users\|home]/%r{\p{L}+}/**` | Regex, glob `/`, regex, glob `/**` |
| `file\[draft\].txt` | One glob segment with literal-bracket escapes |
| `[a-z]` | One glob segment containing a character class |
| `%r[[a-z]]` | Regex `[a-z]` |
| `%r{\d{4}}` | Regex `\d{4}` with nested brace delimiters |
| `%r[ \]]` | Regex matching a space followed by `]` |
| `a%r[bc` | Unclosed excerpt at byte 1 (the `%`) |
| `%r[a]%r{}%r(b)` | Three excerpts; the middle excerpt is empty |
| `\\%r[a]` | Escaped glob backslash, followed by regex `a` |

An excerpt balances its selected delimiter pair, using an iterative depth
counter. A backslash shields the next byte from framing; all escape bytes
remain intact for PCRE2. This is a lexical rule: regex classes, quotes, and
comments do not hide the selected delimiter. For example, use `%r{[]]}` for
a regex class matching `]`, or `%r{(?<=a)b}` for lookbehind, rather than choosing
delimiters that occur unbalanced in those expressions. Escaping delimiter
characters or using full `regex:` mode are other options.

Parsing takes O(input length) time and auxiliary storage. A suffix index
prevents repeated scans for malformed glob classes; output storage is
O(segment count). Parsing uses no recursion or filesystem operations. Regex
segment offsets exclude `%r` and the outer delimiter pair; glob class text
remains within glob segments.

## Migrating from 0.1.0

There is no automatic legacy detection because old regex brackets collide
with ordinary glob character classes. Translate saved patterns deliberately:

| Old pattern | New pattern with the same intended match |
| --- | --- |
| `[abc]` | `%r[abc]` |
| `[[abc]]` | `[abc]` or `%r[[abc]]` |
| `[Users\|home]/[\p{L}+]/**` | `%r[Users\|home]/%r{\p{L}+}/**` |
| `A[(?i)bc]D` | `A%r[(?i)bc]D` |
| `regex:\Afoo\z` | Unchanged |

Glob classes follow the glob case option; excerpts keep their own regex case
scope. Use `%r[[abc]]` when migrating a regex class that must stay
case-sensitive even if glob text is caseless. Revalidate patterns before
saving them. This library update does not rewrite any application's settings.

Applications exposing these patterns through a shell CLI should document
single-quoted arguments, such as `'**/photo-%r{[0-9]{4}}.jpg'`. The library
has no shell dependency and requires no `set -f` configuration. Quoting is
shell syntax, not part of the pattern string passed to `compile`. The existing
sibling `glob` command is not yet a consumer of this library.

## Development

Run `./test` for the complete suite in ReleaseSafe and `./build` for the
ReleaseFast library build. Both use Nix and pinned Zig 0.16.0 from zig-overlay.

Seven initial tests failed against a stub before implementation. The suite
also checks all allocation-failure points on successful and malformed input,
10,000 nested delimiter pairs, Unicode offsets, and lossless source reconstruction.
Matching tests classify candidate sets, check case isolation and true path
boundaries, exercise DFA preflight, and distinguish resource/input errors from
nonmatches. The sigil/class suite was observed failing against the old grammar
before implementation. On Linux, a differential test compares the shared ASCII
glob subset with libc `fnmatch` over all strings of length zero through three
from a fixed alphabet. musl's different treatment of class backslashes and
slash-containing brackets is covered by separate Bash-characterized tests.
This oracle test is skipped on other operating systems; portable classifier
tests still run there.
`nix build .#checks.x86_64-linux.cross` compiles the suite for Linux
and Windows on x86_64/ARM64, plus macOS ARM64; compilation is not native execution.
See [PLAN.md](PLAN.md) for application integration and the optional thin CLI.

## License

globlike is [MIT licensed](LICENSE). Its PCRE2 dependency retains its own
[BSD license and notices](PCRE2-LICENSE.md), installed with the library build.

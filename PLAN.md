# globlike implementation

- [x] Establish a failing delimiter suite before implementation: multiple
  excerpts, nested brackets, escapes, trailing backslashes, and source offsets.
  Curiosity poke: an escaped backslash must not also escape the next bracket.
- [x] Implement the pure stack-based delimiter scanner with owned token storage
  and borrowed source slices. Curiosity poke: cleanup on every allocation error.
  Completed 2026-09-15 16:26 EDT. Seven initial tests failed against the stub;
  all 11 final tests pass, including allocation-failure sweeps and 10,000-level
  nesting. ReleaseFast build passes on Linux x86_64. Flake outputs evaluate
  for Linux x86_64/ARM64 and macOS ARM64; native runs elsewhere remain pending.
- [x] Settle literal brackets inside excerpts with Peter; preserve PCRE2 escapes
  unchanged. Curiosity poke: PCRE2's `[]]` and `[[]` are not balanced spellings.
  Peter confirmed strict balanced framing and escaped literal brackets inside
  excerpts on 2026-09-15 at 21:41 EDT. Keep the existing scanner; full regex
  mode will bypass framing.
- [ ] Translate the three glob operators, implement explicit modes and scoped
  case behavior, and connect the existing PCRE2 DFA compatibility query.
  Curiosity poke: `**/foo` must match `foo` and `a/foo`, never `barfoo`.
- [ ] Test matching over candidate sets and expose reusable diagnostics/C API.
  Curiosity poke: an invalid exception must not silently become a nonmatch.
- [ ] Adopt in RotShield and dirtree, replacing superseded translators and tests.
  Curiosity poke: keep each application's path/basename policy explicit.

The first milestone is a tested delimiter scanner, not a complete matcher.

# PLAN log

Completed PLAN.md items retired by plan-retire, oldest retirement first.

Historical owner references are normalized to BDFN (Benevolent Dictator For Now).
The original wording remains recoverable from the pre-migration Git revision.

## Retired 2026-10-14

- [x] [globlike implementation] Preserve diagnostic category, engine code, readable message, and source offset across compilation, DFA preflight, and matching; never collapse a runtime error into false (BDFN, September 15 evening).
- [x] [globlike implementation] Establish a failing delimiter suite before implementation: multiple excerpts, nested brackets, escapes, trailing backslashes, and source offsets. Curiosity poke: an escaped backslash must not also escape the next bracket.
- [x] [globlike implementation] Implement the pure stack-based delimiter scanner with owned token storage and borrowed source slices. Curiosity poke: cleanup on every allocation error. Completed 2026-09-15 16:26 EDT. Seven initial tests failed against the stub; all 11 final tests pass, including allocation-failure sweeps and 10,000-level nesting. ReleaseFast build passes on Linux x86_64. Flake outputs evaluate for Linux x86_64/ARM64 and macOS ARM64; native runs elsewhere remain pending.
- [x] [globlike implementation] Settle literal brackets inside excerpts with BDFN; preserve PCRE2 escapes unchanged. Curiosity poke: PCRE2's `[]]` and `[[]` are not balanced spellings. BDFN confirmed strict balanced framing and escaped literal brackets inside excerpts on 2026-09-15 at 21:41 EDT. Keep the existing scanner; full regex mode will bypass framing.
- [x] [globlike implementation] Translate the three glob operators, implement explicit modes and scoped case behavior, and connect the existing PCRE2 DFA compatibility query. Curiosity poke: `**/foo` must match `foo` and `a/foo`, never `barfoo`.
- [x] [globlike implementation] Test matching over candidate sets and expose reusable Zig diagnostics. Curiosity poke: an invalid exception must not silently become a nonmatch.

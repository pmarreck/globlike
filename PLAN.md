# globlike implementation

- [ ] Complete and publish the MIT-licensed library with README, then adopt it
  in RotShield (Peter, September 15 evening). Add a thin matching CLI after
  the library and unattended-scan error reporting are complete.
- [x] Preserve diagnostic category, engine code, readable message, and source
  offset across compilation, DFA preflight, and matching; never collapse a
  runtime error into false (Peter, September 15 evening).

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
- [x] Translate the three glob operators, implement explicit modes and scoped
  case behavior, and connect the existing PCRE2 DFA compatibility query.
  Curiosity poke: `**/foo` must match `foo` and `a/foo`, never `barfoo`.
- [x] Test matching over candidate sets and expose reusable Zig diagnostics.
  Curiosity poke: an invalid exception must not silently become a nonmatch.
- [ ] Adopt in RotShield and dirtree, replacing superseded translators and tests.
  Curiosity poke: keep each application's path/basename policy explicit.

The matcher passes 26 tests, including allocation-failure sweeps, invalid UTF-8,
bounded DFA workspace, and hidden unsupported branches. ReleaseFast builds and
test compilation for all five target platforms pass (2026-09-15 22:13 EDT,
approximate). Linux test execution uses musl to avoid the unavailable default
ELF loader in Nix's sandbox. Other platforms have compilation evidence only.

- [ ] Provision the new GitHub webhook and verify remote CI. The local command
  needs a sudo password; no secret was read or copied. Local test/build and
  cross-compilation checks remain available.
- [ ] Add a C API if a consumer needs one; current consumers import Zig modules.

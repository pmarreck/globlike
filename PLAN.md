# PLAN

Historical completions: [docs/PLAN_LOG.md](docs/PLAN_LOG.md). Current context: [library and consolidation](docs/plan_context/consolidation.md).

## Shared language design

- [ ] Decide the glob consumer and repository arrangement before implementing a separate matching CLI.

## Integration

- [ ] Reconcile RotShield and dirtree adoption with the settled language contract, keeping path and basename policy explicit.
- [ ] Add a C API when a concrete consumer requires it.

## Recent completion

- [x] Implement version 0.2 paired %r excerpts and ordinary glob classes; 35 tests and ReleaseFast build pass, with migration documentation (done 2026-10-23 20:28 EDT; context: docs/plan_context/consolidation.md).
- [x] Verify baseline exact-commit CI for 6a33bad84d3b; the run passed October 23 at 11:23 EDT (verified 2026-10-23; context: docs/plan_context/consolidation.md).
- [x] Verify the unchanged implementation with the successful October 14 ./test receipt and October 23 ReleaseFast ./build (done 2026-10-23 10:29 EDT).
- [x] Select %r sigils, preserve standard glob brackets, and expect quoted regex-like CLI arguments without requiring set -f (decided 2026-10-20; confirmed 2026-10-23 10:25 EDT; context: INTENT.md).
- [x] Reconcile the CI webhook through the current provisioning service; dry run and provisioning succeeded (done 2026-10-14 14:37 EDT).

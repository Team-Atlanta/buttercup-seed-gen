# Buttercup Seed-Gen Standalone

## What This Is

A slimmed-down version of Buttercup's oss-crs that focuses solely on seed generation. Instead of the full fuzzing pipeline (seedgen → fuzzer → POV), this tool generates seeds and submits them directly to the competition API via `libcrs register-submit-dir seed`.

## Core Value

Generate quality seeds and submit them to the competition API without the overhead of fuzzing infrastructure.

## Requirements

### Validated

<!-- Existing capabilities that work and we're keeping -->

- ✓ Seedgen generates targeted seed inputs based on code analysis — existing
- ✓ Coverage-bot monitors and reports coverage metrics — existing
- ✓ Redis-based queue communication between components — existing
- ✓ Orchestrator populates Redis with build artifacts — existing
- ✓ OSS-CRS docker build/run infrastructure — existing

### Active

<!-- Current scope. Building toward these. -->

- [ ] Remove fuzzer-bot from oss-crs services (crs.yaml)
- [ ] Seedgen submits seeds directly to `libcrs register-submit-dir seed` directory
- [ ] Remove POV submission path (no longer needed without fuzzer)
- [ ] Verify slimmed services deploy and run successfully

### Out of Scope

- Fuzzing capability — deliberately removed for this standalone tool
- Triaging/TracerBot — not needed without crash analysis
- Patcher — no vulnerabilities to patch without fuzzer
- Full Buttercup CRS deployment — this is oss-crs only

## Context

This work modifies the `oss-crs/` directory which contains a simplified deployment of Buttercup for the OSS-Fuzz CRS competition track. The current architecture:

**Current services in crs.yaml:**
- `redis` — message broker (keep)
- `orchestrator` — populates Redis from disk artifacts (keep)
- `fuzzer-bot` — runs libfuzzer (REMOVE)
- `coverage-bot` — coverage metrics (keep)
- `seed-gen` — generates seeds (keep, modify output)

**Data flow change:**
- OLD: seedgen → Redis → fuzzer-bot → crashes → POV submission
- NEW: seedgen → `libcrs register-submit-dir seed` directly

The `libcrs` CLI is the standard interface for submitting artifacts to the competition API.

## Constraints

- **Interface**: Must use `libcrs register-submit-dir seed` for submission — competition API requirement
- **Existing code**: Prefer modifying existing seedgen over creating new submission logic

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Keep coverage-bot | Still useful for seed quality metrics | — Pending |
| Keep orchestrator | Required to populate Redis for seedgen task discovery | — Pending |
| Direct libcrs submission | Simplest path, matches competition API expectations | — Pending |

---
*Last updated: 2026-03-10 after initialization*

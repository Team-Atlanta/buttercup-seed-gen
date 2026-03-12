# Buttercup Seed-Gen Standalone

## What This Is

A slimmed-down version of Buttercup's oss-crs that focuses solely on seed generation. Instead of the full fuzzing pipeline (seedgen → fuzzer → POV), this tool generates seeds and submits them directly to the competition API via `libcrs register-submit-dir seed`. Supports both C/C++ and Java targets.

## Core Value

Generate quality seeds and submit them to the competition API without the overhead of fuzzing infrastructure.

## Current Milestone: v1.1 Java Support

**Goal:** Add full Java/Jazzer support to seed-gen standalone, including JaCoCo coverage integration.

**Target features:**
- Java language declared in crs.yaml supported_target
- JaCoCo coverage execution in builder-coverage.sh helper.py
- Coverage-bot parses JaCoCo XML for Java targets

## Requirements

### Validated

<!-- Shipped and confirmed working -->

- ✓ Seedgen generates targeted seed inputs based on code analysis — v1.0
- ✓ Coverage-bot monitors and reports coverage metrics — v1.0
- ✓ Redis-based queue communication between components — v1.0
- ✓ Orchestrator populates Redis with build artifacts — v1.0
- ✓ OSS-CRS docker build/run infrastructure — v1.0
- ✓ Fuzzer-bot removed, 4-service architecture — v1.0
- ✓ Seed-only task distribution (SEED_INIT, SEED_EXPLORE) — v1.0
- ✓ No POV/crash infrastructure — v1.0
- ✓ Seeds submitted via libCRS register-submit-dir — v1.0

### Active

<!-- Current scope. Building toward these. -->

- [ ] Add java/jvm to crs.yaml supported_target.language
- [ ] Add JaCoCo coverage execution to builder-coverage.sh helper.py
- [ ] Ensure JaCoCo JARs available in coverage builder image
- [ ] Verify Java coverage-bot integration with existing CoverageRunner.run_java()

### Out of Scope

- Fuzzing capability — deliberately removed for this standalone tool
- Triaging/TracerBot — not needed without crash analysis
- Patcher — no vulnerabilities to patch without fuzzer
- Full Buttercup CRS deployment — this is oss-crs only
- Go/Python/JavaScript coverage — focus on C/C++ and Java only

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
| Keep coverage-bot | Still useful for seed quality metrics | ✓ Good |
| Keep orchestrator | Required to populate Redis for seedgen task discovery | ✓ Good |
| Direct libcrs submission | Simplest path, matches competition API expectations | ✓ Good |
| Imitate OSS-Fuzz helper.py for Java coverage | Consistent with upstream, uses JaCoCo agent + CLI | — Pending |

---
*Last updated: 2026-03-12 after v1.1 milestone start*

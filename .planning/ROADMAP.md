# Roadmap: Buttercup Seed-Gen Standalone

**Project:** Extract seed-gen as standalone service from OSS-CRS
**Created:** 2026-03-10
**Granularity:** Coarse (3-5 phases, 1-3 plans each)

## Phases

- [x] **Phase 1: Service & Configuration Removal** - Remove fuzzer-bot service and update deployment configurations (completed 2026-03-10)
- [x] **Phase 2: Code Cleanup** - Remove fuzzer-specific code paths from retained services (completed 2026-03-10)
- [x] **Phase 3: Validation & Documentation** - Verify standalone deployment and document architecture (completed 2026-03-11)

## Phase Details

### Phase 1: Service & Configuration Removal
**Goal**: Fuzzer-bot is completely removed from service definitions and deployment configurations

**Depends on**: Nothing (first phase)

**Requirements**: SVC-01, SVC-02, SVC-03, SVC-04, SVC-05, CODE-02, CLN-01

**Success Criteria** (what must be TRUE):
  1. Only redis, orchestrator, coverage-bot, and seed-gen services remain in crs.yaml
  2. Docker build completes without fuzzer-builder stage artifacts
  3. Entrypoint script routes to seedgen but not fuzzer-bot
  4. Seeds are written to /artifacts/corpus/ with hash-based filenames
  5. libCRS watcher successfully submits seeds to competition API

**Plans**: 1 plan

Plans:
- [x] 01-01-PLAN.md — Remove fuzzer-bot from crs.yaml, entrypoint, and Dockerfile

### Phase 2: Code Cleanup
**Goal**: Retained services contain no dead code paths or orphaned dependencies

**Depends on**: Phase 1 (service removal must complete before code cleanup)

**Requirements**: CODE-01, CODE-03, CODE-04, CLN-02

**Success Criteria** (what must be TRUE):
  1. Seedgen task distribution contains only seed-init and seed-explore (no vuln-discovery)
  2. No references to crash_queue, crash_set, or CrashSubmit in seed-gen code
  3. No POV submission logic in entrypoint or seedgen bot
  4. All seed-gen component tests pass

**Plans**: 2 plans

Plans:
- [x] 02-01-PLAN.md — Remove vuln-discovery from task probability distribution
- [x] 02-02-PLAN.md — Remove crash infrastructure, POV submission, and vuln-discovery files

### Phase 3: Validation & Documentation
**Goal**: Standalone seedgen deployment is verified working and documented

**Depends on**: Phase 2 (code cleanup must complete before validation)

**Requirements**: CODE-05, VAL-01, VAL-02, VAL-03

**Success Criteria** (what must be TRUE):
  1. Fresh deployment from scratch completes successfully with all four services
  2. Seeds are generated and appear in competition API submission logs
  3. Coverage-bot runs and populates CoverageMap without fuzzer-bot dependency
  4. README documents standalone architecture with no fuzzer references

**Plans**: 3 plans

Plans:
- [x] 03-01-PLAN.md — Verify seed-gen unit tests pass after code cleanup
- [x] 03-02-PLAN.md — Validate end-to-end deployment with 4 services
- [x] 03-03-PLAN.md — Document standalone architecture in README

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Service & Configuration Removal | 1/1 | Complete    | 2026-03-10 |
| 2. Code Cleanup | 2/2 | Complete | 2026-03-10 |
| 3. Validation & Documentation | 3/3 | Complete   | 2026-03-11 |

## Coverage Map

| Requirement | Phase | Rationale |
|-------------|-------|-----------|
| SVC-01 | Phase 1 | Remove fuzzer-bot from crs.yaml |
| SVC-02 | Phase 1 | Keep redis - verified in service config |
| SVC-03 | Phase 1 | Keep orchestrator - verified in service config |
| SVC-04 | Phase 1 | Keep coverage-bot - verified in service config |
| SVC-05 | Phase 1 | Keep seed-gen - verified in service config |
| CODE-01 | Phase 2 | Remove vuln-discovery from task distribution |
| CODE-02 | Phase 1 | Remove fuzzer case from entrypoint |
| CODE-03 | Phase 2 | Remove crash queue references |
| CODE-04 | Phase 2 | Remove POV submission logic |
| CODE-05 | Phase 3 | Verify libCRS seed submission works |
| CLN-01 | Phase 1 | Remove fuzzer build stages from Dockerfile |
| CLN-02 | Phase 2 | Remove orphaned Redis crash queue setup |
| VAL-01 | Phase 3 | Verify deployment with slimmed config |
| VAL-02 | Phase 3 | Verify seedgen generates and submits seeds |
| VAL-03 | Phase 3 | Verify coverage-bot runs independently |

**Coverage**: 15/15 requirements mapped (100%)

## Notes

### Phase Grouping Rationale

**Phase 1 groups all deployment artifacts** (crs.yaml, Dockerfile, entrypoint script) to minimize deployment cycles. All service definition changes happen in one phase for atomic verification.

**Phase 2 isolates Python code changes** to seed-gen component for focused testing. Code cleanup happens after service removal to get accurate picture of remaining dependencies.

**Phase 3 is end-to-end validation** requiring Phases 1-2 stability. Cannot verify deployment until both service config and code cleanup are complete.

### Scope Decisions

Per PROJECT.md, POV generation is **out of scope** for standalone seedgen. This means:
- Remove vuln-discovery tasks (Phase 2)
- Remove POV submit-dir registration (Phase 2)
- Focus purely on seed quality

### Dependencies Identified

- Coverage-bot depends on corpus inputs (currently fuzzer + seedgen, becomes seedgen-only after Phase 1)
- Seed-gen depends on BuildType.FUZZER enum despite fuzzer-bot removal (still processing fuzzer harnesses)
- libCRS watcher depends on correct CORPUS_DIR environment variable (validated in Phase 3)

---
*Last updated: 2026-03-12*

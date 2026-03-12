# Roadmap: Buttercup Seed-Gen Standalone

**Project:** Extract seed-gen as standalone service from OSS-CRS
**Created:** 2026-03-10
**Granularity:** Coarse (3-5 phases, 1-3 plans each)

## Milestones

- [x] **v1.0 MVP** - Phases 1-3 (shipped 2026-03-11)
- [ ] **v1.1 Java Support** - Phases 4-5 (in progress)

## Phases

<details>
<summary>v1.0 MVP (Phases 1-3) - SHIPPED 2026-03-11</summary>

- [x] **Phase 1: Service & Configuration Removal** - Remove fuzzer-bot service and update deployment configurations (completed 2026-03-10)
- [x] **Phase 2: Code Cleanup** - Remove fuzzer-specific code paths from retained services (completed 2026-03-10)
- [x] **Phase 3: Validation & Documentation** - Verify standalone deployment and document architecture (completed 2026-03-11)

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

</details>

### v1.1 Java Support (In Progress)

**Milestone Goal:** Add full Java/Jazzer support to seed-gen standalone with JaCoCo coverage integration.

- [ ] **Phase 4: Java Coverage Infrastructure** - JaCoCo execution in helper.py and Docker image setup
- [ ] **Phase 5: Integration & Validation** - End-to-end Java coverage verification

## Phase Details

### Phase 4: Java Coverage Infrastructure
**Goal**: Java targets can execute with JaCoCo coverage collection

**Depends on**: Phase 3 (v1.0 complete)

**Requirements**: CFG-01, CFG-02, COV-01, COV-02, COV-03, COV-04

**Success Criteria** (what must be TRUE):
  1. crs.yaml lists `java` and `jvm` in supported_target.language
  2. helper.py detects Java language from project.yaml and dispatches to Java coverage branch
  3. Jazzer target runs with JaCoCo agent attached via `--additional_jvm_args`
  4. JaCoCo CLI generates XML report from .exec file
  5. XML report appears at `<build_dir>/dumps/<harness>.xml`

**Plans**: TBD

Plans:
- [ ] 04-01: TBD

### Phase 5: Integration & Validation
**Goal**: Java coverage flows end-to-end from execution to CoverageMap

**Depends on**: Phase 4 (Java coverage infrastructure must be in place)

**Requirements**: INT-01, INT-02, VAL-04, VAL-05

**Success Criteria** (what must be TRUE):
  1. CoverageRunner.run_java() successfully parses JaCoCo XML at expected path
  2. Java target coverage execution succeeds in oss-crs deployment
  3. coverage-bot populates CoverageMap for Java harness
  4. Seed-gen can use Java coverage data for seed quality feedback

**Plans**: TBD

Plans:
- [ ] 05-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Service & Configuration Removal | v1.0 | 1/1 | Complete | 2026-03-10 |
| 2. Code Cleanup | v1.0 | 2/2 | Complete | 2026-03-10 |
| 3. Validation & Documentation | v1.0 | 3/3 | Complete | 2026-03-11 |
| 4. Java Coverage Infrastructure | v1.1 | 0/? | Not started | - |
| 5. Integration & Validation | v1.1 | 0/? | Not started | - |

## Coverage Map

### v1.1 Coverage

| Requirement | Phase | Rationale |
|-------------|-------|-----------|
| CFG-01 | Phase 4 | Add java/jvm to crs.yaml supported_target.language |
| CFG-02 | Phase 4 | helper.py language detection from project.yaml |
| COV-01 | Phase 4 | JaCoCo agent runs Jazzer with additional_jvm_args |
| COV-02 | Phase 4 | JaCoCo CLI generates XML from .exec |
| COV-03 | Phase 4 | XML placed at expected path for CoverageRunner |
| COV-04 | Phase 4 | JaCoCo JARs in coverage builder image |
| INT-01 | Phase 5 | helper.py dispatches to Java vs C coverage |
| INT-02 | Phase 5 | CoverageRunner.run_java() parses generated XML |
| VAL-04 | Phase 5 | Java coverage execution succeeds in deployment |
| VAL-05 | Phase 5 | coverage-bot populates CoverageMap for Java |

**v1.1 Coverage**: 10/10 requirements mapped (100%)

### v1.0 Coverage (Complete)

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

**v1.0 Coverage**: 15/15 requirements mapped (100%)

## Notes

### Phase Grouping Rationale (v1.1)

**Phase 4 groups all JaCoCo infrastructure work** (config changes, helper.py Java branch, Docker image JARs, XML generation). All foundation work for Java coverage happens atomically before integration testing.

**Phase 5 is integration and validation** requiring Phase 4 stability. Cannot verify end-to-end Java coverage until infrastructure is in place.

### Dependencies Identified (v1.1)

- COV-01 (JaCoCo agent runs) requires COV-04 (JARs available in image)
- COV-02 (CLI generates XML) requires COV-01 (.exec file exists)
- COV-03 (XML at path) requires COV-02 (XML generated)
- INT-02 (parse XML) requires COV-03 (XML at expected path)
- VAL-04, VAL-05 require all prior infrastructure

### Key Technical Notes

- **OSS-Fuzz pattern**: Imitate `run_java_fuzz_target` from OSS-Fuzz for JaCoCo integration
- **JaCoCo flow**: agent produces .exec -> CLI produces XML -> CoverageRunner parses XML
- **Existing code**: CoverageRunner.run_java() already expects XML at `<build_dir>/dumps/<harness>.xml`

---
*Last updated: 2026-03-12*

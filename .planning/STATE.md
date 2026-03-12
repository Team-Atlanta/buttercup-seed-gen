---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: java-support
current_phase: 0
status: defining
last_updated: "2026-03-12T00:00:00.000Z"
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
---

# Project State: Buttercup Seed-Gen Standalone

**Last Updated:** 2026-03-12
**Current Phase:** —
**Status:** Defining requirements

## Project Reference

**Core Value**: Generate quality seeds and submit them to competition API without fuzzing overhead

**Current Focus**: Add Java/Jazzer support with JaCoCo coverage integration

**Key Constraint**: Imitate OSS-Fuzz helper.py patterns for Java coverage execution

## Current Position

**Phase**: Not started (defining requirements)
**Plan**: —
**Task**: —
**Status**: Defining requirements

**Progress**: `[░░░░░░░░░░] 0/0 phases (—)`

## Performance Metrics

**v1.0 Final**:
- Plans completed: 6
- Tasks completed: 17
- Phases completed: 3/3
- Requirements: 15/15 mapped (100%)

**v1.1 Current**:
- Phases planned: 0
- Requirements defined: Pending

## Accumulated Context

### Recent Decisions

**2026-03-12**: Started v1.1 Java Support milestone
- Java support already exists in codebase: find_jazzer_harnesses(), Language.JAVA, CodeQuery JAVA_EXTENSIONS
- CoverageRunner.run_java() parses JaCoCo XML — already implemented
- Gap is in oss-crs deployment: crs.yaml only declares C/C++, builder-coverage.sh only handles LLVM coverage
- Will imitate OSS-Fuzz helper.py run_java_fuzz_target() for JaCoCo integration

**2026-03-11**: Completed Phase 03 Plan 03 - Standalone architecture documentation
- Created 305-line oss-crs/README.md documenting 4-service architecture
- Added crs-compose deployment instructions (prepare, build-target, run)
- Documented migration notes (fuzzer-bot, vuln-discovery, POV removed)
- Verified no active fuzzer capability claims in documentation

**2026-03-11**: Completed Phase 03 Plan 01 - Unit test validation
- Verified 17/17 unit tests pass after Phase 2 cleanup
- Confirmed no dead code references to crash infrastructure or vuln-discovery
- Validated task sampling returns only SEED_INIT and SEED_EXPLORE
- Code is lint-clean with ruff

**2026-03-10**: Completed Phase 02 Plan 02 - POV infrastructure removal
- Removed crash infrastructure (crash_queue, crash_set, CrashDir) from SeedGenBot
- Deleted 1,550+ lines of vuln-discovery code across 6 files
- Removed crash-related parameters from __init__ (max_pov_size, crash_dir_count_limit)
- Fixed CLI and test fixtures to match new architecture
- Requirements CODE-03, CODE-04, CLN-02 satisfied

**2026-03-10**: Completed Phase 02 Plan 01 - Vuln-discovery task removal
- Removed VULN_DISCOVERY from TaskName enum
- Removed vuln-discovery from task sampling logic
- Renormalized probabilities: SEED_EXPLORE now 0.95 (was 0.60/0.50)
- Used TDD approach for task sampling changes
- Requirement CODE-01 satisfied

**2026-03-10**: Completed Phase 01 Plan 01 - Fuzzer-bot removal
- Removed fuzzer-bot service from crs.yaml (5 → 4 services)
- Removed fuzzer case from entrypoint script
- Removed fuzzer-builder Docker stage (~200MB saved)
- All 7 Phase 01 requirements satisfied

**2026-03-10**: Roadmap created with 3 phases
- Phase 1: Service & Configuration Removal (7 requirements)
- Phase 2: Code Cleanup (4 requirements)
- Phase 3: Validation & Documentation (4 requirements)

**2026-03-10**: POV generation confirmed out of scope
- Per PROJECT.md, focus is seed-only
- Remove vuln-discovery tasks in Phase 2
- Remove POV submission paths in Phase 2

**2026-03-10**: Granularity set to coarse
- Target 3-5 phases total
- Each phase should have 1-3 plans
- Compress related work into coherent deliverables

### Active TODOs

**Phase 02 - Code Cleanup**: Complete (2/2 plans)
- ✓ Remove vuln-discovery task type from sampling (02-01 complete)
- ✓ Remove POV submission infrastructure (02-02 complete)
- ✓ Clean up orphaned Redis queue consumers (02-02 complete)

**Phase 03 - Validation & Documentation**: Complete (3/3 plans)
- ✓ Unit test validation (03-01 complete)
- ✓ Integration strategy documented (03-02 complete)
- ✓ Standalone architecture documentation (03-03 complete)

### Known Blockers

None identified

### Research Flags

**No research-phase needed** per SUMMARY.md:
- All technologies are existing and observed in codebase
- Work is refactoring existing code, not building new capabilities
- All patterns are well-understood microservices extraction

### Risks

**Coverage-bot corpus dependency** (Medium):
- Coverage metrics may drop when fuzzer-bot stops contributing to corpus
- Mitigation: Document expected baseline shift in Phase 3
- Status: Deferred to Phase 3 validation

**Orphaned queue consumers** (Low):
- Seedgen initializes crash_queue/crash_set that fuzzer-bot would populate
- Mitigation: Remove in Phase 2 code cleanup
- Status: ✅ Resolved in Phase 2 Plan 02

## Session Continuity

### For Next Session

**v1.1 Java Support milestone started — defining requirements**

**Context gathered:**
- Harness is provided via OSS_CRS_TARGET_HARNESS (not discovered)
- OSS-Fuzz helper.py has run_java_fuzz_target() that uses JaCoCo agent + CLI
- JaCoCo produces .exec files → converted to XML → parsed by CoverageRunner.run_java()
- builder-coverage.sh helper.py needs Java coverage branch

**Key references:**
- ~/post/oss-fuzz/infra/base-images/base-runner/coverage (lines 189-229 for Java)
- ~/post/oss-fuzz/infra/base-images/base-runner/jacoco_report_converter.py

**If context is lost**:
- Read: `.planning/PROJECT.md` for milestone goals
- Read: `.planning/REQUIREMENTS.md` for requirements (once created)
- Read: `java-support.md` at repo root for existing Java support documentation

### Key Files

- `.planning/PROJECT.md` - Core value and milestone goals
- `.planning/REQUIREMENTS.md` - Requirements with traceability (to be created)
- `.planning/ROADMAP.md` - Phase structure (v1.0 complete, v1.1 pending)
- `oss-crs/bin/builder-coverage.sh` - Main file to modify for Java coverage
- `fuzzer/src/buttercup/fuzzing_infra/coverage_runner.py` - CoverageRunner.run_java() already exists

### Command Shortcuts

```bash
# View project goals
cat .planning/PROJECT.md

# View current state
cat .planning/STATE.md

# After requirements defined
/gsd:plan-phase 4
```

---
*State initialized: 2026-03-10*
*Milestone v1.1 started: 2026-03-12*

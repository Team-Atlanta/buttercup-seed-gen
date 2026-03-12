---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: java-support
current_phase: 4
status: ready_to_plan
last_updated: "2026-03-12T00:00:00.000Z"
progress:
  total_phases: 5
  completed_phases: 3
  total_plans: 6
  completed_plans: 6
---

# Project State: Buttercup Seed-Gen Standalone

**Last Updated:** 2026-03-12
**Current Phase:** Phase 4 - Java Coverage Infrastructure
**Status:** Ready to plan

## Project Reference

**Core Value**: Generate quality seeds and submit them to competition API without fuzzing overhead

**Current Focus**: Add Java/Jazzer support with JaCoCo coverage integration

**Key Constraint**: Imitate OSS-Fuzz helper.py patterns for Java coverage execution

## Current Position

**Phase**: 4 of 5 (Java Coverage Infrastructure)
**Plan**: 0 of ? (not yet planned)
**Status**: Ready to plan

**Progress**: `[======....] 60% (3/5 phases complete)`

## Performance Metrics

**v1.0 Final**:
- Plans completed: 6
- Tasks completed: 17
- Phases completed: 3/3
- Requirements: 15/15 mapped (100%)

**v1.1 Current**:
- Phases planned: 2 (Phase 4, Phase 5)
- Requirements defined: 10
- Requirements mapped: 10/10 (100%)

## Accumulated Context

### Recent Decisions

**2026-03-12**: v1.1 Roadmap created with 2 phases
- Phase 4: Java Coverage Infrastructure (6 requirements: CFG-01, CFG-02, COV-01, COV-02, COV-03, COV-04)
- Phase 5: Integration & Validation (4 requirements: INT-01, INT-02, VAL-04, VAL-05)
- Imitate OSS-Fuzz run_java_fuzz_target() for JaCoCo integration pattern
- CoverageRunner.run_java() already exists and expects XML at `<build_dir>/dumps/<harness>.xml`

**2026-03-12**: Started v1.1 Java Support milestone
- Java support already exists in codebase: find_jazzer_harnesses(), Language.JAVA, CodeQuery JAVA_EXTENSIONS
- CoverageRunner.run_java() parses JaCoCo XML — already implemented
- Gap is in oss-crs deployment: crs.yaml only declares C/C++, builder-coverage.sh only handles LLVM coverage
- Will imitate OSS-Fuzz helper.py run_java_fuzz_target() for JaCoCo integration

**2026-03-11**: Completed v1.0 Phase 3
- All 6 plans complete
- README documentation with 4-service architecture
- Unit tests passing (17/17)

### Active TODOs

**Phase 04 - Java Coverage Infrastructure**: Not started
- [ ] Add java/jvm to crs.yaml supported_target.language (CFG-01)
- [ ] Add language detection to helper.py (CFG-02)
- [ ] JaCoCo agent runs Jazzer with additional_jvm_args (COV-01)
- [ ] JaCoCo CLI generates XML from .exec (COV-02)
- [ ] XML placed at expected path (COV-03)
- [ ] JaCoCo JARs in Docker image (COV-04)

**Phase 05 - Integration & Validation**: Blocked on Phase 4
- [ ] helper.py dispatches Java vs C coverage (INT-01)
- [ ] CoverageRunner.run_java() parses XML (INT-02)
- [ ] Java coverage succeeds in deployment (VAL-04)
- [ ] coverage-bot populates CoverageMap (VAL-05)

### Known Blockers

None identified

### Key Files

- `.planning/PROJECT.md` - Core value and milestone goals
- `.planning/REQUIREMENTS.md` - Requirements with traceability
- `.planning/ROADMAP.md` - Phase structure (v1.0 complete, v1.1 phases 4-5)
- `oss-crs/bin/builder-coverage.sh` - Main file to modify for Java coverage
- `fuzzer/src/buttercup/fuzzing_infra/coverage_runner.py` - CoverageRunner.run_java() already exists

## Session Continuity

### For Next Session

**v1.1 Java Support milestone — roadmap complete, ready for Phase 4 planning**

**Key references:**
- ~/post/oss-fuzz/infra/base-images/base-runner/coverage (lines 189-229 for Java)
- ~/post/oss-fuzz/infra/base-images/base-runner/jacoco_report_converter.py

**If context is lost**:
- Read: `.planning/PROJECT.md` for milestone goals
- Read: `.planning/REQUIREMENTS.md` for requirements
- Read: `.planning/ROADMAP.md` for phase structure

**Next command**: `/gsd:plan-phase 4`

---
*State initialized: 2026-03-10*
*Milestone v1.1 roadmap: 2026-03-12*

---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: Java Support
current_phase: 5
status: planning
last_updated: "2026-03-13T15:43:09.232Z"
progress:
  total_phases: 5
  completed_phases: 4
  total_plans: 10
  completed_plans: 9
---

# Project State: Buttercup Seed-Gen Standalone

**Last Updated:** 2026-03-13
**Current Phase:** 5
**Status:** In progress

## Project Reference

**Core Value**: Generate quality seeds and submit them to competition API without fuzzing overhead

**Current Focus**: Add Java/Jazzer support with JaCoCo coverage integration

**Key Constraint**: Imitate OSS-Fuzz helper.py patterns for Java coverage execution

## Current Position

**Phase**: 5 of 5 (Integration & Validation)
**Plan**: 1 of 2 complete
**Status**: In progress

**Progress**: `[█████████░] 90% (9/10 plans complete)`

## Performance Metrics

**v1.0 Final**:
- Plans completed: 6
- Tasks completed: 17
- Phases completed: 3/3
- Requirements: 15/15 mapped (100%)

**v1.1 Current**:
- Phases planned: 2 (Phase 4, Phase 5)
- Plans completed: 3 (04-01, 04-02, 05-01)
- Tasks completed: 8
- Requirements defined: 10
- Requirements mapped: 10/10 (100%)
- Requirements completed: 9/10 (90%)

## Accumulated Context

### Recent Decisions

**2026-03-13**: Completed 05-01 (Logging Infrastructure for Coverage Validation)
- Use Python logging module with [COVERAGE] prefix for clear log identification
- Add boundary markers (Start/Complete) for both Java and C/C++ coverage paths
- Include actionable context in error logs (file paths, exit codes, stderr snippets)
- Log progress every 100 files for long-running corpus processing

**2026-03-12**: Completed 04-01 (Java Language Configuration)
- Added java and jvm to crs.yaml supported_target.language
- Installed JaCoCo 0.8.11 JARs in coverage builder image at /opt/
- Use JaCoCo 0.8.11 for Java coverage instrumentation
- Install JaCoCo JARs to /opt/ directory for system-wide availability

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

**Phase 04 - Java Coverage Infrastructure**: 2 of 2 plans complete ✅
- [x] Add java/jvm to crs.yaml supported_target.language (CFG-01) — 04-01
- [x] JaCoCo JARs in Docker image (COV-04) — 04-01
- [x] Add language detection to helper.py (CFG-02) — 04-02
- [x] JaCoCo agent runs Jazzer with additional_jvm_args (COV-01) — 04-02
- [x] JaCoCo CLI generates XML from .exec (COV-02) — 04-02
- [x] XML placed at expected path (COV-03) — 04-02

**Phase 05 - Integration & Validation**: 1 of 2 plans complete
- [x] helper.py dispatches Java vs C coverage (INT-01) — 05-01
- [x] CoverageRunner.run_java() parses XML (INT-02) — 05-01
- [ ] Java coverage succeeds in deployment (VAL-04) — 05-02
- [x] coverage-bot populates CoverageMap (VAL-05) — 05-01 (via logging validation)

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

**v1.1 Java Support milestone — Phase 4 complete, Phase 5 in progress (1/2 plans complete)**

**Last session**: Completed 05-01 (Logging Infrastructure for Coverage Validation)
- Added comprehensive logging to helper.py for both Java and C/C++ coverage paths
- 47 logging statements with [COVERAGE] prefix
- Boundary markers, actionable error context, progress logging

**Next step**: 05-02 (Manual End-to-End Java Coverage Validation)
- Validate Java coverage flow with real project
- Verify XML generation and CoverageRunner parsing
- Document any integration issues

**If context is lost**:
- Read: `.planning/PROJECT.md` for milestone goals
- Read: `.planning/REQUIREMENTS.md` for requirements
- Read: `.planning/ROADMAP.md` for phase structure
- Read: `.planning/phases/05-integration-validation/05-01-SUMMARY.md` for logging context

**Next command**: `/gsd:execute-plan 05-02`

---
*State initialized: 2026-03-10*
*Milestone v1.1 roadmap: 2026-03-12*

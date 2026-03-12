---
phase: 04-java-coverage-infrastructure
plan: 02
subsystem: fuzzing-infrastructure
tags: [java, coverage, jacoco, oss-fuzz]
dependency_graph:
  requires: [oss-fuzz-structure, helper-py-framework]
  provides: [java-coverage-execution, jacoco-integration]
  affects: [coverage-bot, coverage-runner]
tech_stack:
  added: [jacoco-agent, jacoco-cli, yaml-parsing]
  patterns: [language-dispatch, oss-fuzz-imitation]
key_files:
  created: []
  modified:
    - oss-crs/bin/builder-coverage.sh
decisions:
  - "Imitate OSS-Fuzz run_java_fuzz_target() pattern for JaCoCo integration"
  - "Use language detection from project.yaml to dispatch coverage execution"
  - "Support both 'java' and 'jvm' language identifiers"
  - "Place XML reports at <build_dir>/dumps/<harness>.xml (CoverageRunner expected path)"
metrics:
  duration_seconds: 93
  tasks_completed: 3
  files_modified: 1
  commits: 3
  completed_date: "2026-03-12"
---

# Phase 04 Plan 02: Java Coverage Helper Summary

**One-liner:** Added JaCoCo-based Java coverage collection to helper.py with language detection and OSS-Fuzz pattern imitation

## What Was Built

Extended the embedded helper.py in `builder-coverage.sh` to support Java coverage collection using JaCoCo agent and CLI, following the OSS-Fuzz `run_java_fuzz_target()` pattern.

**Key capabilities added:**
1. Language detection from project.yaml files
2. Java coverage execution with JaCoCo agent integration
3. XML report generation using JaCoCo CLI
4. Language-based dispatch (Java vs C/C++ coverage)

## Implementation Details

### Task 1: Language Detection
- Added `get_project_language()` function to parse project.yaml
- Imports yaml module (available in OSS-Fuzz images)
- Defaults to 'c' if project.yaml missing or language not specified
- Returns lowercase language string for consistent comparison

### Task 2: Java Coverage Function
- Added `run_java_coverage()` with JaCoCo integration
- Configures JaCoCo agent with:
  - `destfile=<harness>.exec` for execution data
  - `classdumpdir=dumps/classes` for class files
  - `excludes=com.code_intelligence.jazzer.*` to exclude Jazzer internals
- Runs Jazzer with `--additional_jvm_args=-javaagent:/opt/jacoco-agent.jar`
- Uses `-merge=1` to process all corpus files in one run
- Generates XML report via JaCoCo CLI: `java -jar /opt/jacoco-cli.jar report`
- Places XML at `<build_dir>/dumps/<harness>.xml` (CoverageRunner expected path)

### Task 3: Language Dispatch
- Modified `run_coverage()` to detect language first
- Dispatches to `run_java_coverage()` for `java` or `jvm` projects
- Preserves existing C/C++ LLVM coverage logic for all other languages
- No changes to existing LLVM coverage workflow

## Architecture Decisions

**Language Detection Strategy**
- Decision: Read language from project.yaml (same as OSS-Fuzz)
- Rationale: Consistent with OSS-Fuzz project structure, no new metadata needed
- Alternative considered: Environment variable (rejected - not available in coverage-bot context)

**JaCoCo Integration Pattern**
- Decision: Imitate OSS-Fuzz run_java_fuzz_target() exactly
- Rationale: Proven pattern, matches existing CoverageRunner.run_java() expectations
- Key insight: Use `--additional_jvm_args` to attach JaCoCo agent to Jazzer JVM

**XML Report Path**
- Decision: Place XML at `<build_dir>/dumps/<harness>.xml`
- Rationale: CoverageRunner.run_java() already parses from this exact path
- No changes needed to CoverageRunner

## Deviations from Plan

None - plan executed exactly as written.

## Testing Strategy

**Unit Testing:** Not applicable (shell script with embedded Python)

**Integration Testing:** Will be validated in Phase 5 (Integration & Validation)
- Test with Java project in deployment
- Verify XML generation
- Confirm CoverageRunner can parse output

**Manual Verification:**
```bash
# Verify all functions present
grep "get_project_language" oss-crs/bin/builder-coverage.sh
grep "run_java_coverage" oss-crs/bin/builder-coverage.sh
grep "jacoco-agent.jar" oss-crs/bin/builder-coverage.sh
grep "jacoco-cli.jar" oss-crs/bin/builder-coverage.sh
```

## Requirements Satisfied

- **CFG-02:** Language detection from project.yaml ✓
- **COV-01:** JaCoCo agent runs Jazzer with additional_jvm_args ✓
- **COV-02:** JaCoCo CLI generates XML from .exec file ✓
- **COV-03:** XML placed at expected path (<build_dir>/dumps/<harness>.xml) ✓

## Known Issues

None identified.

## Next Steps

Continue to Phase 4 Plan 3+ (if any) or Phase 5:
- Update crs.yaml to declare java/jvm support (CFG-01)
- Add JaCoCo JARs to Docker image (COV-04)
- Validate end-to-end Java coverage workflow (INT-01, INT-02, VAL-04, VAL-05)

## Commits

1. `344bf62` - feat(04-02): add language detection to helper.py
2. `42c8e0c` - feat(04-02): add Java coverage function with JaCoCo integration
3. `bedd77c` - feat(04-02): dispatch coverage execution based on language

## Self-Check: PASSED

**Files verified:**
```bash
[ -f "oss-crs/bin/builder-coverage.sh" ] && echo "FOUND: oss-crs/bin/builder-coverage.sh"
```
FOUND: oss-crs/bin/builder-coverage.sh

**Commits verified:**
```bash
git log --oneline --all | grep -q "344bf62" && echo "FOUND: 344bf62"
git log --oneline --all | grep -q "42c8e0c" && echo "FOUND: 42c8e0c"
git log --oneline --all | grep -q "bedd77c" && echo "FOUND: bedd77c"
```
FOUND: 344bf62
FOUND: 42c8e0c
FOUND: bedd77c

All files and commits verified successfully.

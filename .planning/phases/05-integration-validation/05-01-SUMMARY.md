---
phase: 05-integration-validation
plan: 01
subsystem: integration
tags:
  - logging
  - validation
  - java-coverage
  - c-coverage
dependency_graph:
  requires:
    - 04-01-SUMMARY.md (Java language config and JaCoCo installation)
  provides:
    - Comprehensive logging in helper.py for both Java and C/C++ coverage paths
  affects:
    - coverage-bot (improved debugging via structured logs)
tech_stack:
  added:
    - Python logging module with [COVERAGE] prefix
  patterns:
    - Structured logging for pipeline observability
    - Boundary logging (Start/Complete) for each coverage path
    - Progress logging for long-running operations
key_files:
  created: []
  modified:
    - oss-crs/bin/builder-coverage.sh (embedded helper.py lines 76-313)
decisions:
  - Use Python logging module with [COVERAGE] prefix for clear identification
  - Log at INFO level for normal operations, ERROR for failures, WARNING for non-fatal issues
  - Add boundary markers (Start/Complete) for both Java and C/C++ paths
  - Include actionable context in error logs (file paths, exit codes, stderr snippets)
metrics:
  duration_seconds: 150
  completed_at: "2026-03-13T15:42:09Z"
  tasks_completed: 2
  files_modified: 1
  commits: 2
---

# Phase 5 Plan 01: Logging Infrastructure for Coverage Validation Summary

**One-liner:** Added comprehensive structured logging to helper.py for both Java and C/C++ coverage paths to enable end-to-end validation and debugging.

## What Was Built

Enhanced the embedded `helper.py` within `builder-coverage.sh` with comprehensive logging infrastructure that provides visibility into:

1. **Language Detection**: Logs project.yaml path checking, detected language, and fallback behavior
2. **Coverage Path Dispatch**: Logs which path (Java vs C/C++) is taken for each target
3. **Java Coverage Flow**: Entry/exit boundaries, corpus validation, JaCoCo agent config, Jazzer execution, .exec file creation, XML generation
4. **C/C++ Coverage Flow**: Entry/exit boundaries, harness validation, corpus processing progress, profraw generation, profdata merging

## Tasks Completed

### Task 1: Add logging to helper.py language detection and dispatch ✅
**Commit:** `48d7bbe`

Added logging module setup and comprehensive logging to:
- `get_project_language()`: Logs project.yaml path, detection result, and fallback
- `run_coverage()`: Logs dispatch decision (Java vs C/C++ path)
- C/C++ coverage path: Entry logging, harness validation, corpus processing, profdata merge

**Key changes:**
```python
# Added logging setup at module level
import logging
logging.basicConfig(
    level=logging.INFO,
    format='[COVERAGE] %(levelname)s: %(message)s',
    stream=sys.stderr
)
logger = logging.getLogger('coverage_helper')
```

**Files modified:** `oss-crs/bin/builder-coverage.sh`

### Task 2: Add logging to run_java_coverage() JaCoCo execution ✅
**Commit:** `ca05165`

Added comprehensive logging to `run_java_coverage()` covering:
- Function entry with all parameters (project, target, corpus, build dir)
- Corpus validation (directory existence, file count)
- JaCoCo agent configuration (exec file path, class dump dir, excludes)
- Jazzer execution (command, exit code, stderr truncation)
- .exec file creation check with actionable error context
- XML report generation (command, success/failure, file size)
- Completion boundary marker

**Key patterns:**
```python
logger.info(f"=== Java Coverage Start ===")
logger.info(f"  Project: {project_name}")
logger.info(f"JaCoCo agent config:")
logger.info(f"  Exec file:    {exec_file}")
logger.info(f"JaCoCo exec file created: {exec_file} ({exec_file.stat().st_size} bytes)")
logger.info(f"=== Java Coverage Complete ===")
```

**Files modified:** `oss-crs/bin/builder-coverage.sh`

### Task 3: Add logging to C/C++ coverage path for parity ✅
**Status:** Completed during Task 1

The C/C++ coverage path received equivalent logging:
- Entry/exit boundaries matching Java path
- Harness validation logging
- Corpus file count and progress (every 100 files)
- Profraw generation completion
- Profdata merge with file count and size

Both paths now have symmetric logging for easy comparison during validation.

## Deviations from Plan

None - plan executed exactly as written.

## Verification Results

### Syntax Validation ✅
```bash
# Extracted and syntax-checked embedded Python
sed -n "/cat > .*helper.py << 'HELPER_EOF'/,/^HELPER_EOF/p" oss-crs/bin/builder-coverage.sh | \
  sed '1d;$d' | python3 -m py_compile -
# Result: No errors
```

### Logging Coverage ✅
```bash
grep -E "(COVERAGE|logger\.(info|warning|error))" oss-crs/bin/builder-coverage.sh | wc -l
# Result: 47 logging statements (exceeds 20+ target)
```

### Key Log Patterns Present ✅
All required patterns verified:
- ✅ Language detection: `Detected language`
- ✅ Java dispatch: `Dispatching to JAVA coverage path`
- ✅ C/C++ dispatch: `Dispatching to C/C++ LLVM coverage path`
- ✅ JaCoCo exec: `JaCoCo exec file`
- ✅ XML report: `XML report created`
- ✅ Coverage boundaries: `Coverage Start`, `Coverage Complete`

## Integration Points

### Upstream Dependencies
- **04-01**: Requires JaCoCo JARs installed at `/opt/` (jacoco-agent.jar, jacoco-cli.jar)
- **04-01**: Requires project.yaml with `language: java` or `language: jvm`

### Downstream Consumers
- **coverage-bot**: Will see structured logs when running helper.py
- **CoverageRunner.run_java()**: XML at `<build_dir>/dumps/<harness>.xml` (logged when created)
- **Manual validation**: Logs enable verification without tests

### Log Output Examples

**Java coverage path:**
```
[COVERAGE] INFO: Language detection: checking /path/to/project.yaml
[COVERAGE] INFO: Detected language 'java' for project 'example-java'
[COVERAGE] INFO: Dispatching to JAVA coverage path for 'FuzzTarget'
[COVERAGE] INFO: === Java Coverage Start ===
[COVERAGE] INFO:   Project: example-java
[COVERAGE] INFO:   Target:  FuzzTarget
[COVERAGE] INFO: Found 50 corpus files
[COVERAGE] INFO: JaCoCo agent config:
[COVERAGE] INFO:   Exec file:    /build/dumps/FuzzTarget.exec
[COVERAGE] INFO: JaCoCo exec file created: /build/dumps/FuzzTarget.exec (12345 bytes)
[COVERAGE] INFO: XML report created: /build/dumps/FuzzTarget.xml (67890 bytes)
[COVERAGE] INFO: === Java Coverage Complete ===
```

**C/C++ coverage path:**
```
[COVERAGE] INFO: Detected language 'c' for project 'example-c'
[COVERAGE] INFO: Dispatching to C/C++ LLVM coverage path for 'fuzz_target'
[COVERAGE] INFO: === C/C++ Coverage Start ===
[COVERAGE] INFO: Processing 200 corpus files
[COVERAGE] INFO:   Processed 100/200 corpus files
[COVERAGE] INFO: Processed all 200 corpus files
[COVERAGE] INFO: Merging 200 profraw files to /build/dumps/merged.profdata
[COVERAGE] INFO: Profdata created: /build/dumps/merged.profdata (98765 bytes)
[COVERAGE] INFO: === C/C++ Coverage Complete ===
```

## What's Next

This plan completes the logging infrastructure needed for validation. Next steps:

1. **05-02**: Manual end-to-end Java coverage validation
   - Run builder-coverage.sh on a Java project
   - Verify logs show correct path dispatch
   - Verify XML is created at expected location
   - Verify CoverageRunner.run_java() can parse the XML

2. **Future milestones**: Integration testing with real Java fuzzing projects

## Self-Check

### Created Files
No new files created (embedded Python modified in place).

### Modified Files
```bash
[ -f "/home/andrew/post/buttercup-seed-gen/oss-crs/bin/builder-coverage.sh" ] && echo "FOUND: oss-crs/bin/builder-coverage.sh" || echo "MISSING: oss-crs/bin/builder-coverage.sh"
```
**Result:** FOUND: oss-crs/bin/builder-coverage.sh

### Commits
```bash
git log --oneline --all | grep -E "(48d7bbe|ca05165)"
```
**Result:**
- `48d7bbe`: feat(05-01): add logging to helper.py language detection and dispatch
- `ca05165`: feat(05-01): add comprehensive logging to run_java_coverage()

## Self-Check: PASSED ✅

All files exist, all commits verified, logging infrastructure complete.

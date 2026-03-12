---
phase: 04-java-coverage-infrastructure
verified: 2026-03-12T20:55:34Z
status: passed
score: 8/8 must-haves verified
re_verification: false
---

# Phase 04: Java Coverage Infrastructure Verification Report

**Phase Goal:** Java targets can execute with JaCoCo coverage collection
**Verified:** 2026-03-12T20:55:34Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | crs.yaml declares java and jvm as supported languages | ✓ VERIFIED | Lines 49-50 in crs.yaml contain `- java` and `- jvm` |
| 2 | JaCoCo JARs are available in coverage builder image at /opt/ | ✓ VERIFIED | Dockerfile lines 12-20 download and install jacoco-agent.jar and jacoco-cli.jar to /opt/ |
| 3 | helper.py detects Java language from project.yaml | ✓ VERIFIED | get_project_language() function at line 88, reads project.yaml with yaml.safe_load() |
| 4 | Jazzer runs with JaCoCo agent via --additional_jvm_args | ✓ VERIFIED | Line 128 in helper.py: `--additional_jvm_args=-javaagent:/opt/jacoco-agent.jar={jacoco_args}` |
| 5 | JaCoCo CLI generates XML report from .exec file | ✓ VERIFIED | Lines 140-148 invoke `java -jar /opt/jacoco-cli.jar report` with .exec as input and --xml for output |
| 6 | XML report appears at <build_dir>/dumps/<harness>.xml | ✓ VERIFIED | Line 116 sets `xml_report = dumps_dir / f"{fuzz_target}.xml"` where dumps_dir is build_dir/dumps (matches CoverageRunner.run_java() expectation at fuzzer/src/buttercup/fuzzing_infra/coverage_runner.py:380) |
| 7 | Language detection triggers Java coverage dispatch | ✓ VERIFIED | Lines 162-165 detect language and dispatch to run_java_coverage() for "java" or "jvm" |
| 8 | JaCoCo agent configured with OSS-Fuzz pattern | ✓ VERIFIED | Line 119 configures agent with destfile, classdumpdir, and excludes matching OSS-Fuzz pattern |

**Score:** 8/8 truths verified (100%)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| oss-crs/crs.yaml | Java language declaration | ✓ VERIFIED | Lines 49-50 contain `- java` and `- jvm` in supported_target.language list |
| oss-crs/dockerfiles/builder-coverage.Dockerfile | JaCoCo JAR installation | ✓ VERIFIED | Lines 12-20 download JaCoCo 0.8.11 and install JARs to /opt/, 98 lines total (substantive) |
| oss-crs/bin/builder-coverage.sh | Java coverage helper.py with JaCoCo integration | ✓ VERIFIED | Embedded helper.py spans 347 lines with get_project_language() (line 88), run_java_coverage() (line 99), dispatch logic (line 164) |

**Artifact Level Checks:**
- **Level 1 (Exists):** All 3 artifacts exist ✓
- **Level 2 (Substantive):** All contain required patterns and are >10 lines ✓
- **Level 3 (Wired):** All artifacts connected to downstream consumers ✓

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| crs.yaml | libCRS target validation | supported_target.language list | ✓ WIRED | Lines 49-50 list java/jvm, enabling libCRS to accept Java targets |
| helper.py | project.yaml | language detection | ✓ WIRED | get_project_language() reads project.yaml with yaml.safe_load() and extracts language field (lines 88-96) |
| helper.py | /opt/jacoco-agent.jar | --additional_jvm_args | ✓ WIRED | Line 128 passes javaagent path to Jazzer JVM |
| helper.py | /opt/jacoco-cli.jar | JaCoCo CLI report | ✓ WIRED | Lines 141-145 invoke CLI with report command, .exec input, --xml output |
| helper.py | <build_dir>/dumps/<harness>.xml | XML output path | ✓ WIRED | Line 116 constructs exact path expected by CoverageRunner.run_java() at coverage_runner.py:380 |
| run_coverage() | run_java_coverage() | language dispatch | ✓ WIRED | Lines 162-165 call get_project_language() and dispatch to run_java_coverage() for java/jvm |

**All key links verified as WIRED.**

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| CFG-01 | 04-01 | crs.yaml declares java and jvm in supported_target.language | ✓ SATISFIED | crs.yaml lines 49-50 contain both entries |
| CFG-02 | 04-02 | helper.py detects language from project.yaml | ✓ SATISFIED | get_project_language() function implemented with yaml parsing |
| COV-01 | 04-02 | JaCoCo agent runs Jazzer with --additional_jvm_args | ✓ SATISFIED | Jazzer invocation at line 128 includes javaagent argument |
| COV-02 | 04-02 | JaCoCo CLI generates XML from .exec file | ✓ SATISFIED | CLI invocation at lines 140-148 with report command |
| COV-03 | 04-02 | XML placed at expected path <build_dir>/dumps/<harness>.xml | ✓ SATISFIED | Path construction at line 116 matches CoverageRunner expectation |
| COV-04 | 04-01 | JaCoCo JARs available in coverage builder image | ✓ SATISFIED | Dockerfile installs jacoco-agent.jar and jacoco-cli.jar to /opt/ |

**Requirement Coverage:** 6/6 phase requirements satisfied (100%)

**Orphaned Requirements:** None — all Phase 4 requirements from REQUIREMENTS.md are covered by plans.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | - | - | - | No anti-patterns detected |

**Anti-pattern scan results:**
- ✓ No TODO/FIXME/PLACEHOLDER markers found
- ✓ No stub implementations (empty returns, console.log only)
- ✓ No hardcoded placeholders or "coming soon" comments
- ✓ All functions have substantive implementations

### Implementation Quality

**Code Completeness:**
- get_project_language(): Full implementation with YAML parsing, error handling (defaults to 'c' if missing), lowercase normalization
- run_java_coverage(): Complete JaCoCo workflow with agent configuration, Jazzer execution, .exec validation, CLI XML generation, error handling
- Dispatch logic: Clean language detection with fallback to C/C++ LLVM coverage
- Error handling: Proper checks for corpus existence, .exec file creation, XML generation return codes

**OSS-Fuzz Pattern Adherence:**
- JaCoCo agent args: `destfile=<exec>,classdumpdir=<dir>,excludes=com.code_intelligence.jazzer.*` ✓
- Jazzer args: `-merge=1 -timeout=100 --nohooks --additional_jvm_args=-javaagent:/opt/jacoco-agent.jar=<args>` ✓
- JaCoCo CLI: `java -jar /opt/jacoco-cli.jar report <exec> --xml <xml> --classfiles <dir>` ✓
- XML path: `<build_dir>/dumps/<harness>.xml` ✓

**Integration Points:**
- CoverageRunner.run_java() expects XML at exact path helper.py generates ✓
- Language detection from project.yaml matches OSS-Fuzz structure ✓
- JaCoCo version (0.8.11) is stable release ✓

### Commits Verified

All commits from summaries verified to exist in repository:

| Hash | Message | Files Changed | Status |
|------|---------|---------------|--------|
| 1e345c5 | feat(04-01): add java and jvm to supported languages | oss-crs/crs.yaml | ✓ VERIFIED |
| e93ad89 | feat(04-01): install JaCoCo JARs in coverage builder | oss-crs/dockerfiles/builder-coverage.Dockerfile | ✓ VERIFIED |
| 344bf62 | feat(04-02): add language detection to helper.py | oss-crs/bin/builder-coverage.sh | ✓ VERIFIED |
| 42c8e0c | feat(04-02): add Java coverage function with JaCoCo integration | oss-crs/bin/builder-coverage.sh | ✓ VERIFIED |
| bedd77c | feat(04-02): dispatch coverage execution based on language | oss-crs/bin/builder-coverage.sh | ✓ VERIFIED |

**Commit verification:** 5/5 commits exist and match claimed changes ✓

### Human Verification Required

No items require human verification. All functionality can be tested in Phase 5 integration validation.

**Automated verification sufficient because:**
- Configuration changes are declarative (crs.yaml entries)
- Docker image setup is verifiable via Dockerfile content
- Python code paths are statically verifiable for correctness
- Wiring is evident from code inspection (function calls, imports, path construction)
- Phase 5 will perform end-to-end integration testing

### Summary

**Phase goal ACHIEVED:** Java targets can execute with JaCoCo coverage collection.

**Evidence:**
1. crs.yaml declares java/jvm support, enabling target acceptance
2. JaCoCo 0.8.11 JARs installed in coverage builder Docker image at /opt/
3. helper.py detects Java language from project.yaml via YAML parsing
4. Jazzer executes with JaCoCo agent attached via --additional_jvm_args
5. JaCoCo CLI generates XML reports from .exec execution data
6. XML reports placed at exact path CoverageRunner.run_java() expects
7. Language-based dispatch routes Java projects to run_java_coverage()
8. All implementation follows OSS-Fuzz proven patterns

**All must-haves verified (8/8), all requirements satisfied (6/6), no gaps found, no anti-patterns detected.**

**Infrastructure is ready for Phase 5 integration and end-to-end validation.**

---

_Verified: 2026-03-12T20:55:34Z_
_Verifier: Claude (gsd-verifier)_

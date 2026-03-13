# Phase 5: Integration & Validation - Research

**Researched:** 2026-03-13
**Domain:** Python integration testing, Java coverage end-to-end flow, OSS-Fuzz patterns
**Confidence:** HIGH

## Summary

Phase 5 integrates Java coverage infrastructure (Phase 4) with existing CoverageRunner and CoverageBot services to enable end-to-end Java coverage flow. The integration follows OSS-Fuzz patterns where `helper.py` detects project language from `project.yaml` and dispatches to language-specific coverage handlers (C/C++ uses LLVM profdata, Java uses JaCoCo XML).

CoverageRunner.run_java() already exists and parses JaCoCo XML from `<build_dir>/dumps/<harness>.xml`. Phase 4 created JaCoCo execution logic in helper.py. This phase connects them by ensuring helper.py's language detection (CFG-02) triggers the correct coverage path, and validates the entire pipeline from coverage execution through Redis CoverageMap population.

**Primary recommendation:** Use pytest for validation with mocked JaCoCo XML fixtures. Integration tests should verify helper.py language detection, CoverageRunner.run_java() XML parsing, and CoverageBot Redis population. End-to-end validation requires a live oss-crs deployment with a Java target.

## <phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INT-01 | helper.py dispatches to Java coverage vs C coverage based on detected language | Language detection uses `project.yaml` parsing (already implemented in Phase 4 helper.py). Dispatch logic is straightforward conditional: `if language in ("java", "jvm"): run_java_coverage()` else LLVM path |
| INT-02 | CoverageRunner.run_java() successfully parses generated JaCoCo XML | run_java() already exists (lines 372-423 in coverage_runner.py), uses BeautifulSoup to parse JaCoCo XML. Integration test should verify it reads XML from `<build_dir>/dumps/<harness>.xml` path that Phase 4 helper.py creates |
| VAL-04 | Java target coverage execution succeeds in oss-crs deployment | Requires live deployment test with Java target (e.g., CRSBench Java benchmark if available). Verify helper.py executes Jazzer with JaCoCo agent, generates XML report at expected path |
| VAL-05 | coverage-bot populates CoverageMap for Java harness | CoverageBot.run_task() calls CoverageRunner.run() which dispatches to run_java(). Verify CoverageBot._submit_function_coverage() stores Java coverage metrics in Redis CoverageMap. Test with mocked run_java() output |

</phase_requirements>

## Standard Stack

### Core Testing Framework
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| pytest | ~8.3.4 | Test framework | Already used across all Buttercup components (fuzzer/pyproject.toml line 43) |
| pytest-cov | ~6.0.0 | Coverage reporting | Standard pytest plugin for test coverage |
| BeautifulSoup4 | ~4.13.3 | XML parsing | Already used by CoverageRunner.run_java() for JaCoCo XML parsing (line 389) |
| lxml | ~5.3.1 | XML parser backend | BS4 dependency, used for JaCoCo XML parsing |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| unittest.mock | stdlib | Mocking | Mock ChallengeTask, Redis, file system for unit tests |
| hypothesis | ~6.148.7 | Property testing | Already used in test_coverage_runner.py for invariant testing |
| redis | ~5.2.1 | Redis client | Integration tests with Redis (use db=13 for test isolation per test_coverage_bot.py line 16) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| pytest | unittest | pytest already standard in project, no migration needed |
| BeautifulSoup4 | lxml.etree directly | BS4 already in use, provides simpler API for parsing |

**Installation:**
```bash
# Already installed via fuzzer dependencies
cd fuzzer && uv sync --all-extras
```

## Architecture Patterns

### Recommended Test Structure
```
fuzzer/tests/
├── test_coverage_runner.py        # Unit tests for CoverageRunner (exists, 1249 lines)
├── test_coverage_bot.py            # Unit tests for CoverageBot (exists, 415 lines)
├── test_java_integration.py        # NEW: Integration tests for Java coverage flow
├── conftest.py                     # Shared fixtures (may not exist yet)
└── data/
    └── jacoco_sample.xml           # NEW: Sample JaCoCo XML for testing
```

### Pattern 1: Language Detection in helper.py
**What:** helper.py reads `project.yaml` to detect language, dispatches to appropriate coverage function
**When to use:** Every coverage execution (already implemented in Phase 4 helper.py lines 88-96)
**Example:**
```python
# Source: Phase 4 builder-coverage.sh lines 88-96
def get_project_language(project_name: str) -> str:
    """Detect language from project.yaml, default to 'c'."""
    helper_dir = Path(__file__).parent.parent  # oss-fuzz/
    project_yaml = helper_dir / "projects" / project_name / "project.yaml"
    if project_yaml.exists():
        with open(project_yaml) as f:
            config = yaml.safe_load(f)
            return config.get("language", "c").lower()
    return "c"

# Dispatch logic (Phase 4 lines 158-165)
def run_coverage(project_name: str, fuzz_target: str, corpus_dir: str,
                 build_dir: Path, no_serve: bool = True) -> int:
    language = get_project_language(project_name)
    if language in ("java", "jvm"):
        return run_java_coverage(project_name, fuzz_target, corpus_dir, build_dir, no_serve)
    # Existing C/C++ LLVM coverage logic follows
```

### Pattern 2: CoverageRunner Language Dispatch
**What:** CoverageRunner.run() dispatches to run_java() or run_c() based on ProjectYaml.unified_language
**When to use:** CoverageBot calls runner.run() for every harness (coverage_runner.py lines 360-370)
**Example:**
```python
# Source: coverage_runner.py lines 360-370
def run(self, harness_name: str, corpus_dir: str) -> list[CoveredFunction] | None:
    lang = ProjectYaml(self.tool, self.tool.project_name).unified_language
    if lang in [Language.C, Language.CPP]:
        ret = self.run_c(harness_name, corpus_dir)
    elif lang == Language.JAVA:
        ret = self.run_java(harness_name, corpus_dir)
    else:
        logger.error(f"Unsupported language: {lang}")
        return None
    return ret
```

### Pattern 3: CoverageBot Redis Submission
**What:** CoverageBot receives list[CoveredFunction] from CoverageRunner, converts to FunctionCoverage protobuf, stores in CoverageMap
**When to use:** After successful coverage run (coverage_bot.py lines 173, 187-210)
**Example:**
```python
# Source: coverage_bot.py lines 187-210 (inferred from test usage)
def _submit_function_coverage(
    self,
    func_coverage: list[CoveredFunction],
    harness_name: str,
    package_name: str,
    task_id: str,
) -> None:
    coverage_map = CoverageMap(self.redis, harness_name, package_name, task_id)
    for func in func_coverage:
        function_coverage = FunctionCoverage()
        function_coverage.function_name = func.names
        function_coverage.total_lines = func.total_lines
        function_coverage.covered_lines = func.covered_lines
        function_coverage.function_paths.extend(func.function_paths)

        if self._should_update_function_coverage(coverage_map, function_coverage):
            coverage_map.set_function_coverage(function_coverage)
```

### Anti-Patterns to Avoid
- **Don't mock language detection in integration tests:** Test actual yaml parsing to catch file path issues
- **Don't test JaCoCo XML parsing without realistic XML:** Use actual JaCoCo output structure (see examples below)
- **Don't skip Redis isolation in tests:** Always use separate database (e.g., db=13) to avoid conflicts with production/other tests

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JaCoCo XML parsing | Custom XML parser | BeautifulSoup4 with lxml backend | Already in use (coverage_runner.py line 389), handles malformed XML gracefully, simpler API than raw lxml |
| Test fixtures for XML | Hardcoded strings in tests | Fixture files in tests/data/ | Easier to maintain, can use actual JaCoCo output, supports multiple test scenarios |
| Redis test isolation | Flushing production DB | Separate test database (db=13) | Already pattern in test_coverage_bot.py line 16, prevents test pollution |
| Mock ChallengeTask | Custom mock class | unittest.mock.MagicMock | Standard library, already used extensively in existing tests |

**Key insight:** CoverageRunner.run_java() XML parsing is already implemented and tested. Don't rewrite—verify it works with helper.py-generated XML path.

## Common Pitfalls

### Pitfall 1: XML Path Mismatch Between helper.py and CoverageRunner
**What goes wrong:** helper.py writes JaCoCo XML to one path, CoverageRunner.run_java() expects it at different path
**Why it happens:** Phase 4 helper.py uses `dumps_dir / f"{fuzz_target}.xml"` (line 116), CoverageRunner expects `build_dir / "dumps" / f"{harness_name}.xml"` (line 380)
**How to avoid:** Integration test MUST verify exact path match. helper.py uses `fuzz_target` parameter, CoverageRunner uses `harness_name`—these must be identical
**Warning signs:** CoverageRunner logs "Failed to find jacoco file for {harness} in {jacoco_path}" (line 382-384)

### Pitfall 2: Language Detection Returns Capitalized String
**What goes wrong:** `project.yaml` contains `language: Java`, helper.py returns "Java", dispatch comparison fails
**Why it happens:** YAML allows capitalized values, Python string comparison is case-sensitive
**How to avoid:** Always `.lower()` the language string (Phase 4 helper.py line 95 already does this)
**Warning signs:** Coverage falls through to C/C++ LLVM path for Java projects, generates "llvm-profdata not found" errors

### Pitfall 3: Empty Corpus Directory
**What goes wrong:** CoverageBot samples corpus, finds no files, skips coverage entirely
**Why it happens:** Corpus not yet populated by seed-gen, or sampling excludes all files
**How to avoid:** Check `corpus.local_corpus_size()` before sampling (coverage_bot.py line 156), log warning if zero
**Warning signs:** CoverageBot logs "No files to process for {harness}" (line 136-139)

### Pitfall 4: BeautifulSoup Parser Backend Mismatch
**What goes wrong:** BeautifulSoup parses XML incorrectly or fails on valid JaCoCo XML
**Why it happens:** Using 'html.parser' instead of 'xml' parser, or lxml not installed
**How to avoid:** Always specify parser: `BeautifulSoup(f, "xml")` (coverage_runner.py line 389)
**Warning signs:** Coverage counts are zero despite JaCoCo generating non-empty XML, or parse errors on self-closing tags

### Pitfall 5: Redis CoverageMap Key Collision
**What goes wrong:** Java coverage overwrites C coverage or vice versa for same harness name
**Why it happens:** CoverageMap uses harness_name + package_name + task_id as key, doesn't distinguish language
**How to avoid:** Different builds (ASan vs Coverage) have different task_ids, so collision shouldn't occur. Verify task_id differs between builds
**Warning signs:** Coverage metrics fluctuate unexpectedly, or Java coverage shows C function names

## Code Examples

Verified patterns from official sources and existing codebase:

### JaCoCo XML Structure (for test fixtures)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- Source: JaCoCo 0.8.11 official documentation -->
<report name="Jacoco Coverage Report">
  <sessioninfo id="test-session" start="1234567890" dump="1234567891"/>
  <package name="com/example">
    <class name="com/example/MyClass" sourcefilename="MyClass.java">
      <method name="myMethod" desc="()V" line="10">
        <counter type="INSTRUCTION" missed="0" covered="15"/>
        <counter type="LINE" missed="2" covered="3"/>
        <counter type="BRANCH" missed="0" covered="2"/>
      </method>
      <method name="anotherMethod" desc="(I)I" line="20">
        <counter type="INSTRUCTION" missed="5" covered="10"/>
        <counter type="LINE" missed="1" covered="2"/>
      </method>
    </class>
  </package>
</report>
```

### Integration Test Pattern for Java Coverage
```python
# Source: Adapted from test_coverage_runner.py patterns
import tempfile
from pathlib import Path
from unittest.mock import MagicMock, patch

def test_java_coverage_integration():
    """Integration test: helper.py generates XML → CoverageRunner parses it."""
    # Create mock ChallengeTask with Java project
    mock_tool = MagicMock()
    mock_tool.project_name = "test_java_project"

    with tempfile.TemporaryDirectory() as tmpdir:
        build_dir = Path(tmpdir)
        dumps_dir = build_dir / "dumps"
        dumps_dir.mkdir()

        # Simulate helper.py writing JaCoCo XML
        jacoco_xml = dumps_dir / "JavaHarness.xml"
        jacoco_xml.write_text("""<?xml version="1.0"?>
        <report>
          <package name="com/example">
            <class name="com/example/Foo" sourcefilename="Foo.java">
              <method name="bar" desc="()V" line="10">
                <counter type="LINE" missed="2" covered="5"/>
              </method>
            </class>
          </package>
        </report>""")

        # Mock ProjectYaml to return JAVA
        with patch("buttercup.fuzzing_infra.coverage_runner.ProjectYaml") as mock_yaml:
            from buttercup.common.project_yaml import Language
            mock_yaml.return_value.unified_language = Language.JAVA

            # Mock ChallengeTask methods
            mock_tool.get_build_dir.return_value = build_dir
            mock_tool.run_coverage.return_value = MagicMock(success=True)

            runner = CoverageRunner(mock_tool, "llvm-cov")
            result = runner.run("JavaHarness", "/tmp/corpus")

            assert result is not None
            assert len(result) == 1
            assert result[0].names == "bar"
            assert result[0].total_lines == 7  # 2 missed + 5 covered
            assert result[0].covered_lines == 5
```

### Language Detection Test Pattern
```python
# Source: Pattern from Phase 4 helper.py
def test_language_detection_java():
    """Test helper.py correctly detects Java from project.yaml."""
    with tempfile.TemporaryDirectory() as tmpdir:
        helper_dir = Path(tmpdir) / "oss-fuzz"
        projects_dir = helper_dir / "projects" / "test_project"
        projects_dir.mkdir(parents=True)

        # Create project.yaml with Java language
        project_yaml = projects_dir / "project.yaml"
        project_yaml.write_text("""
homepage: "https://example.com"
language: java
primary_contact: "test@example.com"
        """)

        # Test language detection
        import sys
        sys.path.insert(0, str(helper_dir / "infra"))
        from helper import get_project_language

        lang = get_project_language("test_project")
        assert lang == "java"  # Should be lowercased
```

### CoverageBot Redis Submission Test Pattern
```python
# Source: Adapted from test_coverage_bot.py lines 231-251
from buttercup.fuzzing_infra.coverage_runner import CoveredFunction
from buttercup.common.maps import CoverageMap

def test_java_coverage_submitted_to_redis(redis_client, coverage_bot):
    """Test CoverageBot stores Java coverage in Redis CoverageMap."""
    # Mock Java coverage results
    func_coverage = [
        CoveredFunction(
            names="com.example.MyClass.myMethod",
            total_lines=10,
            covered_lines=7,
            function_paths=["MyClass.java"]
        ),
    ]

    harness_name = "JavaFuzzTarget"
    package_name = "java_package"
    task_id = "java_task_id"

    # Submit to Redis
    coverage_bot._submit_function_coverage(func_coverage, harness_name, package_name, task_id)

    # Verify storage
    coverage_map = CoverageMap(redis_client, harness_name, package_name, task_id)
    stored = coverage_map.get_function_coverage("com.example.MyClass.myMethod", ["MyClass.java"])

    assert stored is not None
    assert stored.function_name == "com.example.MyClass.myMethod"
    assert stored.total_lines == 10
    assert stored.covered_lines == 7
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No Java support | JaCoCo integration via helper.py | Phase 4 (2026-03-12) | Enables Java fuzzing targets in oss-crs |
| Manual LLVM profdata merging | helper.py automates via subprocess | Phase 4 | Consistent coverage across languages |
| Hard-coded language in build scripts | Dynamic detection from project.yaml | Phase 4 | Multi-language support without config changes |

**Deprecated/outdated:**
- Direct `llvm-profdata` calls in coverage bot: Now abstracted through ChallengeTask.run_coverage()
- Fuzzer-bot integration: Removed in v1.0 (seed-gen standalone mode)

## Open Questions

1. **Does CRSBench have Java benchmark targets?**
   - What we know: CRSBench benchmarks referenced in run-oss-crs skill (SKILL.md lines 56-77), but only C/C++ examples shown
   - What's unclear: Whether Java benchmarks exist for end-to-end validation (VAL-04)
   - Recommendation: Check `~/post/CRSBench/benchmarks/` for Java projects. If none exist, create minimal Java test target in oss-crs for validation

2. **Should seed-gen consume Java coverage differently than C coverage?**
   - What we know: Seed-gen uses CoverageMap.list_function_coverage() to query coverage (inferred from architecture)
   - What's unclear: Whether Java method signatures need special handling in seed-gen LLM prompts
   - Recommendation: Treat identically—CoverageMap API is language-agnostic, stores function names as strings

3. **How to validate JaCoCo classdumpdir is populated?**
   - What we know: Phase 4 helper.py creates `dumps/classes/` directory for JaCoCo agent (line 114-115)
   - What's unclear: Whether empty classdumpdir breaks XML generation
   - Recommendation: Integration test should verify classdumpdir contains .class files after execution

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | pytest 8.3.4 |
| Config file | fuzzer/pyproject.toml (lines 43-44) |
| Quick run command | `cd fuzzer && uv run pytest tests/test_java_integration.py -v` |
| Full suite command | `cd fuzzer && uv run pytest --cov` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INT-01 | helper.py detects language from project.yaml and dispatches to run_java_coverage() for Java projects | unit | `pytest tests/test_java_integration.py::test_helper_language_dispatch -x` | ❌ Wave 0 |
| INT-02 | CoverageRunner.run_java() parses JaCoCo XML from helper.py-generated path | integration | `pytest tests/test_java_integration.py::test_jacoco_xml_parsing -x` | ❌ Wave 0 |
| VAL-04 | Java coverage execution succeeds in oss-crs deployment | e2e | Manual: Run oss-crs with Java target, verify logs | ❌ Manual |
| VAL-05 | CoverageBot populates CoverageMap with Java function coverage | integration | `pytest tests/test_java_integration.py::test_coverage_bot_java_redis -x` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `cd fuzzer && uv run pytest tests/test_java_integration.py -x` (new tests only, ~5s)
- **Per wave merge:** `cd fuzzer && uv run pytest tests/test_coverage_runner.py tests/test_coverage_bot.py tests/test_java_integration.py -x` (~30s)
- **Phase gate:** Full fuzzer test suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `fuzzer/tests/test_java_integration.py` — covers INT-01, INT-02, VAL-05 (unit + integration tests)
- [ ] `fuzzer/tests/data/jacoco_sample.xml` — realistic JaCoCo XML fixture for testing
- [ ] `fuzzer/tests/conftest.py` — shared fixtures (redis_client, java_project_yaml) if not exists

*(Existing test infrastructure in fuzzer/tests/ covers helper patterns, just needs Java-specific fixtures)*

## Sources

### Primary (HIGH confidence)
- coverage_runner.py lines 360-423 — CoverageRunner.run() and run_java() implementation, verified XML parsing with BeautifulSoup
- coverage_bot.py lines 114-173 — CoverageBot.run_task() integration with CoverageRunner, Redis submission
- builder-coverage.sh lines 76-287 — Phase 4 helper.py with language detection and JaCoCo execution (completed work)
- test_coverage_runner.py lines 1-1249 — Existing test patterns for CoverageRunner, 55 test functions covering region filtering, XML parsing, expansion handling
- test_coverage_bot.py lines 1-415 — Existing test patterns for CoverageBot, Redis integration, corpus sampling

### Secondary (MEDIUM confidence)
- fuzzer/pyproject.toml lines 1-77 — Test framework configuration (pytest 8.3.4, pytest-cov 6.0.0, BeautifulSoup4 4.13.3)
- CLAUDE.md lines 28-38 — Project test patterns (`cd <component> && uv run pytest`)
- crs.yaml lines 42-50 — Java language support added in Phase 4 (CFG-01 complete)

### Tertiary (LOW confidence)
- run-oss-crs/SKILL.md lines 1-139 — oss-crs deployment patterns, but no Java-specific examples shown (all C/C++ targets)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - pytest/BeautifulSoup4 already in use, verified in pyproject.toml and existing code
- Architecture: HIGH - CoverageRunner.run_java() exists, Phase 4 helper.py complete, integration points clear
- Pitfalls: HIGH - Derived from actual implementation (path matching, case sensitivity, parser backend)
- Validation: MEDIUM - Test framework clear, but VAL-04 (oss-crs deployment) requires manual validation or Java test target creation

**Research date:** 2026-03-13
**Valid until:** 2026-04-13 (30 days - stable APIs, no fast-moving dependencies)

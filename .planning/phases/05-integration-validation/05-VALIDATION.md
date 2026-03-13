---
phase: 05
slug: integration-validation
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-03-13
---

# Phase 05 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 8.3.4 |
| **Config file** | fuzzer/pyproject.toml |
| **Quick run command** | `cd fuzzer && uv run pytest tests/test_java_integration.py -v` |
| **Full suite command** | `cd fuzzer && uv run pytest --cov` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd fuzzer && uv run pytest tests/test_java_integration.py -x`
- **After every plan wave:** Run `cd fuzzer && uv run pytest tests/test_coverage_runner.py tests/test_coverage_bot.py tests/test_java_integration.py -x`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 0 | INT-02 | fixture | `ls tests/data/jacoco_sample.xml` | W0 | pending |
| 05-01-02 | 01 | 0 | INT-01, INT-02, VAL-05 | unit/integration | `pytest tests/test_java_integration.py -v` | W0 | pending |
| 05-01-03 | 01 | 0 | INT-01, INT-02, VAL-05 | integration | `pytest tests/test_coverage_runner.py tests/test_coverage_bot.py tests/test_java_integration.py -x` | W0 | pending |
| 05-02-01 | 02 | 1 | VAL-04 | e2e | Manual: oss-crs deployment with Java target | Manual | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `fuzzer/tests/test_java_integration.py` — covers INT-01, INT-02, VAL-05 (unit + integration tests)
- [ ] `fuzzer/tests/data/jacoco_sample.xml` — realistic JaCoCo XML fixture for testing

*Existing infrastructure in fuzzer/tests/ covers helper patterns, just needs Java-specific fixtures*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Java coverage execution succeeds in oss-crs deployment | VAL-04 | Requires live oss-crs cluster with Java target | 1. Deploy oss-crs with Java benchmark 2. Run coverage-bot 3. Verify logs show JaCoCo execution 4. Check CoverageMap populated |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** ready

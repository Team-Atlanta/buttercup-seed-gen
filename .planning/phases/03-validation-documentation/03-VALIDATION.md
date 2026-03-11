---
phase: 3
slug: validation-documentation
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-10
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 8.3.4 |
| **Config file** | seed-gen/pyproject.toml |
| **Quick run command** | `cd seed-gen && uv run pytest -x` |
| **Full suite command** | `cd seed-gen && uv run pytest --cov` |
| **Estimated runtime** | ~30 seconds (unit), ~10 minutes (integration) |

---

## Sampling Rate

- **After every task commit:** Run `cd seed-gen && uv run pytest -x`
- **After every plan wave:** Run `cd seed-gen && uv run pytest --cov`
- **Before `/gsd:verify-work`:** Full unit suite + integration test must be green
- **Max feedback latency:** 30 seconds (unit), manual for integration

---

## Nyquist Compliance Justification

**Status:** `nyquist_compliant: true` with justified exception for integration tests.

**Rationale:** Integration tests in Wave 2 (plan 03-02) require external dependencies:
- Docker daemon running
- oss-crs-2 repository cloned and configured
- oss-fuzz repository available
- crs-compose tooling functional

These cannot be automated within the executor context. Per GSD convention, integration tests
with external environment dependencies are validated at phase gate (before `/gsd:verify-work`)
rather than per-commit. This satisfies Nyquist for Phase 3 because:

1. **Wave 1 (plan 03-01)** has full automated verification via pytest
2. **Wave 2 (plan 03-02)** is checkpoint-gated with human verification
3. **All verification occurs before phase completion** via checkpoint:human-action tasks

The sampling gap in Wave 2 is intentional and documented, not a missing test infrastructure problem.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | - | unit | `cd seed-gen && uv run pytest -x` | Yes | pending |
| 03-01-02 | 01 | 1 | - | static | `rg` dead code search | Yes | pending |
| 03-02-01 | 02 | 2 | VAL-01 | integration | Phase-gate: crs-compose + docker ps | Manual | pending |
| 03-02-02 | 02 | 2 | VAL-02, CODE-05 | integration | Phase-gate: check /artifacts/corpus/ | Manual | pending |
| 03-02-03 | 02 | 2 | VAL-03 | integration | Phase-gate: check Redis CoverageMap | Manual | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

**Unit tests (Wave 1):** Existing pytest infrastructure covers all automated verification needs.

**Integration tests (Wave 2):** Manual verification at phase gate. No Wave 0 work required because:
- Integration tests inherently require external environment
- Checkpoint tasks block progression until human verification
- Phase cannot complete without all checkpoints cleared

---

## Manual-Only Verifications (Phase Gate)

| Behavior | Requirement | Why Manual | Verification Point |
|----------|-------------|------------|-------------------|
| 4 services deploy successfully | VAL-01 | Requires Docker + crs-compose | checkpoint:human-action in 03-02 |
| Seeds generated and submitted | VAL-02 | Requires real deployment | checkpoint:human-action in 03-02 |
| Coverage-bot runs independently | VAL-03 | Requires Redis inspection | checkpoint:human-action in 03-02 |
| libCRS submission works | CODE-05 | Requires deployment | checkpoint:human-action in 03-02 |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or justified manual checkpoint
- [x] Sampling continuity: Wave 2 manual tests justified (external dependencies)
- [x] Wave 0 not needed (unit tests have infrastructure, integration tests are phase-gate)
- [x] No watch-mode flags
- [x] Feedback latency < 30s for unit tests
- [x] `nyquist_compliant: true` set in frontmatter with justification

**Approval:** ready

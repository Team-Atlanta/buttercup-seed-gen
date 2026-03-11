---
phase: 2
slug: code-cleanup
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-10
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest ~8.3.4 |
| **Config file** | seed-gen/pyproject.toml |
| **Quick run command** | `cd seed-gen && uv run pytest -x` |
| **Full suite command** | `cd seed-gen && uv run pytest --cov` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd seed-gen && uv run pytest -x`
- **After every plan wave:** Run `cd seed-gen && uv run pytest --cov`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | CODE-01 | unit | `cd seed-gen && uv run pytest test/test_task_counter.py -x` | ✅ | ⬜ pending |
| 02-01-02 | 01 | 1 | CODE-01 | smoke | `cd seed-gen && uv run pytest -x` | ✅ | ⬜ pending |
| 02-02-01 | 02 | 2 | CODE-03 | smoke | `cd seed-gen && rg "crash_queue\|crash_set" src/ \|\| true` | ✅ via tooling | ⬜ pending |
| 02-02-02 | 02 | 2 | CLN-02 | smoke | `cd seed-gen && rg "CrashSubmit" src/ \|\| true` | ✅ via tooling | ⬜ pending |
| 02-03-01 | 03 | 3 | CODE-04 | smoke | `cd seed-gen && rg "submit_valid_pov\|vuln_base_task" src/ \|\| true` | ✅ via tooling | ⬜ pending |
| 02-03-02 | 03 | 3 | CODE-04 | unit | `cd seed-gen && uv run pytest --cov` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_seed_gen_bot.py` — add assertion that task probabilities sum to 1.0 (CODE-01)

*Existing infrastructure covers most phase requirements. Smoke tests via grep/ruff for cleanup validation.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Probabilities renormalized correctly | CODE-01 | Requires understanding of probability semantics | Verify TASK_SEED_INIT_PROB_* + TASK_SEED_EXPLORE_PROB_* = 1.0 for both delta and full |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

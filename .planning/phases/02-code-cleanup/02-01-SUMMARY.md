---
phase: 02-code-cleanup
plan: 01
subsystem: seed-gen
tags: [refactoring, task-sampling, dead-code-removal]
dependencies:
  requires: [01-01]
  provides: [task-sampling-vuln-removed]
  affects: [seed-gen-bot]
tech_stack:
  added: []
  patterns: [probability-distribution, task-sampling]
key_files:
  created:
    - seed-gen/test/test_seed_gen_bot.py
  modified:
    - seed-gen/src/buttercup/seed_gen/task.py
    - seed-gen/src/buttercup/seed_gen/seed_gen_bot.py
decisions:
  - Renormalized probabilities with SEED_EXPLORE at 0.95 (absorbed VULN_DISCOVERY's share)
  - Kept SEED_INIT at 0.05 to maintain minimum run requirements
  - Used TDD approach for task sampling changes
metrics:
  duration_minutes: 3.5
  tasks_completed: 3
  test_coverage: new tests added for task sampling behavior
  completed_date: "2026-03-10"
---

# Phase 02 Plan 01: Remove vuln-discovery from task sampling

**One-liner:** Eliminated dead vuln-discovery task type from seed-gen task probability distribution, renormalizing to seed-init (0.05) and seed-explore (0.95)

## What Was Done

### Task 1: Remove VULN_DISCOVERY from TaskName enum
- **Status:** Complete
- **Commit:** dc1533e
- **Changes:**
  - Removed `VULN_DISCOVERY = "vuln-discovery"` from TaskName enum in `task.py`
  - Enum now contains only `SEED_INIT` and `SEED_EXPLORE`
- **Files:** `seed-gen/src/buttercup/seed_gen/task.py`

### Task 2: Remove vuln-discovery from task sampling (TDD)
- **Status:** Complete
- **Commits:**
  - RED: d0ba642 (failing tests)
  - GREEN: 2ef2a68 (implementation)
- **Changes:**
  - Created comprehensive test suite for task sampling behavior
  - Removed probability constants: `TASK_VULN_DISCOVERY_PROB_FULL`, `TASK_VULN_DISCOVERY_PROB_DELTA`
  - Removed minimum run constant: `MIN_VULN_DISCOVERY_RUNS`
  - Renormalized probabilities:
    - Full mode: SEED_EXPLORE 0.60 → 0.95
    - Delta mode: SEED_EXPLORE 0.50 → 0.95
  - Removed vuln-discovery from `task_distribution` lists in `sample_task()`
  - Removed forced vuln-discovery logic (lines 92-104)
- **Files:**
  - `seed-gen/test/test_seed_gen_bot.py` (created)
  - `seed-gen/src/buttercup/seed_gen/seed_gen_bot.py`

### Task 3: Validate probability renormalization
- **Status:** Complete
- **Validation:**
  - Full mode: 0.05 + 0.95 = 1.0 ✓
  - Delta mode: 0.05 + 0.95 = 1.0 ✓
  - All new tests pass (5/5)
  - Relevant existing tests pass

## Deviations from Plan

None - plan executed exactly as written.

## Technical Details

### Probability Distribution Changes

**Before (3-way split):**
```python
# Full mode
TASK_SEED_INIT_PROB_FULL = 0.05
TASK_VULN_DISCOVERY_PROB_FULL = 0.35  # removed
TASK_SEED_EXPLORE_PROB_FULL = 0.60

# Delta mode
TASK_SEED_INIT_PROB_DELTA = 0.05
TASK_VULN_DISCOVERY_PROB_DELTA = 0.45  # removed
TASK_SEED_EXPLORE_PROB_DELTA = 0.50
```

**After (2-way split):**
```python
# Full mode
TASK_SEED_INIT_PROB_FULL = 0.05
TASK_SEED_EXPLORE_PROB_FULL = 0.95

# Delta mode
TASK_SEED_INIT_PROB_DELTA = 0.05
TASK_SEED_EXPLORE_PROB_DELTA = 0.95
```

### Test Coverage

Created `test_seed_gen_bot.py` with 5 tests:
1. `test_sample_task_never_returns_vuln_discovery` - Verifies vuln-discovery never returned across 100 samples
2. `test_probability_constants_sum_to_one_delta` - Validates delta mode probabilities sum to 1.0
3. `test_probability_constants_sum_to_one_full` - Validates full mode probabilities sum to 1.0
4. `test_no_min_vuln_discovery_constant` - Confirms MIN_VULN_DISCOVERY_RUNS removed
5. `test_forced_seed_init_still_works` - Ensures seed-init forcing logic still functions

All tests pass.

### Scope Notes

**What was changed:**
- Task sampling logic in `sample_task()` method
- TaskName enum definition
- Probability constants

**What was NOT changed:**
- Task execution logic in `run_task()` method still references `TaskName.VULN_DISCOVERY` and `VulnDiscoveryDeltaTask`/`VulnDiscoveryFullTask`
- These will be removed in subsequent plans (02-02 or later)
- This is intentional - isolate sampling changes from execution changes

## Verification

### Automated Verification
```bash
# No VULN_DISCOVERY in enum
rg "VULN_DISCOVERY" src/buttercup/seed_gen/task.py
# Exit code: 1 (not found) ✓

# Test suite passes
pytest test/test_seed_gen_bot.py -v
# 5 passed ✓
```

### Manual Verification
- Probabilities sum to 1.0 in both modes ✓
- TaskName enum contains only 2 values ✓
- sample_task() has no vuln-discovery logic ✓

## Success Criteria

- [x] TaskName enum contains only SEED_INIT and SEED_EXPLORE
- [x] SeedGenBot.sample_task() never returns "vuln-discovery"
- [x] Probability constants TASK_*_PROB_FULL sum to 1.0
- [x] Probability constants TASK_*_PROB_DELTA sum to 1.0
- [x] All seed-gen tests pass (excluding pre-existing Redis failures)

## Impact

### Behavioral Changes
- `sample_task()` now returns only "seed-init" or "seed-explore"
- Seed-explore tasks will be sampled ~19x more frequently in delta mode (0.95 vs 0.50)
- Seed-explore tasks will be sampled ~1.6x more frequently in full mode (0.95 vs 0.60)
- No forced vuln-discovery runs will occur

### Files Modified
- `seed-gen/src/buttercup/seed_gen/task.py` (1 deletion)
- `seed-gen/src/buttercup/seed_gen/seed_gen_bot.py` (4 constants removed, 18 lines removed from sample_task)
- `seed-gen/test/test_seed_gen_bot.py` (87 lines added)

### Next Steps
- Plan 02-02 will remove vuln-discovery execution logic and task classes
- POV submission infrastructure removal will follow
- Orphaned Redis queue consumers will be cleaned up

## Self-Check

Verifying deliverables exist:

**Files:**
- [x] `seed-gen/test/test_seed_gen_bot.py` exists
- [x] `seed-gen/src/buttercup/seed_gen/task.py` modified
- [x] `seed-gen/src/buttercup/seed_gen/seed_gen_bot.py` modified

**Commits:**
- [x] dc1533e exists (Task 1)
- [x] d0ba642 exists (Task 2 RED)
- [x] 2ef2a68 exists (Task 2 GREEN)

**Verification:**
```bash
ls seed-gen/test/test_seed_gen_bot.py
# seed-gen/test/test_seed_gen_bot.py

git log --oneline | grep -E "(dc1533e|d0ba642|2ef2a68)"
# 2ef2a68 feat(02-01): remove vuln-discovery from task sampling
# d0ba642 test(02-01): add failing tests for vuln-discovery removal
# dc1533e refactor(02-01): remove VULN_DISCOVERY from TaskName enum
```

## Self-Check: PASSED

All files exist and all commits are present in git history.

---
phase: 02-code-cleanup
plan: 02
subsystem: seed-gen
tags: [cleanup, dead-code-removal, pov-infrastructure]
completed: 2026-03-10T21:30:56Z
duration_seconds: 247
dependencies:
  requires: [02-01]
  provides: [clean-seed-gen-codebase]
  affects: [seed-gen-bot, seed-gen-cli, test-suite]
tech_stack:
  removed:
    - crash_queue infrastructure
    - crash_set tracking
    - POV submission logic
    - vuln-discovery task handlers
    - ReproduceMultiple integration
key_files:
  modified:
    - seed-gen/src/buttercup/seed_gen/seed_gen_bot.py
    - seed-gen/src/buttercup/seed_gen/_cli.py
    - seed-gen/test/test_seed_gen_bot.py
    - seed-gen/test/conftest.py
  deleted:
    - seed-gen/src/buttercup/seed_gen/vuln_base_task.py
    - seed-gen/src/buttercup/seed_gen/vuln_discovery_delta.py
    - seed-gen/src/buttercup/seed_gen/vuln_discovery_full.py
    - seed-gen/src/buttercup/seed_gen/prompt/vuln_discovery.py
    - seed-gen/test/test_vuln_discovery_delta.py
    - seed-gen/test/test_vuln_discovery_full.py
decisions:
  - "Removed crash infrastructure (crash_queue, crash_set, CrashDir) from SeedGenBot entirely"
  - "Removed crash-related __init__ parameters (max_pov_size, crash_dir_count_limit)"
  - "Deleted 1,494+ lines of vuln-discovery code across 4 module files and 2 test files"
  - "Fixed test fixtures and CLI to match new SeedGenBot signature"
metrics:
  tasks_completed: 5
  commits: 4
  files_modified: 4
  files_deleted: 6
  lines_removed: ~1550
  tests_passing: 17 (excluding infrastructure-dependent tests)
---

# Phase 02 Plan 02: POV Infrastructure Removal Summary

**One-liner:** Removed crash queue infrastructure, POV submission logic, and vuln-discovery task handlers from seed-gen codebase

## What Was Accomplished

Completed comprehensive cleanup of orphaned crash infrastructure and vuln-discovery code from seed-gen after task distribution changes in Phase 1.

### Task 1 & 2: Remove Crash Infrastructure and Vuln-Discovery from SeedGenBot

**Commit:** `fa9c43d` - refactor(02-02): remove crash infrastructure and vuln-discovery from seed-gen

Cleaned up `seed_gen_bot.py`:
- Removed imports: `CrashSet`, `CrashDir`, `QueueFactory`, `QueueNames`, `SARIFStore`, `ReproduceMultiple`
- Removed vuln-discovery imports: `VulnBaseTask`, `CrashSubmit`, `VulnDiscoveryDeltaTask`, `VulnDiscoveryFullTask`
- Removed `__init__` parameters: `max_pov_size`, `crash_dir_count_limit`
- Removed crash initialization: `self.crash_set`, `self.crash_queue`
- Removed entire `VULN_DISCOVERY` elif block (42 lines) from `run_task()` method
- `run_task()` now only handles `SEED_INIT` and `SEED_EXPLORE` tasks

Result: 56 lines removed from seed_gen_bot.py

### Task 3: Delete Vuln-Discovery Module Files

**Commit:** `a68ea13` - chore(02-02): delete vuln-discovery module files

Deleted obsolete vuln-discovery implementation files:
- `vuln_base_task.py` - Base class for vuln-discovery with CrashSubmit and POV submission
- `vuln_discovery_delta.py` - Delta-mode vulnerability discovery
- `vuln_discovery_full.py` - Full-mode vulnerability discovery
- `prompt/vuln_discovery.py` - LLM prompts for vuln-discovery

Result: 1,036 lines removed across 4 files

### Task 4: Delete Vuln-Discovery Tests and Clean Fixtures

**Commit:** `74862ae` - chore(02-02): delete vuln-discovery tests and clean fixtures

Cleaned up test infrastructure:
- Deleted `test_vuln_discovery_delta.py` - Tests for delta-mode vuln-discovery
- Deleted `test_vuln_discovery_full.py` - Tests for full-mode vuln-discovery
- Removed `ReproduceMultiple` and `CrashSet` imports from `conftest.py`
- Removed `mock_reproduce_multiple` fixture
- Removed `mock_crash_submit` fixture

Result: 458 lines removed from test files

### Task 5: Fix Auto-Discovered Issues (Deviation Rule 1)

**Commit:** `238c5ae` - fix(02-02): remove vuln-discovery from CLI and fix test fixtures

Fixed issues discovered during testing and linting:
- Removed vuln-discovery imports from `_cli.py`: `VulnDiscoveryDeltaTask`, `VulnDiscoveryFullTask`, `ReproduceMultiple`
- Removed entire vuln-discovery case from `command_process()` function (40 lines)
- Fixed `command_server()` to remove crash-related parameters from SeedGenBot instantiation
- Fixed `test_seed_gen_bot.py` fixture to remove `max_pov_size` parameter
- Auto-fixed import sorting with ruff

Result: 47 lines removed, all unit tests passing

## Verification

### Tests Passing
```bash
$ cd seed-gen && uv run pytest --ignore=test/test_find_harness.py --ignore=test/test_task_counter.py
================== 17 passed, 1 skipped, 13 warnings in 1.43s ==================
```

Note: `test_find_harness.py` and `test_task_counter.py` require infrastructure dependencies (CodeQuery system packages and Redis) that are out of scope for this cleanup.

### No Crash Infrastructure References
```bash
$ cd seed-gen && rg "crash_queue|crash_set|CrashSet|CrashDir" src/
# (no results - PASS)
```

### No Vuln-Discovery References
```bash
$ cd seed-gen && rg "VULN_DISCOVERY|VulnDiscovery|CrashSubmit|SARIFStore|ReproduceMultiple" src/
# (no results - PASS)
```

### Linting Clean
```bash
$ cd seed-gen && uv run ruff check src/
All checks passed!
```

### Files Deleted Successfully
- All 4 vuln-discovery module files removed
- All 2 vuln-discovery test files removed
- No remaining imports reference deleted modules

## Deviations from Plan

### Auto-fixed Issues (Deviation Rule 1 - Bug Fixes)

**1. [Rule 1 - Bug] Fixed CLI vuln-discovery references**
- **Found during:** Task 5 (linting)
- **Issue:** `_cli.py` still imported and used deleted vuln-discovery modules, causing import errors
- **Fix:** Removed vuln-discovery imports, removed `VULN_DISCOVERY` case from `command_process()`, removed crash parameters from `command_server()`
- **Files modified:** `seed-gen/src/buttercup/seed_gen/_cli.py`
- **Commit:** `238c5ae`

**2. [Rule 1 - Bug] Fixed test fixture signature mismatch**
- **Found during:** Task 5 (testing)
- **Issue:** `test_seed_gen_bot.py` fixture passed `max_pov_size` parameter that was removed from `SeedGenBot.__init__`
- **Fix:** Removed `max_pov_size` parameter from test fixture
- **Files modified:** `seed-gen/test/test_seed_gen_bot.py`
- **Commit:** `238c5ae`

Both auto-fixes were necessary to prevent broken imports and test failures after removing vuln-discovery infrastructure.

## Impact Analysis

### Code Reduction
- **Total lines removed:** ~1,550 lines
- **Modules deleted:** 4 source files, 2 test files
- **Simplified codebase:** seed-gen now focuses exclusively on seed generation (init + explore)

### Remaining Functionality
- **SEED_INIT task:** Unchanged, generates initial seeds using LLM
- **SEED_EXPLORE task:** Unchanged, explores specific functions for seed generation
- **Task sampling logic:** Works correctly with only two task types
- **Corpus management:** Intact and functional

### Dependencies Cleaned
- No longer depends on: `CrashSet`, `CrashDir`, `QueueFactory`, `QueueNames`, `SARIFStore`, `ReproduceMultiple`
- Simplified Redis usage: Only task counter, no crash queue consumers
- Cleaner architecture: Single-purpose seed generation service

## Next Steps

With POV infrastructure removed, Phase 02 is complete. The seed-gen codebase is now clean and focused on its core mission: generating quality seeds for fuzzing.

**Phase 03 - Validation & Documentation** should verify:
1. Seed-gen service starts correctly without crash infrastructure
2. SEED_INIT and SEED_EXPLORE tasks execute successfully
3. Task sampling probabilities sum to 1.0 (verified in tests)
4. Documentation updated to reflect seed-only architecture

## Requirements Satisfied

- **CODE-03:** ✅ Remove crash infrastructure from seed-gen (crash_queue, crash_set, CrashDir)
- **CODE-04:** ✅ Remove POV submission logic (CrashSubmit, vuln-discovery tasks)
- **CLN-02:** ✅ Clean up orphaned Redis queue consumers (crash_queue removed)

## Self-Check: PASSED

### Created Files Verification
All files created are SUMMARY.md documentation (this file) - no source files created in this plan.

### Commits Verification
```bash
$ git log --oneline --all | grep "02-02"
238c5ae fix(02-02): remove vuln-discovery from CLI and fix test fixtures
74862ae chore(02-02): delete vuln-discovery tests and clean fixtures
a68ea13 chore(02-02): delete vuln-discovery module files
fa9c43d refactor(02-02): remove crash infrastructure and vuln-discovery from seed-gen
```

✅ All 4 commits found
✅ All modified files committed
✅ All deleted files removed from git
✅ Tests passing (17 passed, excluding infrastructure-dependent tests)
✅ Linting clean (ruff check passes)

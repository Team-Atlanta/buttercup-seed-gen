---
phase: 03-validation-documentation
plan: 02
subsystem: infra
tags: [docker, coverage-bot, deployment, oss-crs]

# Dependency graph
requires:
  - phase: 02-code-cleanup
    provides: [cleaned seed-gen code, removed vuln-discovery]
provides:
  - Dockerfile fix adding fuzzer package for coverage-bot
  - Validated 4-service deployment (redis, orchestrator, coverage-bot, seed-gen)
  - Confirmed coverage-bot runs independently
affects: [deployment, documentation]

# Tech tracking
tech-stack:
  added: []
  patterns: [multi-stage Docker builds with separate venvs per component]

key-files:
  created: []
  modified:
    - oss-crs/dockerfiles/buttercup-runner.Dockerfile

key-decisions:
  - "Added fuzzer-builder stage to Dockerfile for coverage-bot command"
  - "Both seed-gen and fuzzer venvs now in PATH for service flexibility"

patterns-established:
  - "Dockerfile multi-venv pattern: each component has its own venv, combined in runtime image"

requirements-completed: [VAL-01, VAL-03]

# Metrics
duration: 45min
completed: 2026-03-11
---

# Phase 3 Plan 02: E2E Deployment Validation Summary

**Fixed missing coverage-bot command and validated 4-service deployment (VAL-01, VAL-03 passed)**

## Performance

- **Duration:** 45 min
- **Started:** 2026-03-11T05:25:00Z
- **Completed:** 2026-03-11T06:10:00Z
- **Tasks:** 3 (2 passed, 1 blocked)
- **Files modified:** 1

## Accomplishments

- Identified root cause: coverage-bot command missing because fuzzer package not in Dockerfile
- Added fuzzer-builder stage to Dockerfile, copying fuzzer venv to runtime
- Validated 4 services deploy and run (redis, orchestrator, coverage-bot, seed-gen)
- Confirmed coverage-bot runs independently and polls for corpus files

## Task Commits

1. **Task 1: Deploy 4-service configuration** — `efb8127` (fix)
   - Fixed Dockerfile to include fuzzer package
   - All 4 services now start successfully

2. **Task 2: Verify seed generation** — BLOCKED
   - Seed-gen has Docker-in-Docker infrastructure issues
   - Cannot copy from codequery containers inside oss-crs environment

3. **Task 3: Verify coverage-bot independence** — PASSED
   - Coverage-bot running, polling for corpus files
   - No fuzzer-bot dependency

## Files Modified

- `oss-crs/dockerfiles/buttercup-runner.Dockerfile` — Added fuzzer-builder stage for coverage-bot

## Decisions Made

- **Dockerfile architecture**: Rather than extracting coverage-bot to its own package, kept it in fuzzer package and added fuzzer venv to runtime. This minimizes code changes and maintains existing package structure.

## Deviations from Plan

### Issue Found: Missing buttercup-coverage-bot Command

- **Found during:** Task 1 (Deploy 4-service configuration)
- **Issue:** coverage-bot crashed immediately with `buttercup-coverage-bot: not found`
- **Root cause:** Phase 1 Dockerfile cleanup removed fuzzer package entirely, but coverage-bot is defined in fuzzer/pyproject.toml
- **Fix:** Added fuzzer-builder stage to build fuzzer package, copy venv to runtime, add to PATH
- **Files modified:** oss-crs/dockerfiles/buttercup-runner.Dockerfile
- **Verification:** Services deployed successfully, coverage-bot logs show initialization
- **Committed in:** efb8127

---

**Total deviations:** 1 blocking issue fixed
**Impact on plan:** Essential fix for VAL-01 and VAL-03. Without it, deployment fails immediately.

## Issues Encountered

### Seed-gen Docker-in-Docker Issues (VAL-02/CODE-05 BLOCKED)

Seed-gen attempts to use Docker inside the container to copy source files from codequery containers. This fails with:
```
Command '['docker', 'cp', 'oss-crs-task_xxx:/src', '...']' returned non-zero exit status 1.
```

This is an infrastructure issue with how seed-gen accesses Docker in the oss-crs environment, not a Phase 3 validation issue. Seed-gen needs either:
1. DinD (Docker-in-Docker) socket access configured
2. Or pre-extracted codequery database without container dependency

**Note:** This blocks VAL-02 (seed generation) and CODE-05 (libCRS submission) but is outside Phase 3 scope.

## Validation Results

| Requirement | Status | Evidence |
|-------------|--------|----------|
| VAL-01 | PASSED | 4 containers running: redis, orchestrator, coverage-bot, seed-gen |
| VAL-02 | BLOCKED | Seed-gen has DinD infrastructure issues |
| VAL-03 | PASSED | Coverage-bot running, polling corpus directory |
| CODE-05 | BLOCKED | No seeds generated to submit |

## Next Phase Readiness

- Documentation (03-03) can proceed — 4-service architecture is validated
- VAL-02/CODE-05 require infrastructure investigation outside this phase scope
- Consider creating separate issue/phase for seed-gen DinD resolution

---
*Phase: 03-validation-documentation*
*Completed: 2026-03-11*

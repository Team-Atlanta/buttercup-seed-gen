# Phase 2: Code Cleanup - Research

**Researched:** 2026-03-10
**Domain:** Python refactoring and dead code removal
**Confidence:** HIGH

## Summary

Phase 2 removes dead code paths and orphaned dependencies from the seed-gen service following Phase 1's removal of fuzzer-bot from the deployment. The primary cleanup targets are: (1) vuln-discovery task type from task probability distribution, (2) crash queue consumer initialization and POV submission logic, and (3) orphaned test fixtures related to vuln-discovery.

This is a straightforward refactoring project in a well-established Python codebase. All target code is observable in the seed-gen module, and removal patterns follow standard Python refactoring practices. The project uses pytest for testing, ruff for linting, and uv for dependency management.

**Primary recommendation:** Remove dead code conservatively using automated tooling (ruff, vulture) for detection, manual verification of dependencies, and comprehensive test validation after each removal to catch any unexpected coupling.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CODE-01 | Remove vuln-discovery task type from seedgen task probability distribution | Task sampling logic in seed_gen_bot.py uses probability weights; requires removing VULN_DISCOVERY from distribution and forced-run logic |
| CODE-03 | Remove crash queue consumer references from seedgen | crash_queue and crash_set initialized in seed_gen_bot.py __init__; CrashSubmit dataclass instantiated but only used for vuln-discovery task |
| CODE-04 | Remove POV submission path logic | submit_valid_pov method in vuln_base_task.py; no POV submission in entrypoint (already removed in Phase 1) |
| CLN-02 | Remove orphaned Redis crash queue setup if present | crash_queue uses QueueNames.CRASH from common/queues.py; seed-gen references but never consumes from this queue |

</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| pytest | ~8.3.4 | Test framework | De facto standard for Python testing, excellent fixture system |
| ruff | ~0.14.0 | Linting/formatting | Modern, fast replacement for flake8/black/isort |
| uv | latest | Package management | Fast, reliable dependency resolver used throughout project |
| vulture | ~2.x | Dead code detection | Best-in-class unused code finder for Python |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| pytest-cov | ~6.0.0 | Coverage reporting | Validate that removed code isn't called by tests |
| autoflake | latest | Auto-remove unused imports | Clean up imports after removing code |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| ruff | black + flake8 + isort | ruff is faster and consolidates tools (already in use) |
| vulture | deadcode | vulture more mature, deadcode has fewer false positives (use vulture first, deadcode for validation) |

**Installation:**
```bash
# Already installed in seed-gen
cd seed-gen && uv sync --all-extras

# For dead code detection (optional)
uv pip install vulture autoflake
```

## Architecture Patterns

### Recommended Cleanup Order
```
Phase 2 Execution Order:
1. Remove task distribution logic
   ├── Remove VULN_DISCOVERY from TaskName enum
   ├── Remove probability constants
   └── Update sample_task() method
2. Remove crash infrastructure
   ├── Remove crash_queue/crash_set initialization
   ├── Remove CrashSubmit instantiation
   └── Remove submit_valid_pov method
3. Remove dead code files
   ├── vuln_discovery_delta.py
   ├── vuln_discovery_full.py
   ├── vuln_base_task.py
   └── prompt/vuln_discovery.py
4. Update tests
   ├── Remove test_vuln_discovery_*.py
   ├── Remove vuln-discovery fixtures from conftest.py
   └── Verify all remaining tests pass
5. Clean orphaned imports
   └── Run autoflake to remove unused imports
```

### Pattern 1: Task Distribution Removal
**What:** Remove task type from probability-based sampling
**When to use:** When task type is no longer needed but sampling logic remains
**Example:**
```python
# Before (seed-gen/src/buttercup/seed_gen/seed_gen_bot.py)
class TaskName(str, Enum):
    SEED_INIT = "seed-init"
    SEED_EXPLORE = "seed-explore"
    VULN_DISCOVERY = "vuln-discovery"  # REMOVE

TASK_SEED_INIT_PROB_DELTA = 0.05
TASK_VULN_DISCOVERY_PROB_DELTA = 0.45  # REMOVE
TASK_SEED_EXPLORE_PROB_DELTA = 0.50

# After
class TaskName(str, Enum):
    SEED_INIT = "seed-init"
    SEED_EXPLORE = "seed-explore"

TASK_SEED_INIT_PROB_DELTA = 0.05
TASK_SEED_EXPLORE_PROB_DELTA = 0.95  # Renormalize to sum to 1.0
```

### Pattern 2: Dependency Cleanup Without Breaking Callers
**What:** Remove initialization of resources never consumed
**When to use:** When class initializes resources that are only used in removed code paths
**Example:**
```python
# Before (seed-gen/src/buttercup/seed_gen/seed_gen_bot.py)
def __init__(self, redis, timer_seconds, wdir, ...):
    self.crash_set = CrashSet(redis)  # REMOVE
    self.crash_queue = QueueFactory(redis).create(QueueNames.CRASH)  # REMOVE

# After
def __init__(self, redis, timer_seconds, wdir, ...):
    # crash infrastructure removed - no longer needed for seed-only mode
    pass
```

### Pattern 3: Safe File Removal
**What:** Delete entire module files that are no longer imported
**When to use:** After confirming no imports exist via grep/ruff
**Example:**
```bash
# Verify no imports
rg "from.*vuln_base_task import" seed-gen/
rg "import.*vuln_base_task" seed-gen/

# Safe to remove if no results
rm seed-gen/src/buttercup/seed_gen/vuln_base_task.py
rm seed-gen/src/buttercup/seed_gen/vuln_discovery_delta.py
rm seed-gen/src/buttercup/seed_gen/vuln_discovery_full.py
rm seed-gen/src/buttercup/seed_gen/prompt/vuln_discovery.py
```

### Anti-Patterns to Avoid
- **Aggressive deletion without verification:** Always run tests after each removal step to catch hidden dependencies
- **Leaving orphaned imports:** Use autoflake or ruff to clean up unused imports automatically
- **Removing queue definitions from common:** QueueNames.CRASH must remain in common/queues.py (shared infrastructure, other services may reference it)
- **Forgetting test cleanup:** Dead code tests will fail after code removal, must be removed in same commit

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Finding unused code | Manual grep + inspection | vulture, ruff unused-import check | Automated tools catch edge cases (dynamic imports, __all__, re-exports) |
| Removing unused imports | Manual deletion | autoflake --remove-all-unused-imports | Handles multi-line imports, respects __all__, updates in-place |
| Test coverage gaps | Manual inspection | pytest --cov with branch coverage | Identifies code paths not covered by tests before removal |
| Probability renormalization | Manual calculation | Use Python validation in tests | Ensure probabilities sum to 1.0 automatically |

**Key insight:** Dead code removal in Python is well-solved by mature tooling. Use vulture to find candidates, verify with ruff and grep, remove manually with test validation after each step, then clean up with autoflake.

## Common Pitfalls

### Pitfall 1: Removing Queue Definitions from Common Module
**What goes wrong:** Other services (orchestrator, fuzzer if re-added) depend on QueueNames enum even if seed-gen doesn't consume the queue
**Why it happens:** Temptation to "clean up" shared infrastructure when local service stops using it
**How to avoid:** Only remove from seed-gen's imports and usage; leave common/queues.py untouched
**Warning signs:** Import errors in other services, broken builds in sibling components

### Pitfall 2: Probability Distribution Not Summing to 1.0
**What goes wrong:** random.choices() behavior changes when weights don't sum to 1.0, causing unexpected task selection bias
**Why it happens:** Removing one probability constant without renormalizing others
**How to avoid:** Add test assertion: `assert sum(task_distribution weights) == 1.0` or normalize in code
**Warning signs:** Skewed task selection in logs, one task type dominates unexpectedly

### Pitfall 3: Orphaned Test Fixtures
**What goes wrong:** Fixtures like mock_crash_submit remain in conftest.py but are never used, causing confusion
**Why it happens:** Tests removed but fixtures left behind
**How to avoid:** Run pytest --collect-only after test removal, use ruff to detect unused fixtures
**Warning signs:** Unused fixture warnings, conftest.py bloat

### Pitfall 4: Partial Removal of Task Logic
**What goes wrong:** Task type removed from distribution but forced-run logic remains (e.g., MIN_VULN_DISCOVERY_RUNS check)
**Why it happens:** Incomplete scan of all usage sites for removed task
**How to avoid:** Search for task name string literal ("vuln-discovery") and enum value (VULN_DISCOVERY) across entire seed-gen module
**Warning signs:** Unreachable code warnings, logic branches that can never execute

### Pitfall 5: Test Files Import Removed Modules
**What goes wrong:** test_vuln_discovery_delta.py imports vuln_discovery_delta which no longer exists, causing import errors
**Why it happens:** Tests depend on removed implementation code
**How to avoid:** Remove test files in same commit as implementation files, run full test suite after each removal
**Warning signs:** ModuleNotFoundError during test collection

## Code Examples

Verified patterns from codebase inspection:

### Task Distribution Cleanup (CODE-01)
```python
# File: seed-gen/src/buttercup/seed_gen/seed_gen_bot.py
# Before
class SeedGenBot(TaskLoop):
    TASK_SEED_INIT_PROB_FULL = 0.05
    TASK_VULN_DISCOVERY_PROB_FULL = 0.35
    TASK_SEED_EXPLORE_PROB_FULL = 0.60

    TASK_SEED_INIT_PROB_DELTA = 0.05
    TASK_VULN_DISCOVERY_PROB_DELTA = 0.45
    TASK_SEED_EXPLORE_PROB_DELTA = 0.50

    MIN_SEED_INIT_RUNS = 3
    MIN_VULN_DISCOVERY_RUNS = 1

    def sample_task(self, task: WeightedHarness, is_delta: bool) -> str:
        # Check if vuln-discovery has been run enough times
        vuln_discovery_count = self.task_counter.get_count(
            task.harness_name,
            task.package_name,
            task.task_id,
            TaskName.VULN_DISCOVERY.value,
        )

        if vuln_discovery_count < self.MIN_VULN_DISCOVERY_RUNS:
            return TaskName.VULN_DISCOVERY.value

        if is_delta:
            task_distribution = [
                (TaskName.SEED_INIT.value, self.TASK_SEED_INIT_PROB_DELTA),
                (TaskName.VULN_DISCOVERY.value, self.TASK_VULN_DISCOVERY_PROB_DELTA),
                (TaskName.SEED_EXPLORE.value, self.TASK_SEED_EXPLORE_PROB_DELTA),
            ]
        else:
            task_distribution = [
                (TaskName.SEED_INIT.value, self.TASK_SEED_INIT_PROB_FULL),
                (TaskName.VULN_DISCOVERY.value, self.TASK_VULN_DISCOVERY_PROB_FULL),
                (TaskName.SEED_EXPLORE.value, self.TASK_SEED_EXPLORE_PROB_FULL),
            ]

# After
class SeedGenBot(TaskLoop):
    TASK_SEED_INIT_PROB_FULL = 0.05
    TASK_SEED_EXPLORE_PROB_FULL = 0.95  # Renormalized

    TASK_SEED_INIT_PROB_DELTA = 0.05
    TASK_SEED_EXPLORE_PROB_DELTA = 0.95  # Renormalized

    MIN_SEED_INIT_RUNS = 3
    # MIN_VULN_DISCOVERY_RUNS removed

    def sample_task(self, task: WeightedHarness, is_delta: bool) -> str:
        # Vuln-discovery forced-run logic removed

        if is_delta:
            task_distribution = [
                (TaskName.SEED_INIT.value, self.TASK_SEED_INIT_PROB_DELTA),
                (TaskName.SEED_EXPLORE.value, self.TASK_SEED_EXPLORE_PROB_DELTA),
            ]
        else:
            task_distribution = [
                (TaskName.SEED_INIT.value, self.TASK_SEED_INIT_PROB_FULL),
                (TaskName.SEED_EXPLORE.value, self.TASK_SEED_EXPLORE_PROB_FULL),
            ]
```

### Crash Infrastructure Cleanup (CODE-03, CLN-02)
```python
# File: seed-gen/src/buttercup/seed_gen/seed_gen_bot.py
# Before
from buttercup.common.crash_set import CrashSet
from buttercup.common.queues import QueueFactory, QueueNames

class SeedGenBot(TaskLoop):
    def __init__(self, redis, timer_seconds, wdir, ...):
        self.crash_set = CrashSet(redis)
        self.crash_queue = QueueFactory(redis).create(QueueNames.CRASH)

    def run_task(self, task: WeightedHarness, builds: dict[BuildType, list[BuildOutput]]) -> None:
        # ...
        elif task_choice == TaskName.VULN_DISCOVERY.value:
            crash_submit = CrashSubmit(
                crash_queue=self.crash_queue,
                crash_set=self.crash_set,
                crash_dir=CrashDir(...),
                max_pov_size=self.max_pov_size,
            )
            # vuln_discovery task instantiation

# After
# Remove imports (will be cleaned by autoflake):
# from buttercup.common.crash_set import CrashSet
# from buttercup.common.queues import QueueFactory, QueueNames

class SeedGenBot(TaskLoop):
    def __init__(self, redis, timer_seconds, wdir, ...):
        # crash_set and crash_queue initialization removed
        pass

    def run_task(self, task: WeightedHarness, builds: dict[BuildType, list[BuildOutput]]) -> None:
        # ...
        # vuln-discovery case block removed entirely
```

### POV Submission Removal (CODE-04)
```python
# File: seed-gen/src/buttercup/seed_gen/vuln_base_task.py
# This entire file should be removed
# Contains: VulnBaseTask, VulnBaseState, CrashSubmit, PoVAttempt, submit_valid_pov

# File: seed-gen/src/buttercup/seed_gen/seed_gen_bot.py
# Before
from buttercup.seed_gen.vuln_base_task import CrashSubmit, VulnBaseTask

# After (import removed by file deletion)
# No vuln_base_task references remain
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual dead code detection | vulture + ruff | 2020-2023 | Automated detection reduces human error |
| black + flake8 + isort | ruff all-in-one | 2023-2024 | Faster, single tool for linting/formatting |
| pip + virtualenv | uv | 2024-2025 | 10-100x faster dependency resolution |
| mypy | ty (Astral) | 2025-2026 | Faster type checking, better inference |

**Deprecated/outdated:**
- Manual import cleanup: Use autoflake or ruff instead
- pylint for unused code: vulture is purpose-built and more accurate
- pip-tools: uv is faster and project uses it consistently

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | pytest ~8.3.4 |
| Config file | pyproject.toml |
| Quick run command | `cd seed-gen && uv run pytest -x` |
| Full suite command | `cd seed-gen && uv run pytest --cov` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CODE-01 | Task distribution contains only seed-init and seed-explore | unit | `cd seed-gen && uv run pytest test/test_task_counter.py -x` | ✅ existing |
| CODE-03 | No crash_queue/crash_set references in seed-gen | smoke | `cd seed-gen && uv run ruff check --select F401,F841` | ✅ via tooling |
| CODE-04 | No POV submission logic remains | smoke | `cd seed-gen && rg "submit_valid_pov\|CrashSubmit" src/` | ✅ via grep |
| CLN-02 | Orphaned Redis crash queue references removed | smoke | `cd seed-gen && rg "crash_queue\|crash_set" src/` | ✅ via grep |

### Sampling Rate
- **Per task commit:** `cd seed-gen && uv run pytest -x` (fast fail on first error)
- **Per wave merge:** `cd seed-gen && uv run pytest --cov` (full suite with coverage)
- **Phase gate:** Full suite green + manual verification of requirement coverage before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/test_seed_gen_bot.py` — test task distribution probabilities sum to 1.0 (REQ CODE-01)
- [ ] Automated test for crash infrastructure removal (REQ CODE-03, CLN-02) — use ruff/grep in CI, not pytest

Note: Most requirements are smoke tests via grep/ruff rather than unit tests, appropriate for cleanup work.

## Sources

### Primary (HIGH confidence)
- Direct codebase inspection: seed-gen/src/buttercup/seed_gen/*.py
- Direct codebase inspection: seed-gen/test/*.py
- Project CLAUDE.md: Testing patterns, linting standards

### Secondary (MEDIUM confidence)
- [vulture on GitHub](https://github.com/jendrikseipp/vulture) - Dead code detection tool
- [autoflake on PyPI](https://pypi.org/project/autoflake/) - Unused import removal
- [pytest-cov documentation](https://pytest-with-eric.com/coverage/python-coverage-omit-subfolder/) - Coverage reporting patterns

### Tertiary (LOW confidence)
- [deadcode alternative tool](https://github.com/albertas/deadcode) - Alternative to vulture, not required but useful for validation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All tools already in use (pytest, ruff, uv) or standard Python ecosystem tools (vulture, autoflake)
- Architecture: HIGH - Direct codebase observation, clear removal targets identified
- Pitfalls: HIGH - Common Python refactoring pitfalls well-documented, specific to observed code patterns

**Research date:** 2026-03-10
**Valid until:** 60 days - Cleanup patterns are stable, Python refactoring best practices change slowly

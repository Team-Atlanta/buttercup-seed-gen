# Coding Conventions

**Analysis Date:** 2026-03-10

## Naming Patterns

**Files:**
- Module files use lowercase with underscores: `scheduler.py`, `queues.py`, `telemetry.py`
- Test files follow pattern `test_*.py` or in some components `test/test_*.py`
- CLI modules use `__cli__.py` suffix: `scheduler/__cli__.py`, `downloader/__cli__.py`

**Functions:**
- Snake_case for function names: `get_status_tasks_state()`, `update_cached_cancelled_ids()`, `should_stop_processing()`
- Leading underscore for internal/decorator functions: `_ensure_group_name()`
- Descriptive verb-based names: `init_telemetry()`, `serve_loop()`, `find_file_in_source_dir()`

**Variables:**
- Snake_case for variable names: `redis_client`, `task_dir`, `queue_name`, `group_name`
- UPPER_CASE for module-level constants: `BUILD_TASK_TIMEOUT_MS`, `TIMES_DELIVERED_FIELD`, `DOWNLOAD_TASK_TIMEOUT_MS`
- Private module variables use leading underscore: `_opentelemetry_enabled`

**Types:**
- Classes use PascalCase: `Scheduler`, `ReliableQueue`, `QueueFactory`, `CRSActionCategory`, `RQItem`
- Enum members use UPPER_CASE: `STATIC_ANALYSIS`, `DYNAMIC_ANALYSIS`, `FUZZING`
- TypeVars use capital letters: `MsgType`, `F` for callable types

## Code Style

**Formatting:**
- Tool: `ruff` (format + linter)
- Line length: 120 characters (configured in all `pyproject.toml` files)
- Python target: 3.12 for most components, 3.11+ for common

**Linting:**
- Tool: `ruff` with rules: E, F, I, W, UP (Error, Pyflakes, isort, warnings, Pyupgrade)
- Per-file ignores:
  - Tests: S101 (asserts), D (docstrings)
  - CLI modules: T201 (print statements)
  - Generated/external code excluded: protobuf files (`*_pb2.py`, `*_pb2_grpc.py`), `competition_api_client`
- Formatter conflicts ignored: COM812, ISC001

**Type Checking:**
- Tool: `ty` (Astral type checker, replaces mypy)
- Pre-commit hook runs `ty check src/` automatically
- Rules: unresolved-import and unresolved-attribute set to "error" or "warn" depending on component

## Import Organization

**Order:**
1. Standard library imports: `logging`, `os`, `uuid`, `dataclasses`, `pathlib`
2. Third-party imports: `redis`, `pydantic`, `fastapi`, `google.protobuf`
3. Local buttercup imports: `from buttercup.common.X`, `from buttercup.orchestrator.X`
4. Relative imports within component: rarely used, mostly absolute imports

**Path Aliases:**
- No path aliases configured; all imports are absolute from `buttercup` root
- Organized by component: `buttercup.common.*`, `buttercup.orchestrator.*`, `buttercup.fuzzing_infra.*`, etc.

**Example Pattern (from scheduler.py):**
```python
import logging
import random
from dataclasses import dataclass, field
from pathlib import Path

from buttercup.common.challenge_task import ChallengeTask
from buttercup.common.datastructures.msg_pb2 import (
    BuildOutput,
    BuildRequest,
)
from buttercup.common.queues import GroupNames, QueueFactory
from redis import Redis

from buttercup.orchestrator.api_client_factory import create_api_client
from buttercup.orchestrator.scheduler.cancellation import Cancellation

logger = logging.getLogger(__name__)
```

## Error Handling

**Patterns:**
- Use `logger.exception()` for caught exceptions with context
- Raise `ValueError` with descriptive messages for invalid arguments: `raise ValueError("group_name must be set for this operation")`
- Try-except blocks guard against specific external failures (e.g., RedisError)
- Example from queues.py:
```python
try:
    # Redis operation
except RedisError as e:
    logger.exception("Redis error occurred: %s", e)
    # Handle or re-raise
```

## Logging

**Framework:** `logging` module standard library

**Patterns:**
- Initialize logger per module: `logger = logging.getLogger(__name__)`
- Use `logger.info()` for informational messages: `logger.info("Initializing telemetry for %s", application_name)`
- Use `logger.warning()` for warnings: `logger.warning("OpenTelemetry is not installed")`
- Use `logger.error()` for errors: `logger.error("OTEL_EXPORTER_OTLP_ENDPOINT not set")`
- Use `logger.exception()` in except blocks to include traceback
- Use string formatting with `%s` and format args, not f-strings: `logger.info("Got %d items", count)`

## Comments

**When to Comment:**
- Comments explain WHY, not WHAT (code should be self-documenting)
- Inline comments for non-obvious logic or important assumptions
- Minimal use; rely on descriptive function/variable names
- Example: `# Shorter timeout for crashes we want to retry builds fairly quickly` above timeout constant

**JSDoc/TSDoc:**
- Python docstrings used for public functions and classes
- Docstring format: Triple-quoted, typically one-liner for simple functions
- Example from scheduler.py:
```python
def update_cached_cancelled_ids(self) -> bool:
    """Update the cached set of cancelled task IDs.

    Retrieves all cancelled task IDs from the registry and stores them in the cached_cancelled_ids set.

    Returns:
        bool: True if there were any cancelled task IDs, False otherwise

    """
```

## Function Design

**Size:** Functions are relatively compact, typically 5-30 lines for core logic

**Parameters:**
- Use type hints consistently: `def func(param: str) -> bool:`
- Use dataclasses for complex parameter groups: `@dataclass class Scheduler: ...`
- Optional parameters with default values: `extra_attributes: dict | None = None`

**Return Values:**
- Type hints on all public functions
- Union types for multiple returns: `Task | None`, `str | Task`
- Return simple values, not wrapped in objects (except when dataclass makes sense)

## Module Design

**Exports:**
- No explicit `__all__` declarations observed; modules export public classes and functions directly
- Private modules/functions use leading underscore: `_ensure_group_name`, `_opentelemetry_enabled`

**Barrel Files:**
- Not used; each module imports directly what it needs
- Deep imports encouraged: `from buttercup.orchestrator.scheduler.scheduler import Scheduler`

**Dataclasses:**
- Preferred over plain classes for data containers
- Use `@dataclass` decorator with type annotations
- Fields with `field(init=False, default=None)` for lazy initialization
- Example from scheduler.py:
```python
@dataclass
class Scheduler:
    tasks_storage_dir: Path
    scratch_dir: Path
    redis: Redis | None = None
    ready_queue: ReliableQueue | None = field(init=False, default=None)
```

**Enums:**
- Use `Enum` for named constants and state values
- String enums inherit from `str` for easy serialization: `class QueueNames(str, Enum):`
- Example from queues.py:
```python
class QueueNames(str, Enum):
    BUILD = "fuzzer_build_queue"
    CRASH = "fuzzer_crash_queue"
```

---

*Convention analysis: 2026-03-10*

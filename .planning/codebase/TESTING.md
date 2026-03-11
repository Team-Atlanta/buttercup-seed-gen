# Testing Patterns

**Analysis Date:** 2026-03-10

## Test Framework

**Runner:**
- pytest 8.3.4+
- Config in each component's `pyproject.toml` under `[tool.pytest.ini_options]`

**Assertion Library:**
- pytest native assertions with `assert` statements
- `dirty-equals` package for flexible matching in common component tests

**Run Commands:**
```bash
# Run all tests in a component
cd <component> && uv run pytest

# Run tests with coverage
cd <component> && uv run pytest --cov

# Run specific test file
cd <component> && uv run pytest tests/test_reliable_queue.py

# Run tests matching pattern
cd <component> && uv run pytest -k "test_queue"

# Run only integration tests (marked with @pytest.mark.integration)
cd <component> && uv run pytest --runintegration

# Skip integration tests (default behavior)
cd <component> && uv run pytest
```

## Test File Organization

**Location:**
- `common/tests/` - Test files separate from source in common component
- `orchestrator/test/` - Some components use `test/` instead of `tests/`
- `patcher/tests/` - Uses `tests/` directory
- `program-model/tests/` - Uses `tests/` directory
- `seed-gen/test/` - Uses `test/` directory
- `fuzzer/` - Tests organized in same structure as common

**Naming:**
- Test files: `test_<module_name>.py`
- Test functions: `test_<functionality_being_tested>()`
- Test fixtures: Named with `@pytest.fixture` decorator

**Structure:**
```
component/
├── tests/                  # or test/
│   ├── conftest.py        # Shared fixtures and pytest hooks
│   ├── test_module1.py
│   ├── test_module2.py
│   └── data/              # Test data files
└── src/
    └── buttercup/
        └── <component>/
```

## Test Structure

**Suite Organization:**

From `common/tests/conftest.py`:
```python
import pytest

def pytest_addoption(parser):
    parser.addoption("--runintegration", action="store_true", default=False, help="run integration tests")

def pytest_configure(config):
    config.addinivalue_line("markers", "integration: mark test as an integration test")

def pytest_collection_modifyitems(config, items):
    if config.getoption("--runintegration"):
        return
    skip_integration = pytest.mark.skip(reason="need --runintegration option to run")
    for item in items:
        if "integration" in item.keywords:
            item.add_marker(skip_integration)
```

**Patterns:**

Setup with fixtures:
```python
@pytest.fixture
def redis_client():
    res = Redis(host="localhost", port=6379, db=15)
    yield res
    res.flushdb()  # Cleanup after test

@pytest.fixture
def reliable_queue(redis_client):
    queue = ReliableQueue[Struct](
        queue_name=QUEUE_NAME,
        group_name=GROUP_NAME,
        redis=redis_client,
        task_timeout_ms=1000,
        msg_builder=Struct,
        reader_name="test_reader",
    )
    yield queue
    redis_client.delete(queue.queue_name)
```

Teardown pattern:
```python
@pytest.fixture
def task_dir(tmp_path: Path) -> Path:
    """Create a mock challenge task directory structure."""
    task_dir = tmp_path / "test-task-id-1"
    task_dir.mkdir(parents=True, exist_ok=True)
    # ... setup code ...
    return task_dir
```

Module-scoped fixtures for expensive resources:
```python
@pytest.fixture(scope="module")
def antlr4_oss_fuzz_task(tmp_path_factory: pytest.TempPathFactory):
    return oss_fuzz_task(
        tmp_path_factory.mktemp("task_dir"),
        "antlr4-java",
        "aixcc-afc",
        # ... parameters ...
    )
```

## Mocking

**Framework:** `unittest.mock` (standard library)

**Patterns:**

Using `@patch` decorator:
```python
class TestBackend(unittest.TestCase):
    @patch("buttercup.orchestrator.task_server.backend.Redis")
    @patch("buttercup.orchestrator.task_server.backend.TaskRegistry")
    def test_get_status_tasks_state(self, mock_task_registry, mock_redis):
        mock_registry = MagicMock()
        mock_registry.__iter__.return_value = mock_tasks
        mock_registry.is_cancelled.side_effect = [True, False, False, False, False]
        mock_task_registry.return_value = mock_registry
        # ... test code ...
```

Using context manager for patch:
```python
with patch("module.path.ClassName", return_value=mock_instance):
    # test code
```

Using `patch.dict` for environment variables:
```python
with patch.dict(os.environ, {"OSS_FUZZ_CONTAINER_ORG": "aixcc-afc"}):
    result = ChallengeTask(...)
```

Using `Mock()` with spec:
```python
@pytest.fixture
def mock_redis():
    return Mock(spec=Redis)

@pytest.fixture
def mock_api_client():
    return Mock()
```

Configuring mock behavior:
```python
mock_registry.is_successful.side_effect = [True, False, False]  # Returns different values per call
queue_factory.create.side_effect = [queue1, queue2, queue3]     # Returns different objects per call
mock_redis.from_url.assert_called_once_with("redis://localhost:6379")  # Verify call
```

**What to Mock:**
- External services: Redis, APIs, HTTP clients
- Database connections
- File I/O operations (use `tmp_path` instead)
- Time-dependent functions
- Expensive network or filesystem operations

**What NOT to Mock:**
- Core business logic being tested
- Internal helper functions in the same module
- Value objects and simple data structures
- Standard library functions like `logging` (test output instead)

## Fixtures and Factories

**Test Data:**

From `patcher/tests/test_utils.py`:
```python
@pytest.fixture
def task_dir(tmp_path: Path) -> Path:
    """Create a mock challenge task directory structure."""
    task_dir = tmp_path / "test-task-id-1"
    task_dir.mkdir(parents=True, exist_ok=True)

    oss_fuzz = task_dir / "fuzz-tooling" / "my-oss-fuzz"
    source = task_dir / "src" / "my-source"

    oss_fuzz.mkdir(parents=True, exist_ok=True)
    source.mkdir(parents=True, exist_ok=True)

    (diffs / "patch1.diff").write_text("mock patch 1")
    (source / "test.txt").write_text("mock test content")

    TaskMeta(...).save(task_dir)

    return task_dir
```

Factory functions for complex objects:
```python
def oss_fuzz_task(
    tmp_path: Path,
    oss_fuzz_project: str,
    oss_fuzz_branch: str,
    project: str,
    project_url: str,
    project_commit: str,
) -> ChallengeTask:
    """Create a challenge task using a real OSS-Fuzz repository."""
    # ... setup code ...
    return ChallengeTask(
        read_only_task_dir=tmp_path,
        local_task_dir=tmp_path,
    )
```

**Location:**
- Fixtures in `tests/conftest.py` (shared across test module)
- Component-specific fixtures: `conftest.py` in same test directory
- Test data files: `tests/data/` or `test/data/` subdirectories

**Fixture Scope:**
- `function` (default): Fresh fixture for each test
- `module`: Shared across all tests in a module (use for expensive setup)
- `session`: Shared across entire test run

Example with module scope:
```python
@pytest.fixture(scope="module")
def antlr4_oss_fuzz_cq(antlr4_oss_fuzz_task: ChallengeTask):
    return CodeQuery(antlr4_oss_fuzz_task)
```

## Coverage

**Requirements:**
- No explicit coverage targets enforced in config
- `pytest-cov` package available for measurement
- Coverage config in `pyproject.toml`:
```
[tool.coverage.run]
source = ["src/buttercup"]
omit = ["*/tests/*", "*/__cli__.py", "*/_cli.py"]

[tool.coverage.report]
exclude_lines = [
    "pragma: no cover",
    "def __repr__",
    "if __name__ == .__main__.:",
    "raise NotImplementedError",
    "if TYPE_CHECKING:",
]
```

**View Coverage:**
```bash
cd <component> && uv run pytest --cov --cov-report=html
# Coverage report in htmlcov/index.html
```

## Test Types

**Unit Tests:**
- Scope: Individual functions or classes
- Approach: Mock external dependencies, test behavior in isolation
- Example: `test_reliable_queue_push_pop()` tests queue operations with mocked Redis
- Location: Same directory as code, named `test_<module>.py`

**Integration Tests:**
- Scope: Multiple components working together
- Approach: Use real Redis connection, file system, or other real services
- Marked with `@pytest.mark.integration`
- Run with `pytest --runintegration`
- Example: `program-model/tests/conftest.py` has fixtures that clone real git repos
- Location: Same test files but marked with marker

**E2E Tests:**
- Not heavily used; system runs on Kubernetes in deployment
- Deployment-level testing via `make send-integration-task`
- Scripts in `orchestrator/scripts/` for manual testing

## Common Patterns

**Async Testing:**

From `orchestrator/pyproject.toml`:
```
[tool.pytest.ini_options]
asyncio_default_fixture_loop_scope = "function"
```

With `pytest-asyncio`:
```python
@pytest.mark.asyncio
async def test_async_function():
    result = await some_async_function()
    assert result == expected
```

**Error Testing:**

Using `pytest.raises` context manager:
```python
def test_invalid_group_name():
    factory = QueueFactory(redis_client)
    with pytest.raises(ValueError):
        factory.create(QueueNames.BUILD_OUTPUT, "invalid_group")
```

**Time-dependent Testing:**

Real sleep for time-sensitive operations:
```python
def test_autoclaim(reliable_queue, redis_client):
    item = reliable_queue.pop()
    assert item is not None
    msg_id = item.item_id

    time.sleep(2)  # Wait for timeout

    queue = ReliableQueue[Struct](...)
    item = queue.pop()
    assert item is not None
    assert item.item_id == msg_id  # Should be autoclaimed
```

**Multiple Assertions:**

Chain assertions in single test:
```python
def test_reliable_queue_push_pop(reliable_queue):
    test_msg = Struct()
    test_msg.update({"test_key": "test_value"})

    reliable_queue.push(test_msg)
    assert reliable_queue.size() == 1

    result = reliable_queue.pop()
    assert isinstance(result, RQItem)
    assert isinstance(result.deserialized, Struct)
    assert result.deserialized.fields["test_key"].string_value == "test_value"
```

---

*Testing analysis: 2026-03-10*

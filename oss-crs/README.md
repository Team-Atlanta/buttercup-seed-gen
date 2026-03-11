# Buttercup Seed-Gen Standalone

## Overview

Buttercup Seed-Gen Standalone is a slimmed-down seed generation service extracted from the full Buttercup CRS. It generates targeted test inputs and submits them directly to the competition API.

**Key characteristics:**
- **4 services** (redis, orchestrator, coverage-bot, seed-gen)
- **No fuzzing:** This is NOT a vulnerability discovery tool
- **Seed-only workflow:** Generates intelligent corpus inputs via LLM analysis

**What this does:**
- Downloads build artifacts from competition API
- Analyzes code structure using CodeQuery
- Generates targeted seed inputs using LLM
- Submits seeds to competition API for coverage

**What this does NOT do:**
- Vulnerability discovery (fuzzer-bot removed)
- POV generation or submission
- Crash analysis or triage

## Architecture

### Services (4 total)

| Service | Container | Purpose |
|---------|-----------|---------|
| **redis** | redis.Dockerfile | Message broker for service coordination |
| **orchestrator** | buttercup-runner.Dockerfile | Populates Redis with build artifacts and harness weights |
| **coverage-bot** | buttercup-runner.Dockerfile | Measures coverage metrics from corpus inputs |
| **seed-gen** | buttercup-runner.Dockerfile | LLM-powered seed generation |

**Removed:** fuzzer-bot (no longer needed for seed-only workflow)

### Data Flow

```
1. libCRS downloads build artifacts
   - task (compiled binaries)
   - task-coverage (coverage instrumented build)
   - cqdb (CodeQuery database)
        |
        v
2. Orchestrator registers builds in Redis
   - BuildMap: Task metadata
   - HarnessWeights: Harness selection weights
        |
        v
3. Seed-gen generates seeds via LLM analysis
   - Reads code structure from cqdb
   - Generates targeted inputs
   - Writes to /artifacts/corpus/
        |
        v
4. libCRS watcher submits seeds
   - Monitors /artifacts/corpus/
   - Submits new seeds to Competition API
        |
        v
5. Coverage-bot measures coverage
   - Runs corpus inputs through instrumented build
   - Populates CoverageMap in Redis
```

### Service Routing

The `buttercup_entrypoint` script routes to services via `RUN_TYPE` environment variable:

| RUN_TYPE | Service | Entry Point |
|----------|---------|-------------|
| `redis` | Redis server | `redis-server` |
| `orchestrator` | Orchestrator | `python /crs/orchestrator.py` |
| `coverage` | Coverage Bot | `buttercup-coverage-bot` |
| `seedgen` | Seed Generator | `seed-gen server` |

## Deployment

### Using crs-compose (Recommended)

This deployment uses `crs-compose` from the oss-crs-2 repository.

#### Prerequisites

- Docker installed and running
- oss-crs-2 repository cloned
- oss-fuzz repository available

#### Prepare

```bash
cd $OSS_CRS
uv run crs-compose prepare \
    --compose-file ./example_configs/buttercup-scan/buttercup-compose.yaml
```

#### Build Target

```bash
cd $OSS_CRS
uv run crs-compose build-target \
    --compose-file ./example_configs/buttercup-scan/buttercup-compose.yaml \
    --target-proj-path $OSS_FUZZ/projects/libxml2
```

#### Run (with LLM)

```bash
export ANTHROPIC_API_KEY=<your-key>
export OPENAI_API_KEY=<your-key>
cd $OSS_CRS
uv run crs-compose run \
    --compose-file ./example_configs/buttercup-scan/buttercup-compose.yaml \
    --target-proj-path $OSS_FUZZ/projects/libxml2 \
    --target-harness xml
```

#### Run (without LLM)

For testing infrastructure without LLM API costs:

```bash
cd $OSS_CRS
uv run crs-compose run \
    --compose-file ./example_configs/buttercup-scan/buttercup-compose-nollm.yaml \
    --target-proj-path $OSS_FUZZ/projects/libxml2 \
    --target-harness xml
```

### Environment Variables

| Variable | Purpose | Required |
|----------|---------|----------|
| `ANTHROPIC_API_KEY` | Anthropic Claude API key | For LLM seeds |
| `OPENAI_API_KEY` | OpenAI API key | For LLM seeds |
| `OSS_CRS_LLM_API_URL` | Custom LiteLLM proxy URL | Optional |
| `OSS_CRS_LLM_API_KEY` | Custom LiteLLM proxy key | Optional |

## Configuration Files

### crs.yaml

Defines the 4-service architecture:

```yaml
crs_run_phase:
  redis:
    dockerfile: oss-crs/dockerfiles/redis.Dockerfile
  orchestrator:
    dockerfile: oss-crs/dockerfiles/buttercup-runner.Dockerfile
    additional_env:
      RUN_TYPE: orchestrator
  coverage-bot:
    dockerfile: oss-crs/dockerfiles/buttercup-runner.Dockerfile
    additional_env:
      RUN_TYPE: coverage
  seed-gen:
    dockerfile: oss-crs/dockerfiles/buttercup-runner.Dockerfile
    additional_env:
      RUN_TYPE: seedgen
```

### buttercup_entrypoint

Located at `bin/buttercup_entrypoint`. Routes service execution based on `RUN_TYPE`:
- Downloads build artifacts via libCRS
- Sets up Redis connection
- Maps LLM environment variables
- Registers seed submission directory

### buttercup-runner.Dockerfile

Multi-service container image that includes:
- Python runtime with buttercup packages
- seed-gen CLI
- coverage-bot CLI
- Redis client libraries

## Development

### Running Tests

```bash
cd seed-gen && uv run pytest
```

### Running Tests with Coverage

```bash
cd seed-gen && uv run pytest --cov
```

### Linting

```bash
make lint-component COMPONENT=seed-gen
```

### Key Test Areas

| Test Module | Purpose |
|-------------|---------|
| `test_seed_gen_bot.py` | Task sampling (SEED_INIT, SEED_EXPLORE only) |
| `test_seed_init.py` | Initial seed generation logic |
| `test_seed_explore.py` | Exploration seed generation logic |
| `test_task_counter.py` | Task counting and selection |

## Verifying Deployment

### Check Running Services

```bash
docker ps --filter "name=crs-run"
# Expected: 4 containers (redis, orchestrator, coverage-bot, seed-gen)
# Note: orchestrator exits after populating Redis
```

### Check Redis Data Structures

```bash
CONTAINER=$(docker ps --filter "name=crs-run" -q | head -1)

# Verify orchestrator populated Redis
docker exec $CONTAINER redis-cli KEYS "BuildMap:*"
docker exec $CONTAINER redis-cli KEYS "HarnessWeights:*"

# Verify coverage-bot populated CoverageMap
docker exec $CONTAINER redis-cli KEYS "CoverageMap:*"
```

### Check Seed Generation

```bash
# Check corpus directory for seeds
docker exec $CONTAINER ls -la /artifacts/corpus/
# Expected: Files with SHA256 hash names

# Check libCRS submission log
docker exec $CONTAINER cat /tmp/seed_submit.log
# Expected: "Submitted seed" messages
```

### Stopping the System

```bash
pkill -f "crs-compose run"
```

**Important:** Always stop via `pkill`, not `docker stop`. The process handles cleanup automatically.

## Migration Notes

### What Was Removed

| Component | Description |
|-----------|-------------|
| **fuzzer-bot service** | Automated fuzzing and crash detection |
| **VULN_DISCOVERY task type** | Task type for vulnerability discovery runs |
| **POV submission** | Proof-of-vulnerability submission infrastructure |
| **Crash queue/set** | Redis structures for crash tracking |
| **Crash directory monitoring** | File watchers for crash artifacts |

### What Remains

| Component | Description |
|-----------|-------------|
| **SEED_INIT task** | Initial seed generation from code analysis |
| **SEED_EXPLORE task** | Exploration seed generation from coverage |
| **Coverage metrics** | Full coverage measurement infrastructure |
| **Redis coordination** | All service coordination via Redis |
| **libCRS submission** | Automatic seed submission to competition API |

### Task Distribution

After removal of VULN_DISCOVERY, task sampling probabilities are:

| Task Type | Probability | Description |
|-----------|-------------|-------------|
| SEED_INIT | 5% | Code-aware initial seed generation |
| SEED_EXPLORE | 95% | Coverage-guided exploration seeds |

## Troubleshooting

### "No weighted harnesses found"

**Cause:** Orchestrator hasn't populated Redis yet.
**Solution:** Wait for orchestrator to complete. Check its exit status - should be "Exited (0)".

### Seeds not submitting

**Cause:** libCRS watcher process died.
**Solution:** Check `/tmp/seed_submit.log` for errors. Verify the register-submit-dir process is running:
```bash
docker exec $CONTAINER ps aux | grep libCRS
```

### Coverage-bot shows zero coverage

**Cause:** Empty corpus directory.
**Solution:** Wait for seed-gen to produce seeds. Verify `/artifacts/corpus/` is not empty.

### Redis connection refused

**Cause:** Redis container not ready or network issue.
**Solution:** The entrypoint waits up to 60 seconds for Redis. Check Redis container logs.

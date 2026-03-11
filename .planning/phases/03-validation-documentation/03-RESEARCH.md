# Phase 3: Validation & Documentation - Research

**Researched:** 2026-03-10
**Domain:** Integration testing, deployment validation, technical documentation
**Confidence:** HIGH

## Summary

Phase 3 validates that the standalone seed-gen deployment works end-to-end after the service removal (Phase 1) and code cleanup (Phase 2). The research confirms that all necessary validation infrastructure already exists - pytest test suite with 82 tests for seed-gen, crs-compose tooling for deployment testing, and libCRS CLI for submission verification. The primary challenge is not technical capability but orchestration - ensuring the four services (redis, orchestrator, coverage-bot, seed-gen) coordinate correctly without fuzzer-bot, and documenting the new architecture so future developers understand the standalone seed-only pattern.

**Primary recommendation:** Use a three-phase validation approach - (1) unit test verification that code changes are correct, (2) integration test using crs-compose run with a test target to verify end-to-end deployment, (3) documentation of the standalone architecture with explicit "no fuzzer" callouts.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CODE-05 | Verify libCRS seed submission continues working (already implemented) | libCRS register-submit-dir mechanism verified in entrypoint (line 125), directory watching pattern established, submission logs at /tmp/seed_submit.log |
| VAL-01 | Services deploy successfully with slimmed configuration | crs-compose prepare/run tooling provides deployment mechanism, crs.yaml already validated for 4-service configuration in Phase 1 |
| VAL-02 | Seedgen generates and submits seeds via libCRS | Existing test suite (82 tests) validates generation logic, integration test with real target verifies submission path |
| VAL-03 | Coverage-bot runs without fuzzer-bot dependency | Coverage-bot entrypoint shows no fuzzer dependencies (line 113-120), only requires corpus and Redis CoverageMap |
</phase_requirements>

## Standard Stack

### Core Testing Infrastructure
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| pytest | ~8.3.4 | Unit and integration testing | Python testing standard, already in use across all components |
| pytest-asyncio | ~0.25.2 | Async test support | Required for Redis and LLM mocking in seed-gen tests |
| pytest-cov | ~6.0.0 | Code coverage measurement | Standard coverage tool, integrated with pytest |
| uv | latest | Python environment management | Fast, reliable, already used for all component dependency management |

### Deployment & Validation Tools
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| crs-compose | latest | CRS deployment orchestration | Integration testing - deploy all 4 services with real target |
| libCRS CLI | competition version | Competition API client | Verify seed submission path and download build artifacts |
| kubectl | 1.28+ | Kubernetes inspection (if using full deployment) | Check pod status for cloud deployments (not needed for local crs-compose) |
| docker | 20.10+ | Container runtime | Build buttercup-runner.Dockerfile and run services |

### Documentation Standards
| Tool | Purpose | Format |
|------|---------|--------|
| Markdown | Technical documentation | README.md with architecture diagrams as ASCII or mermaid |
| CLAUDE.md | AI assistant guidance | Structured sections for architecture, commands, patterns |

**Installation:**
```bash
# Test infrastructure (already present in seed-gen/pyproject.toml)
cd seed-gen && uv sync --group dev

# Deployment tools (already available in project)
# crs-compose: check oss-crs-2 repository
# libCRS: provided by competition infrastructure
# docker: system package manager
```

## Architecture Patterns

### Recommended Validation Structure
```
.planning/phases/03-validation-documentation/
├── 03-RESEARCH.md           # This file
├── 03-01-PLAN.md            # Unit test verification
├── 03-02-PLAN.md            # Integration deployment test
└── 03-03-PLAN.md            # Documentation update
```

### Pattern 1: Unit Test Verification (Pre-Integration)
**What:** Run existing test suite to verify code changes didn't break seed generation logic
**When to use:** Before attempting integration tests - catch regressions early
**Example:**
```bash
# Run seed-gen test suite
cd seed-gen && uv run pytest

# Expected: All 82 tests pass
# Focus areas:
# - test_seed_gen_bot.py: Verify task sampling excludes vuln-discovery
# - test_task_counter.py: Verify task counting logic intact
# - test_seed_init.py: Verify seed generation logic works
# - test_seed_explore.py: Verify exploration tasks work
```

### Pattern 2: Integration Test with crs-compose
**What:** Deploy all 4 services with a real test target and verify end-to-end workflow
**When to use:** After unit tests pass - validate service coordination
**Example:**
```bash
# From oss-crs-2 directory (skill: run-oss-crs)
cd $OSS_CRS

# Prepare environment
uv run crs-compose prepare \
    --compose-file ./example_configs/buttercup-scan/buttercup-compose.yaml

# Build test target (libxml2 or json-c)
uv run crs-compose build-target \
    --compose-file ./example_configs/buttercup-scan/buttercup-compose.yaml \
    --target-proj-path $OSS_FUZZ/projects/libxml2

# Run seed-gen (no LLM needed for validation)
uv run crs-compose run \
    --compose-file ./example_configs/buttercup-scan/buttercup-compose-nollm.yaml \
    --target-proj-path $OSS_FUZZ/projects/libxml2 \
    --target-harness xml

# Success indicators:
# 1. All 4 containers start (redis, orchestrator, coverage-bot, seed-gen)
# 2. No fuzzer-bot container appears
# 3. Seeds appear in /artifacts/corpus/ (docker exec to check)
# 4. libCRS submission log shows activity: /tmp/seed_submit.log
# 5. Coverage-bot populates CoverageMap (check Redis keys)
```

### Pattern 3: Service Coordination Verification
**What:** Verify Redis-mediated communication works without fuzzer-bot
**When to use:** During integration test - validate data flow
**Example:**
```bash
# Check Redis data structures populated correctly
CONTAINER=$(docker ps --filter "name=crs-run" -q | head -1)

# Verify orchestrator populated Redis
docker exec $CONTAINER redis-cli KEYS "BuildMap:*"
docker exec $CONTAINER redis-cli KEYS "HarnessWeights:*"

# Verify coverage-bot populated CoverageMap
docker exec $CONTAINER redis-cli KEYS "CoverageMap:*"

# Check seed-gen corpus output
docker exec $CONTAINER ls -la /artifacts/corpus/
# Expected: Hash-named seed files (SHA256 filenames)

# Check libCRS submission log
docker exec $CONTAINER cat /tmp/seed_submit.log
# Expected: "Submitted seed" or similar confirmation messages
```

### Pattern 4: README Documentation Structure
**What:** Document standalone architecture with explicit fuzzer removal
**When to use:** After integration tests pass - codify the validated architecture
**Example structure:**
```markdown
# Buttercup Seed-Gen Standalone

## Overview
Slimmed-down seed generation service without fuzzing infrastructure.
Generates targeted test inputs and submits directly to competition API.

## Architecture

### Services (4 total)
- **redis**: Message broker for service coordination
- **orchestrator**: Populates Redis with build artifacts
- **coverage-bot**: Measures coverage metrics
- **seed-gen**: Generates seeds via LLM analysis

**Removed:** fuzzer-bot (no longer needed for seed-only workflow)

### Data Flow
1. libCRS downloads build artifacts (task, task-coverage, cqdb)
2. Orchestrator registers builds in Redis (BuildMap, HarnessWeights)
3. Coverage-bot measures coverage → Redis CoverageMap
4. Seed-gen generates seeds → /artifacts/corpus/
5. libCRS watcher submits seeds → Competition API

## Deployment

### Using crs-compose (recommended)
[Commands from crs-compose pattern above]

### Configuration
- **crs.yaml**: 4-service definition
- **buttercup_entrypoint**: RUN_TYPE routing (redis|orchestrator|coverage|seedgen)
- **buttercup-runner.Dockerfile**: Multi-service container

## Development

### Running Tests
cd seed-gen && uv run pytest

### Validating Deployment
[Integration test commands]

## Migration Notes

**What Changed:**
- Removed fuzzer-bot service
- Removed vuln-discovery task type
- Removed POV submission logic
- Removed crash queue infrastructure

**What Stayed:**
- Seed generation (SEED_INIT, SEED_EXPLORE)
- Coverage-bot for metrics
- Redis coordination
- libCRS submission mechanism
```

### Anti-Patterns to Avoid

- **Documenting fuzzer features:** Do NOT include fuzzer-bot in architecture diagrams or command examples - creates confusion about current capabilities
- **Skipping smoke test:** Do NOT assume deployment works without running crs-compose - service coordination failures only surface at runtime
- **Ignoring submission logs:** Do NOT validate without checking /tmp/seed_submit.log - seeds might generate but not submit
- **Testing with LLM:** Do NOT require LLM API keys for validation - use buttercup-compose-nollm.yaml to validate infrastructure without LLM costs

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Integration test runner | Custom deployment script | crs-compose run | Already handles container orchestration, libCRS coordination, environment setup |
| Unit test framework | Custom test harness | pytest with existing fixtures | 82 tests already written, fixtures mock Redis/LLM/file system |
| Seed submission verification | Custom API client | libCRS register-submit-dir + log monitoring | Competition standard, handles retries and batching |
| Service health checks | Custom polling script | Docker logs + Redis key inspection | Native tools, no additional dependencies |

**Key insight:** All validation infrastructure already exists. Phase 3 is about orchestration and documentation, not building new tooling.

## Common Pitfalls

### Pitfall 1: Service Start Order Dependencies
**What goes wrong:** Seed-gen or coverage-bot starts before orchestrator populates Redis, leading to "no harnesses found" errors
**Why it happens:** Docker Compose starts services in parallel, Redis data structures initially empty
**How to avoid:** Orchestrator runs synchronously and exits, other services loop and wait for Redis data
**Warning signs:** Container logs show "No weighted harnesses found" or "BuildMap empty"
**Detection:** Check orchestrator container status - should be "Exited (0)" not "Running"

### Pitfall 2: Corpus Directory Confusion
**What goes wrong:** Seeds generated but not submitted because corpus directory not monitored
**Why it happens:** Multiple corpus paths exist - /artifacts/corpus/ (submission), /artifacts/<task_id>/corpus_<harness>/ (generation)
**How to avoid:** Verify libCRS register-submit-dir targets /artifacts/corpus/ and seed-gen writes to same location
**Warning signs:** Seeds in task-specific directories but not in /artifacts/corpus/
**Detection:** `docker exec $CONTAINER ls -la /artifacts/corpus/` should show hash-named files

### Pitfall 3: Coverage-Bot Corpus Dependency
**What goes wrong:** Coverage-bot runs but reports zero coverage or crashes
**Why it happens:** Expects corpus inputs to run harnesses against, sparse corpus from seed-gen-only
**How to avoid:** Accept lower initial coverage baseline, ensure seed-gen writes ALL generated seeds to corpus
**Warning signs:** CoverageMap empty in Redis, coverage-bot logs show "No corpus files found"
**Detection:** Check /artifacts/corpus/ has seeds before coverage-bot runs

### Pitfall 4: libCRS Submission Silent Failures
**What goes wrong:** Seeds generate, appear in corpus directory, but never reach competition API
**Why it happens:** libCRS watcher background process dies silently, no automatic restart
**How to avoid:** Always check /tmp/seed_submit.log for "Submitted" messages, verify libCRS process running
**Warning signs:** Corpus fills up but submission log stops updating
**Detection:** `docker exec $CONTAINER ps aux | grep libCRS` should show register-submit-dir process

### Pitfall 5: Test Suite Passes But Integration Fails
**What goes wrong:** All 82 unit tests pass but deployment doesn't work
**Why it happens:** Unit tests mock Redis/filesystem, integration issues only surface with real services
**How to avoid:** ALWAYS run integration test with crs-compose after unit test success
**Warning signs:** False confidence from green test suite
**Detection:** Unit tests are necessary but not sufficient - integration test is mandatory

## Code Examples

Verified patterns from existing codebase:

### Checking Service Status
```bash
# Source: CLAUDE.md deployment patterns
# Check all containers running
docker ps --filter "name=crs-run"

# Expected: 4 containers (redis, orchestrator, coverage-bot, seed-gen)
# orchestrator should show "Exited (0)" status after populating Redis

# Check specific service logs
CONTAINER=$(docker ps --filter "name=crs-run" -q | head -1)
docker logs $CONTAINER 2>&1 | tail -50
```

### Verifying Redis Coordination
```bash
# Source: common/src/buttercup/common/maps.py data structures
REDIS_CONTAINER=$(docker ps --filter "name=crs-run" -q | head -1)

# Check BuildMap (orchestrator output)
docker exec $REDIS_CONTAINER redis-cli KEYS "BuildMap:*"
# Expected: Keys with task_id

# Check HarnessWeights (orchestrator output)
docker exec $REDIS_CONTAINER redis-cli KEYS "HarnessWeights:*"
# Expected: Keys for each harness

# Check CoverageMap (coverage-bot output)
docker exec $REDIS_CONTAINER redis-cli KEYS "CoverageMap:*"
# Expected: Keys populated after coverage-bot runs
```

### Inspecting Seed Generation
```bash
# Source: oss-crs/bin/buttercup_entrypoint corpus setup
CONTAINER=$(docker ps --filter "name=crs-run" -q | head -1)

# Check corpus directory for seeds
docker exec $CONTAINER ls -la /artifacts/corpus/
# Expected: Files with SHA256 hash names (e.g., a1b2c3d4...xyz)

# Check libCRS submission log
docker exec $CONTAINER cat /tmp/seed_submit.log
# Expected: Timestamp + "Submitted seed" messages

# Count generated seeds
docker exec $CONTAINER bash -c "ls -1 /artifacts/corpus/ | wc -l"
# Expected: Non-zero count after seed-gen runs
```

### Running Test Suite
```bash
# Source: seed-gen/pyproject.toml pytest configuration
cd /home/andrew/post/buttercup-bugfind/seed-gen

# Run all tests
uv run pytest

# Run specific test module
uv run pytest test/test_seed_gen_bot.py -v

# Run with coverage
uv run pytest --cov

# Expected output:
# - 82 tests collected
# - All tests pass
# - No crash/vuln-discovery references in failures
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual service coordination | crs-compose orchestration | OSS-CRS 2.0 | Simpler deployment, less error-prone |
| Separate fuzzer/seedgen tools | Integrated seed-gen standalone | This project (Phase 1-2) | Lighter deployment, focused capability |
| Manual corpus sync | libCRS directory watching | Competition standard | Automatic submission, no custom code |
| Docker Compose | crs-compose YAML | OSS-CRS 2.0 | Better multi-stage build support |

**Deprecated/outdated:**
- **Fuzzer-bot service:** Removed in Phase 1, no longer part of architecture
- **Vuln-discovery tasks:** Removed in Phase 2, task distribution now SEED_INIT + SEED_EXPLORE only
- **POV submission:** Removed in Phase 2, only seed submission remains
- **Manual libCRS registration:** Historical approach, now automated in entrypoint

## Open Questions

1. **Coverage baseline expectations**
   - What we know: Coverage-bot will receive fewer corpus inputs (seed-gen only, no fuzzer contributions)
   - What's unclear: Expected coverage percentage drop, whether this impacts seed-gen effectiveness
   - Recommendation: Measure baseline coverage with integration test, document in README as "expected behavior for seed-only mode"

2. **LLM requirement for validation**
   - What we know: buttercup-compose-nollm.yaml exists for non-LLM deployment
   - What's unclear: Can seed-gen operate without LLM at all, or will it fail to generate seeds
   - Recommendation: Use nollm config for infrastructure validation, test basic functionality. Full validation with LLM optional but recommended for completeness

3. **Integration test target selection**
   - What we know: libxml2 and json-c are standard test targets in run-oss-crs skill
   - What's unclear: Which target is fastest/most reliable for validation purposes
   - Recommendation: Use libxml2 (smaller, faster build) for quick validation, json-c as alternative if libxml2 issues

4. **Documentation location**
   - What we know: Main README.md documents full Buttercup CRS, may confuse standalone users
   - What's unclear: Should standalone docs live in oss-crs/README.md or separate file
   - Recommendation: Create oss-crs/README.md specifically for standalone deployment, add pointer from main README.md

## Validation Architecture

> Nyquist validation enabled per .planning/config.json

### Test Framework
| Property | Value |
|----------|-------|
| Framework | pytest 8.3.4 |
| Config file | seed-gen/pyproject.toml (tool.pytest.ini_options) |
| Quick run command | `cd seed-gen && uv run pytest -x` |
| Full suite command | `cd seed-gen && uv run pytest --cov` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CODE-05 | libCRS seed submission works | integration | Manual: crs-compose run + log inspection | ❌ Wave 0 |
| VAL-01 | 4 services deploy successfully | integration | Manual: crs-compose run + docker ps check | ❌ Wave 0 |
| VAL-02 | Seeds generated and submitted | integration | Manual: check /artifacts/corpus/ and /tmp/seed_submit.log | ❌ Wave 0 |
| VAL-03 | Coverage-bot runs without fuzzer | integration | Manual: check Redis CoverageMap + coverage-bot logs | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `cd seed-gen && uv run pytest -x` (fail-fast unit tests)
- **Per wave merge:** `cd seed-gen && uv run pytest` (full unit suite)
- **Phase gate:** Integration test with crs-compose before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] Integration test script `tests/integration/test_standalone_deployment.sh` — covers VAL-01, VAL-02, VAL-03
  - Runs crs-compose prepare/build/run
  - Checks all 4 services start (VAL-01)
  - Verifies seeds in /artifacts/corpus/ (VAL-02)
  - Verifies Redis CoverageMap populated (VAL-03)
  - Verifies libCRS submission log (CODE-05)
- [ ] README.md validation section — documents expected outcomes

**Note:** Integration tests are manual because they require:
- oss-crs-2 repository available at $OSS_CRS
- oss-fuzz repository available at $OSS_FUZZ
- Docker daemon running
- ~5-10 minutes execution time (too slow for per-commit)

Automation deferred to CI/CD pipeline, manual execution documented in PLAN.md.

## Sources

### Primary (HIGH confidence)
- Codebase analysis:
  - `/home/andrew/post/buttercup-bugfind/oss-crs/crs.yaml` - 4-service configuration
  - `/home/andrew/post/buttercup-bugfind/oss-crs/bin/buttercup_entrypoint` - libCRS registration (line 125)
  - `/home/andrew/post/buttercup-bugfind/seed-gen/test/` - 82 existing tests, pytest configuration
  - `/home/andrew/post/buttercup-bugfind/seed-gen/pyproject.toml` - Test framework setup
  - `/home/andrew/post/buttercup-bugfind/.planning/research/SUMMARY.md` - Architectural research from project initiation
  - `/home/andrew/post/buttercup-bugfind/.claude/skills/run-oss-crs/SKILL.md` - crs-compose usage patterns
  - `/home/andrew/post/buttercup-bugfind/.planning/phases/01-service-configuration-removal/01-01-SUMMARY.md` - Phase 1 completion artifacts
  - `/home/andrew/post/buttercup-bugfind/.planning/phases/02-code-cleanup/02-02-SUMMARY.md` - Phase 2 completion artifacts

### Secondary (MEDIUM confidence)
- Project documentation:
  - `/home/andrew/post/buttercup-bugfind/CLAUDE.md` - Development commands and debugging patterns
  - `/home/andrew/post/buttercup-bugfind/README.md` - Full Buttercup deployment patterns
  - `/home/andrew/post/buttercup-bugfind/deployment/README.md` - Kubernetes deployment (not used for oss-crs)

### Tertiary (LOW confidence - not used)
- None - all research based on codebase analysis and established project patterns

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - pytest already in use, crs-compose observed in skill, all tools present
- Architecture patterns: HIGH - validated against existing Phase 1 & 2 work, integration patterns from run-oss-crs skill
- Pitfalls: HIGH - derived from microservices coordination research and observed entrypoint/service dependencies
- Validation approach: HIGH - test suite exists (82 tests), crs-compose deployment tested in skill documentation

**Research date:** 2026-03-10
**Valid until:** 2026-04-10 (30 days - stable deployment patterns, no fast-moving dependencies)

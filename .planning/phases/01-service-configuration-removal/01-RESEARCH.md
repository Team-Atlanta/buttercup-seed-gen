# Phase 1: Service & Configuration Removal - Research

**Researched:** 2026-03-10
**Domain:** Microservices configuration removal and Docker multi-stage build optimization
**Confidence:** HIGH

## Summary

Phase 1 removes fuzzer-bot service from the Buttercup OSS-CRS deployment by modifying three configuration files: crs.yaml (service definitions), buttercup_entrypoint (runtime routing), and buttercup-runner.Dockerfile (multi-stage build). The work is straightforward configuration editing with minimal risk because the architecture already uses loose coupling through Redis - removing fuzzer-bot doesn't break API contracts between remaining services.

The critical insight is that this is a **subtraction problem, not an addition problem**. No new technologies are needed, no dependencies need to be added, and the seed submission mechanism via libCRS is already fully implemented. The primary risk is incomplete removal leaving dead code in the Docker image (fuzzer-builder stage occupies ~200MB of unused dependencies).

**Primary recommendation:** Remove all three artifacts atomically in a single plan to avoid configuration drift. Validate by building the Docker image and verifying only four services start (redis, orchestrator, coverage-bot, seed-gen).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SVC-01 | Remove fuzzer-bot service from crs.yaml | YAML service definition removal (lines 33-36) |
| SVC-02 | Keep redis service for inter-service communication | Redis proven essential for BuildMap, HarnessWeights, CoverageMap |
| SVC-03 | Keep orchestrator service for Redis population from build artifacts | Orchestrator populates Redis from disk artifacts, required by all bots |
| SVC-04 | Keep coverage-bot service for coverage metrics | Coverage-bot measures code coverage to guide seed-gen targeting |
| SVC-05 | Keep seed-gen service with modified task selection | Seed-gen generates inputs and submits via libCRS (already working) |
| CODE-02 | Remove fuzzer case from buttercup_entrypoint script | Entrypoint routing lines 113-129 must be deleted |
| CLN-01 | Remove fuzzer build stages from Dockerfile (dead code) | Fuzzer-builder stage lines 38-65, COPY commands 121-122, PATH update line 133 |

</phase_requirements>

## Standard Stack

All technologies are already in use and observed in the codebase. No new installations or dependencies required.

### Core Technologies
| Technology | Current Version | Purpose | Why Standard |
|------------|-----------------|---------|--------------|
| YAML | 1.2 | Service configuration (crs.yaml) | libCRS competition framework requirement |
| Bash | 4.4+ | Entrypoint script routing | Standard container initialization pattern |
| Docker multi-stage builds | 20.10+ | Service isolation | Single Dockerfile, multiple services via RUN_TYPE routing |
| libCRS CLI | (competition-provided) | Competition API integration | AIxCC Finals infrastructure requirement |
| Redis | 7.x | Message broker and shared state | Proven pattern for microservices coordination |

### Supporting Tools
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| docker buildx bake | 0.18+ | Multi-target builds | Build buttercup-runner image from docker-bake.hcl |
| uv | 0.5.20 | Python dependency management | Already used in Dockerfile for venv creation |
| pytest | 8.3.4 | Test runner | Validate no regressions in retained services |
| ruff | 0.14.0 | Linting | Verify code quality after changes |

### Installation

No new installations needed. All tools already present in project.

```bash
# Verify current setup
docker buildx version  # Multi-stage build support
docker version | grep Version  # Should be 20.10+
redis-cli --version  # Verify Redis client available

# Build modified image
docker buildx bake -f oss-crs/docker-bake.hcl
```

## Architecture Patterns

### Current Service Architecture (Before Phase 1)

```
crs.yaml defines 5 services:
├── redis (infrastructure)
├── orchestrator (coordinator)
├── fuzzer-bot (TO BE REMOVED)
├── coverage-bot (retained)
└── seed-gen (retained)

All services built from buttercup-runner.Dockerfile:
├── fuzzer-builder stage → /app/fuzzer/.venv (dead code after removal)
├── seedgen-builder stage → /app/seed-gen/.venv (retained)
└── runtime stage with RUN_TYPE routing via entrypoint
```

### Target Service Architecture (After Phase 1)

```
crs.yaml defines 4 services:
├── redis (infrastructure)
├── orchestrator (coordinator)
├── coverage-bot (retained)
└── seed-gen (retained)

Dockerfile simplified:
├── seedgen-builder stage → /app/seed-gen/.venv (retained)
├── cscope-builder stage → /usr/local/bin/cscope (retained, needed by seed-gen)
└── runtime stage with RUN_TYPE routing (fuzzer case removed)
```

### Pattern 1: Multi-Stage Docker Build for Service Selection

**What:** Single Dockerfile builds multiple services, runtime selection via environment variable

**When to use:** Microservices sharing common base dependencies but different application logic

**Example from buttercup-runner.Dockerfile:**
```dockerfile
# Build stage creates service-specific venv
FROM base-image AS seedgen-builder
WORKDIR /app
RUN cd seed-gen && uv sync --frozen --no-editable

# Runtime stage copies all venvs, selects via PATH and entrypoint
FROM runner-base AS runtime
COPY --from=seedgen-builder /app/seed-gen/.venv /app/seed-gen/.venv
ENV PATH=/app/seed-gen/.venv/bin:$PATH
ENTRYPOINT ["/usr/local/bin/buttercup_entrypoint"]
```

**Modification pattern for removal:**
1. Delete unused builder stage entirely (fuzzer-builder lines 38-65)
2. Remove COPY commands for deleted stage (lines 121-122)
3. Update PATH environment variable to remove deleted venv (line 133)
4. Verify docker-bake.hcl doesn't reference deleted stage (currently only targets "base")

### Pattern 2: Entrypoint Script Routing

**What:** Bash script routes to different service executables based on RUN_TYPE environment variable

**When to use:** Container needs to support multiple service types from single image

**Example from buttercup_entrypoint:**
```bash
case "$RUN_TYPE" in
    redis)
        exec redis-server --save "" --appendonly no
        ;;
    seedgen)
        libCRS register-submit-dir seed "$CORPUS_DIR" --log /tmp/seed_submit.log &
        export BUTTERCUP_SEED_GEN_SERVER__REDIS_URL="$REDIS_URL"
        exec seed-gen server
        ;;
esac
```

**Modification pattern for removal:**
1. Delete entire case block for fuzzer (lines 113-129)
2. Verify no shared initialization logic in deleted block needed by other cases
3. Keep error handling for unknown RUN_TYPE (lines 152-156)

### Pattern 3: libCRS Directory Watcher for Submission

**What:** Background watcher monitors directory, automatically submits new files to competition API

**When to use:** Decouple file generation from API submission (allows async, retries)

**Example from buttercup_entrypoint (seedgen case):**
```bash
# Start background watcher for seed submission
libCRS register-submit-dir seed "$CORPUS_DIR" --log /tmp/seed_submit.log &

# Seeds written to $CORPUS_DIR are automatically submitted
# Seed-gen bot writes: /artifacts/corpus/SHA256HASH
# libCRS detects new file, POSTs to competition API
```

**Why this pattern is critical:**
- Seed-gen doesn't need API credentials or network logic
- Submission retries handled by libCRS, not application code
- Multiple services can write to same directory (automatic deduplication via hash filenames)
- Logs to /tmp/seed_submit.log for debugging submission issues

### Anti-Patterns to Avoid

- **Partial service removal:** Don't remove fuzzer from crs.yaml but leave Dockerfile stage - wastes image space
- **Shared corpus registration drift:** Don't remove fuzzer's libCRS registration without verifying seedgen has its own (line 143 confirms seedgen registers separately)
- **PATH ordering assumptions:** Don't assume service finds correct binary without explicit PATH - fuzzer venv was first in PATH (line 133), removing it changes resolution order
- **Dead code in entrypoint:** Don't leave fuzzer case block as "unused fallback" - explicit deletion prevents accidental invocation

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Service discovery | Custom network scanning, hardcoded IPs | `libCRS get-service-domain redis` | Competition framework provides service DNS resolution, handles cluster networking |
| File watching for submission | `inotify` loops, polling scripts | `libCRS register-submit-dir` | Handles retries, rate limiting, API authentication, deduplication |
| Multi-stage Docker builds | Multiple Dockerfiles, build scripts | Docker `buildx bake` with HCL | Single source of truth, layer caching, parallel builds |
| Service coordination | Direct HTTP/gRPC between services | Redis pub/sub, queues, maps | Proven pattern in existing codebase, loose coupling, observable state |

**Key insight:** The libCRS CLI abstracts all competition infrastructure complexity. Don't try to replace its functionality with custom HTTP clients or file watchers - it handles edge cases like network splits, API rate limits, and authentication renewal that custom solutions miss.

## Common Pitfalls

### Pitfall 1: Orphaned Docker Build Stages
**What goes wrong:** Removing service from crs.yaml but leaving builder stage in Dockerfile wastes ~200MB per image

**Why it happens:** Multi-stage builds don't automatically prune unreferenced stages - if nothing COPYs from fuzzer-builder, it still executes and caches layers

**How to avoid:**
1. Search Dockerfile for all references to stage being removed: `grep -n "fuzzer-builder" oss-crs/dockerfiles/buttercup-runner.Dockerfile`
2. Delete stage definition (FROM ... AS fuzzer-builder block)
3. Delete all COPY --from=fuzzer-builder commands
4. Remove stage directory from PATH environment variable
5. Rebuild with `--no-cache` flag to verify: `docker buildx bake --no-cache -f oss-crs/docker-bake.hcl`

**Warning signs:** Docker build completes but image size doesn't decrease significantly after service removal

### Pitfall 2: Shared Initialization Logic in Entrypoint
**What goes wrong:** Fuzzer case block may contain setup logic that other services depend on (environment variables, directory creation)

**Why it happens:** Entrypoint scripts accumulate shared logic in first case block, then later cases assume it executed

**How to avoid:**
1. Audit fuzzer case block (lines 113-129) for setup commands
2. Check if any setup is needed by other services
3. Specifically verify: directory creation (covered by global lines 14-19), libCRS registration (seedgen has its own at line 143), environment variable exports (seedgen sets its own at lines 145-149)
4. Current analysis: fuzzer block contains ONLY fuzzer-specific logic, safe to delete entirely

**Warning signs:** Other services fail with "directory not found" or "environment variable unset" after fuzzer removal

### Pitfall 3: libCRS Registration Confusion
**What goes wrong:** Removing fuzzer's seed registration without verifying seedgen has independent registration causes seeds to not submit

**Why it happens:** Both fuzzer and seedgen write to /artifacts/corpus/ - developer assumes single registration watches directory for both

**How to avoid:**
1. Verify each service case has independent `libCRS register-submit-dir` call
2. Current analysis:
   - Fuzzer: lines 116-117 register POVs and seeds
   - Seedgen: line 143 registers seeds independently
3. Removal safe: seedgen registration is self-contained
4. POV registration (line 116) can be removed - no longer needed

**Warning signs:** Seeds written to /artifacts/corpus/ but don't appear in competition API logs after fuzzer removal

### Pitfall 4: Service Definition Syntax Errors
**What goes wrong:** YAML indentation or key misalignment breaks libCRS parsing

**Why it happens:** YAML is whitespace-sensitive, removing service leaves trailing keys or misaligned indents

**How to avoid:**
1. Use YAML linter before committing: `yamllint oss-crs/crs.yaml`
2. Verify structure: `python -c "import yaml; yaml.safe_load(open('oss-crs/crs.yaml'))"`
3. Expected structure after removal:
```yaml
crs_run_phase:
  redis:
    dockerfile: ...
  orchestrator:
    dockerfile: ...
  coverage-bot:
    dockerfile: ...
  seed-gen:
    dockerfile: ...
```

**Warning signs:** libCRS compile fails with "invalid YAML structure" or "unexpected key"

### Pitfall 5: PATH Priority Changes Break Service Resolution
**What goes wrong:** Removing fuzzer venv from PATH changes binary resolution order, wrong version executes

**Why it happens:** Current PATH (line 133): `/app/fuzzer/.venv/bin:/app/seed-gen/.venv/bin` - fuzzer has priority

**How to avoid:**
1. Check if fuzzer and seed-gen venvs have overlapping binaries: `comm -12 <(ls /app/fuzzer/.venv/bin) <(ls /app/seed-gen/.venv/bin)`
2. After removal, PATH becomes: `/app/seed-gen/.venv/bin:$PATH`
3. Verify seed-gen finds correct executables: `docker run --rm -e RUN_TYPE=seedgen buttercup-runner which seed-gen`
4. Current analysis: seed-gen and fuzzer use different entry points (seed-gen vs buttercup-fuzzer), no collision risk

**Warning signs:** Coverage-bot or seed-gen fail with "command not found" or wrong version after fuzzer removal

## Code Examples

Verified patterns from codebase:

### Service Removal from crs.yaml
```yaml
# Before (5 services)
crs_run_phase:
  redis:
    dockerfile: oss-crs/dockerfiles/redis.Dockerfile
  orchestrator:
    dockerfile: oss-crs/dockerfiles/buttercup-runner.Dockerfile
    additional_env:
      RUN_TYPE: orchestrator
  fuzzer-bot:  # DELETE THIS BLOCK
    dockerfile: oss-crs/dockerfiles/buttercup-runner.Dockerfile
    additional_env:
      RUN_TYPE: fuzzer
  coverage-bot:
    dockerfile: oss-crs/dockerfiles/buttercup-runner.Dockerfile
    additional_env:
      RUN_TYPE: coverage
  seed-gen:
    dockerfile: oss-crs/dockerfiles/buttercup-runner.Dockerfile
    additional_env:
      RUN_TYPE: seedgen

# After (4 services)
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

### Docker Builder Stage Removal
```dockerfile
# Before: fuzzer-builder stage exists (lines 38-65)
FROM base-image AS fuzzer-builder
WORKDIR /app
RUN cd fuzzer && uv sync --frozen --no-editable
RUN cd fuzzer_runner && uv sync --frozen --no-editable

# DELETE ENTIRE STAGE ABOVE

# Runtime stage before
FROM runner-base AS runtime
COPY --from=fuzzer-builder /app/fuzzer/.venv /app/fuzzer/.venv  # DELETE
COPY --from=fuzzer-builder /app/fuzzer_runner/.venv /app/fuzzer_runner/.venv  # DELETE
COPY --from=seedgen-builder /app/seed-gen/.venv /app/seed-gen/.venv
ENV PATH=/app/fuzzer/.venv/bin:/app/seed-gen/.venv/bin:$PATH  # UPDATE

# Runtime stage after
FROM runner-base AS runtime
COPY --from=seedgen-builder /app/seed-gen/.venv /app/seed-gen/.venv
ENV PATH=/app/seed-gen/.venv/bin:$PATH
```

### Entrypoint Case Removal
```bash
# Before: fuzzer case exists (lines 113-129)
case "$RUN_TYPE" in
    # ... other cases ...
    fuzzer)  # DELETE FROM HERE
        echo "Starting Fuzzer Bot..."
        libCRS register-submit-dir pov "$POVS_DIR" --log /tmp/pov_submit.log &
        libCRS register-submit-dir seed "$CORPUS_DIR" --log /tmp/seed_submit.log &
        libCRS register-shared-dir /shared-corpus corpus || true
        export BUTTERCUP_FUZZER_REDIS_URL="$REDIS_URL"
        export BUTTERCUP_FUZZER_TIMER=5000
        export BUTTERCUP_FUZZER_WDIR="$ARTIFACTS_DIR"
        export BUTTERCUP_FUZZER_CRS_SCRATCH_DIR="$ARTIFACTS_DIR"
        export BUTTERCUP_FUZZER_RUNNER_PATH="/app/fuzzer_runner/runner.sh"
        export BUTTERCUP_FUZZER_TIMEOUT=60000
        export BUTTERCUP_FUZZER_LOG_LEVEL=INFO
        exec buttercup-fuzzer
        ;;  # DELETE TO HERE
    coverage)
        # ... coverage case remains ...
```

### Validation Commands
```bash
# Verify YAML syntax
python -c "import yaml; yaml.safe_load(open('oss-crs/crs.yaml'))"

# Verify Docker build succeeds without fuzzer stage
docker buildx bake --no-cache -f oss-crs/docker-bake.hcl

# Verify only 4 services defined
grep -E "^  [a-z-]+:" oss-crs/crs.yaml | wc -l  # Should return 4

# Verify entrypoint has no fuzzer case
grep -n "fuzzer)" oss-crs/bin/buttercup_entrypoint  # Should return no results

# Verify PATH doesn't reference fuzzer
grep "fuzzer/.venv" oss-crs/dockerfiles/buttercup-runner.Dockerfile  # Should return no results
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | pytest 8.3.4 + pytest-asyncio 0.25.2 |
| Config file | Component-level pyproject.toml (seed-gen, common, fuzzer, etc.) |
| Quick run command | `cd <component> && uv run pytest -x` |
| Full suite command | `cd <component> && uv run pytest --cov` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SVC-01 | Only 4 services in crs.yaml | config validation | `python -c "import yaml; assert len(yaml.safe_load(open('oss-crs/crs.yaml'))['crs_run_phase']) == 4"` | ✅ crs.yaml |
| SVC-02 | Redis service defined | config validation | `grep -q "redis:" oss-crs/crs.yaml` | ✅ crs.yaml |
| SVC-03 | Orchestrator service defined | config validation | `grep -q "orchestrator:" oss-crs/crs.yaml` | ✅ crs.yaml |
| SVC-04 | Coverage-bot service defined | config validation | `grep -q "coverage-bot:" oss-crs/crs.yaml` | ✅ crs.yaml |
| SVC-05 | Seed-gen service defined | config validation | `grep -q "seed-gen:" oss-crs/crs.yaml` | ✅ crs.yaml |
| CODE-02 | No fuzzer case in entrypoint | config validation | `! grep -q "fuzzer)" oss-crs/bin/buttercup_entrypoint` | ✅ buttercup_entrypoint |
| CLN-01 | No fuzzer stages in Dockerfile | config validation | `! grep -q "fuzzer-builder" oss-crs/dockerfiles/buttercup-runner.Dockerfile` | ✅ buttercup-runner.Dockerfile |

### Sampling Rate
- **Per task commit:** `python -c "import yaml; yaml.safe_load(open('oss-crs/crs.yaml'))"` + grep validations
- **Per wave merge:** Full integration test (docker buildx bake + verify image boots)
- **Phase gate:** All config validations pass + Docker build succeeds + no fuzzer artifacts remain

### Wave 0 Gaps
None - existing configuration files cover all requirements. Test infrastructure is simple shell commands validating file contents.

## Sources

### Primary (HIGH confidence)
- /home/andrew/post/buttercup-bugfind/oss-crs/crs.yaml - Service definitions, current has 5 services
- /home/andrew/post/buttercup-bugfind/oss-crs/bin/buttercup_entrypoint - Runtime routing, fuzzer case at lines 113-129
- /home/andrew/post/buttercup-bugfind/oss-crs/dockerfiles/buttercup-runner.Dockerfile - Multi-stage build, fuzzer-builder at lines 38-65
- /home/andrew/post/buttercup-bugfind/oss-crs/orchestrator.py - Redis population logic, confirms BuildMap/HarnessWeights usage
- /home/andrew/post/buttercup-bugfind/.planning/research/SUMMARY.md - Comprehensive codebase analysis and architecture patterns
- /home/andrew/post/buttercup-bugfind/CLAUDE.md - Project-specific development patterns and commands

### Secondary (MEDIUM confidence)
- Docker documentation - Multi-stage build patterns
- YAML 1.2 specification - Syntax validation
- libCRS CLI usage - Observed via entrypoint script patterns (implementation details are closed-source competition infrastructure)

### Tertiary (LOW confidence)
None - all research based on direct codebase analysis

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All technologies observed directly in codebase, no external dependencies
- Architecture: HIGH - Data flow traced through actual code paths (Redis keys, file operations), verified via orchestrator.py
- Pitfalls: HIGH - Based on microservices extraction patterns and specific codebase structure analysis
- Validation: HIGH - Test infrastructure exists and is actively used (pytest in all components)

**Research date:** 2026-03-10
**Valid until:** 2026-04-10 (30 days - stable domain, established patterns)

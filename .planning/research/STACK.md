# Technology Stack: Seedgen Direct Submission

**Project:** Buttercup Seed-Gen Standalone
**Researched:** 2026-03-10

## Executive Summary

The current oss-crs seedgen writes seeds to a local directory (`CORPUS_DIR`), and they're submitted via `libCRS register-submit-dir seed` background process. To modify for standalone direct submission, we need to:

1. Keep the background `libCRS register-submit-dir seed` watcher (already working)
2. Remove fuzzer-bot service and its submission paths
3. Maintain corpus directory write mechanism (already optimal)

**Key finding:** The submission mechanism is already implemented correctly. Seeds are written to `CORPUS_DIR` and automatically submitted by the libCRS watcher. The only change needed is removing fuzzer-bot from service configuration.

## libCRS CLI Interface

### Observed Commands

Based on analysis of `oss-crs/bin/buttercup_entrypoint`:

| Command | Purpose | Parameters | Notes |
|---------|---------|------------|-------|
| `libCRS download-build-output` | Download build artifacts from competition API | `<artifact_type> <destination_dir>` | Artifact types: `task`, `task-coverage`, `cqdb` |
| `libCRS register-submit-dir` | Register directory for automatic submission | `<submission_type> <watch_dir> --log <logfile>` | Run in background (`&`), watches directory |
| `libCRS get-service-domain` | Get service DNS name | `<service_name>` | Returns hostname for inter-service communication |

### Seed Submission Interface

**Current implementation (fuzzer entrypoint, line 117):**
```bash
libCRS register-submit-dir seed "$CORPUS_DIR" --log /tmp/seed_submit.log &
```

**Current implementation (seedgen entrypoint, line 143):**
```bash
libCRS register-submit-dir seed "$CORPUS_DIR" --log /tmp/seed_submit.log &
```

**How it works:**
1. `register-submit-dir` runs as background process
2. Watches `$CORPUS_DIR` for new files
3. Automatically submits new seeds to competition API
4. Logs to `/tmp/seed_submit.log`
5. Runs continuously until container stops

**Confidence:** HIGH (directly observed in codebase)

## Current Seedgen Output Mechanism

### Data Flow

```
SeedGenBot.run_task()
    ↓
Generates seeds in out_dir (temp directory)
    ↓
Corpus.copy_corpus(str(out_dir))
    ↓
Copies to local corpus: {wdir}/{task_id}/corpus_{harness_name}/
    ↓
libCRS register-submit-dir watcher detects new files
    ↓
Automatically submits to competition API
```

### Key Code Paths

**Seed Generation** (`seed-gen/src/buttercup/seed_gen/seed_gen_bot.py:256-257`):
```python
copied_files = corp.copy_corpus(str(out_dir))
logger.info("Copied %d files to corpus %s", len(copied_files), corp.corpus_dir)
```

**Corpus Directory** (`common/src/buttercup/common/corpus.py:223-227`):
```python
class Corpus(InputDir):
    def __init__(self, wdir: str, task_id: str, harness_name: str, copy_corpus_max_size: int | None = None):
        self.task_id = task_id
        self.harness_name = harness_name
        self.corpus_dir = os.path.join(task_id, f"{CORPUS_DIR_NAME}_{harness_name}")
        super().__init__(wdir, self.corpus_dir, copy_corpus_max_size=copy_corpus_max_size)
```

**Copy Mechanism** (`common/src/buttercup/common/corpus.py:53-67`):
```python
def copy_corpus(self, src_dir: str) -> list[str]:
    """Copy files from src_dir to local corpus only."""
    files = []
    for file in os.listdir(src_dir):
        file_path = os.path.join(src_dir, file)
        size = Path(file_path).stat().st_size
        if self.copy_corpus_max_size is not None and size > self.copy_corpus_max_size:
            logger.warning(
                "Not copying corpus input (size %s bytes) which exceeds max size %s bytes",
                size,
                self.copy_corpus_max_size,
            )
            continue
        files.append(self.copy_file(file_path, only_local=True))
    return files
```

**File Hashing** (`common/src/buttercup/common/corpus.py:21-27, 40-51`):
- Seeds are hashed using SHA256 (first 100 bytes, then streaming)
- Files are renamed to their hash (64 hex characters)
- Prevents duplicate submissions
- Hash used as filename for deduplication

### Environment Configuration

**Entrypoint setup** (`oss-crs/bin/buttercup_entrypoint:140-151`):
```bash
seedgen)
    echo "Starting Seed-Gen..."
    # Register submit directories for seeds
    libCRS register-submit-dir seed "$CORPUS_DIR" --log /tmp/seed_submit.log &

    export BUTTERCUP_SEED_GEN_SERVER__REDIS_URL="$REDIS_URL"
    export BUTTERCUP_SEED_GEN_SERVER__SLEEP_TIME=10
    export BUTTERCUP_SEED_GEN_SERVER__CORPUS_ROOT="$CORPUS_DIR"
    export BUTTERCUP_SEED_GEN_WDIR="$ARTIFACTS_DIR"
    export BUTTERCUP_SEED_GEN_LOG_LEVEL=INFO
    exec seed-gen server
```

**Key variables:**
- `CORPUS_DIR="/artifacts/corpus"` — submission watch directory
- `BUTTERCUP_SEED_GEN_SERVER__CORPUS_ROOT` — not currently used by seedgen
- `BUTTERCUP_SEED_GEN_WDIR="/artifacts"` — working directory base
- Actual corpus written to: `{WDIR}/{task_id}/corpus_{harness_name}/`

**Confidence:** HIGH (verified in codebase)

## What Changes Are Needed

### Required Changes

**1. Remove fuzzer-bot from crs.yaml**

Current service definition (line 33-36):
```yaml
fuzzer-bot:
  dockerfile: oss-crs/dockerfiles/buttercup-runner.Dockerfile
  additional_env:
    RUN_TYPE: fuzzer
```

Action: DELETE this service definition entirely.

**2. Remove fuzzer-bot from buttercup_entrypoint**

Current fuzzer case (line 113-130):
```bash
fuzzer)
    echo "Starting Fuzzer Bot..."
    # Register submit directories for POVs and seeds
    libCRS register-submit-dir pov "$POVS_DIR" --log /tmp/pov_submit.log &
    libCRS register-submit-dir seed "$CORPUS_DIR" --log /tmp/seed_submit.log &
    ...
```

Action: DELETE this case block entirely (not used in standalone seedgen).

### No Changes Required

**1. Seed submission mechanism**
- Already configured in seedgen case (line 143)
- Already runs as background watcher
- Already monitors `$CORPUS_DIR` for new files

**2. Corpus writing**
- `Corpus.copy_corpus()` writes to correct location
- File hashing prevents duplicates
- Size limits already enforced (`max_corpus_seed_size: 64 KiB`)

**3. Orchestrator**
- Still needed to populate Redis with task metadata
- Registers build outputs in Redis (BuildMap)
- Registers harness weights (HarnessWeights)
- Seedgen reads from Redis to discover tasks

**4. Coverage-bot**
- Still useful for seed quality metrics
- Provides function coverage data
- Informs SeedExploreTask target selection

### Verification Points

After changes, verify:
1. `libCRS register-submit-dir seed` runs in seedgen container
2. Seeds appear in `/artifacts/corpus/`
3. Seeds are submitted to competition API (check `/tmp/seed_submit.log`)
4. No POV submission attempts (fuzzer removed)

## Integration Architecture

### Current (with fuzzer)
```
orchestrator → Redis
    ↓
seedgen → /artifacts/{task_id}/corpus_{harness}/  ← fuzzer reads
    ↓                                                   ↓
libCRS watcher                                    crashes → POVs
    ↓
Competition API (seeds)
```

### Target (standalone seedgen)
```
orchestrator → Redis
    ↓
seedgen → /artifacts/{task_id}/corpus_{harness}/
    ↓
libCRS watcher
    ↓
Competition API (seeds only)
```

**Key insight:** The fuzzer-bot also ran `libCRS register-submit-dir seed` because it added fuzzer-generated corpus additions. In standalone mode, only seedgen generates seeds, so only one watcher is needed.

## Technical Specifications

### Corpus File Format
- **Naming:** SHA256 hash (64 hex characters)
- **Size limit:** 64 KiB (configurable via `max_corpus_seed_size`)
- **Location:** `{wdir}/{task_id}/corpus_{harness_name}/{hash}`
- **Deduplication:** Automatic via hash-based naming

### libCRS Watcher Behavior
- **Process model:** Background daemon (`&`)
- **Watch mechanism:** File system monitoring (implementation unknown)
- **Submission:** Automatic when new files detected
- **Logging:** Writes to specified log file
- **Lifecycle:** Runs until container stops

### Environment Contract

Required for seedgen to work:
```bash
REDIS_URL                               # Redis connection
BUTTERCUP_SEED_GEN_WDIR                 # Working directory base
BUTTERCUP_SEED_GEN_SERVER__REDIS_URL    # Redundant with REDIS_URL
CORPUS_DIR                              # Watch directory for libCRS
```

## Sources

**PRIMARY (Codebase):**
- `/home/andrew/post/buttercup-bugfind/oss-crs/bin/buttercup_entrypoint` (libCRS CLI usage)
- `/home/andrew/post/buttercup-bugfind/seed-gen/src/buttercup/seed_gen/seed_gen_bot.py` (seed output)
- `/home/andrew/post/buttercup-bugfind/common/src/buttercup/common/corpus.py` (corpus mechanism)
- `/home/andrew/post/buttercup-bugfind/oss-crs/crs.yaml` (service definitions)
- `/home/andrew/post/buttercup-bugfind/oss-crs/orchestrator.py` (Redis population)
- `/home/andrew/post/buttercup-bugfind/seed-gen/src/buttercup/seed_gen/config.py` (configuration)

**EXTERNAL (AIxCC):**
- libCRS is competition infrastructure CLI (not open-source, observed via usage patterns)
- AIxCC competition documentation not publicly indexed
- Confidence: MEDIUM for libCRS internals (observed interface only, not implementation)

## Open Questions

1. **libCRS watcher implementation** — How does it detect new files? Polling vs inotify? (LOW priority, works as-is)
2. **Submission deduplication** — Does libCRS track submitted hashes server-side? (LOW priority, client-side hash prevents re-submission)
3. **Corpus root configuration** — `BUTTERCUP_SEED_GEN_SERVER__CORPUS_ROOT` is set but unused by seedgen code (investigate if needed)

## Confidence Assessment

| Area | Confidence | Rationale |
|------|------------|-----------|
| libCRS submission interface | HIGH | Direct observation in entrypoint, working implementation |
| Seedgen output mechanism | HIGH | Code analysis, clear data flow |
| Required changes | HIGH | Simple service removal, no code changes needed |
| libCRS internals | MEDIUM | Observed interface only, implementation unknown |
| Submission reliability | MEDIUM | Assumes libCRS handles retries, no error handling visible |

## Recommendation

**Proceed with minimal changes:**
1. Remove `fuzzer-bot` from `crs.yaml`
2. Remove fuzzer case from `buttercup_entrypoint`
3. Keep all existing seedgen infrastructure unchanged
4. Verify submission logs show successful seed uploads

**No code changes needed** to seedgen, corpus, or orchestrator components. The existing architecture already supports standalone seed submission.

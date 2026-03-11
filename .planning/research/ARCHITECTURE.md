# Architecture Patterns: Buttercup Seedgen Standalone

**Domain:** Bug-finding CRS service restructuring
**Researched:** 2026-03-10
**Confidence:** HIGH (all information from codebase analysis)

## Current OSS-CRS Architecture

### Service Topology

```
┌─────────────────────────────────────────────────────────────┐
│                    OSS-CRS Current State                     │
└─────────────────────────────────────────────────────────────┘

┌──────────────┐
│  libCRS API  │  (external competition API)
└──────┬───────┘
       │ download build outputs
       │
┌──────▼─────────────────────────────────────────────────────┐
│               Docker Services (crs.yaml)                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────┐     ┌──────────────┐     ┌──────────────┐   │
│  │  redis  │────▶│ orchestrator │────▶│ fuzzer-bot   │   │
│  └─────────┘     └──────────────┘     └──────┬───────┘   │
│       │                                        │            │
│       │                                        │ POVs       │
│       │          ┌──────────────┐              │            │
│       ├─────────▶│ coverage-bot │              │            │
│       │          └──────────────┘              │            │
│       │                 │                      │            │
│       │                 │ function coverage    │            │
│       │                 ▼                      │            │
│       │          ┌──────────────┐              │            │
│       └─────────▶│   seed-gen   │──────────────┘            │
│                  └──────┬───────┘       seeds               │
│                         │                                   │
└─────────────────────────┼───────────────────────────────────┘
                          │
                          ▼
                   libCRS register-submit-dir
```

### Component Responsibilities

| Component | Purpose | Inputs | Outputs | Keep/Remove |
|-----------|---------|--------|---------|-------------|
| **redis** | Message broker, shared state | — | Redis queues/maps | **KEEP** |
| **orchestrator** | Populates Redis from disk artifacts | `/artifacts/task` from libCRS | BuildMap, HarnessWeights in Redis | **KEEP** |
| **fuzzer-bot** | Executes libfuzzer, finds crashes | Corpus from Redis, seeds from seed-gen | POVs via libCRS | **REMOVE** |
| **coverage-bot** | Measures code coverage | Corpus, coverage build | FunctionCoverage in Redis | **KEEP** |
| **seed-gen** | Generates targeted test inputs | BuildMap, FunctionCoverage from Redis | Seeds to Corpus | **KEEP + MODIFY** |

### Data Flow Components

#### Redis Data Structures

**HarnessWeights** (`harness_weights` hash)
- Populated by: orchestrator
- Consumed by: fuzzer-bot, coverage-bot, seed-gen
- Purpose: Task discovery — which harnesses to work on

**BuildMap** (`build_list`, `build_san_list` keys)
- Populated by: orchestrator
- Consumed by: All bots
- Purpose: Locate build artifacts (FUZZER, COVERAGE, PATCH builds)

**CoverageMap** (`coverage_map:<harness>:<package>:<task_id>` hash)
- Populated by: coverage-bot
- Consumed by: seed-gen (FunctionSelector)
- Purpose: Guide seed-gen to focus on high-coverage functions

**CrashQueue** (Redis queue, not used in seedgen-only)
- Populated by: fuzzer-bot, seed-gen (vuln-discovery mode)
- Consumed by: tracer-bot (not in oss-crs)
- Purpose: Crash triage pipeline

#### Corpus Management

**Corpus class** (`common/src/buttercup/common/corpus.py`)
- Local path: `/artifacts/<task_id>/corpus_<harness_name>/`
- Remote path: node-local shared storage
- Operations:
  - `copy_corpus(src_dir)` — Import generated seeds (used by seed-gen)
  - `sync_from_remote()` — Pull corpus from shared storage
  - `sync_to_remote()` — Push corpus to shared storage

**Current seed flow:**
1. seed-gen generates seeds → temp output directory
2. seed-gen calls `corp.copy_corpus(out_dir)` → copies to local corpus
3. fuzzer-bot pulls from corpus, fuzzes with seeds
4. fuzzer-bot submits POVs via `libCRS register-submit-dir pov`

## Target Architecture: Seedgen-Only

### Service Topology

```
┌─────────────────────────────────────────────────────────────┐
│                   OSS-CRS Target State                       │
└─────────────────────────────────────────────────────────────┘

┌──────────────┐
│  libCRS API  │  (external competition API)
└──────┬───────┘
       │ download build outputs
       │
┌──────▼─────────────────────────────────────────────────────┐
│               Docker Services (crs.yaml)                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────┐     ┌──────────────┐                         │
│  │  redis  │────▶│ orchestrator │                         │
│  └─────────┘     └──────────────┘                         │
│       │                                                     │
│       │          ┌──────────────┐                         │
│       ├─────────▶│ coverage-bot │                         │
│       │          └──────────────┘                         │
│       │                 │                                  │
│       │                 │ function coverage               │
│       │                 ▼                                  │
│       │          ┌──────────────┐                         │
│       └─────────▶│   seed-gen   │                         │
│                  └──────┬───────┘                         │
│                         │                                  │
│                         │ seeds written directly          │
│                         ▼                                  │
│                  /artifacts/corpus/                        │
│                         │                                  │
└─────────────────────────┼──────────────────────────────────┘
                          │
                          ▼
                   libCRS register-submit-dir seed
                   (watches /artifacts/corpus/)
```

### Removed Components

**fuzzer-bot** — No longer needed
- Previously consumed seeds and generated POVs
- With seedgen-only, we skip fuzzing phase entirely

**POV submission** — No longer needed
- `libCRS register-submit-dir pov` removed from entrypoint
- POV-related directories (`/artifacts/povs/`) no longer created

**Shared corpus sync** — No longer needed
- `libCRS register-shared-dir /shared-corpus corpus` removed
- No multi-pod corpus sharing (single seed-gen writes directly)

### Modified Components

**seed-gen** — Same internal logic, different output
- **No code changes needed** in seed-gen bot itself
- Corpus class already writes to `/artifacts/<task_id>/corpus_<harness_name>/`
- `libCRS register-submit-dir seed` watches `/artifacts/corpus/` (mapped volume)
- Seeds automatically submitted when written to corpus directory

**orchestrator** — No changes needed
- Same role: populate Redis from disk artifacts
- Still registers FUZZER and COVERAGE builds
- HarnessWeights still populated for seed-gen task discovery

**coverage-bot** — No changes needed
- Still measures coverage and populates CoverageMap
- Seed-gen's FunctionSelector still needs this data

**buttercup_entrypoint** — Simplified
- Remove fuzzer-bot case
- Remove POV registration
- Remove shared corpus registration
- Keep seed submission registration in seedgen case

## Data Flow: Before vs After

### Current Flow (Full Pipeline)

```
orchestrator → Redis BuildMap/HarnessWeights
     ↓
coverage-bot → corpus → coverage metrics → Redis CoverageMap
     ↓
seed-gen → reads CoverageMap → generates seeds → Corpus.copy_corpus()
     ↓
   local corpus (/artifacts/<task_id>/corpus_<harness>/)
     ↓
fuzzer-bot → reads corpus → fuzzes → crashes → POVs
     ↓
libCRS register-submit-dir pov → competition API
libCRS register-submit-dir seed → competition API
```

### Target Flow (Seedgen-Only)

```
orchestrator → Redis BuildMap/HarnessWeights
     ↓
coverage-bot → corpus → coverage metrics → Redis CoverageMap
     ↓
seed-gen → reads CoverageMap → generates seeds → Corpus.copy_corpus()
     ↓
   /artifacts/corpus/ (shared with host)
     ↓
libCRS register-submit-dir seed → competition API
```

**Key difference:** Skip fuzzing phase, submit seeds directly

## Component Boundaries

### Unchanged Services

| Service | Interface | State Storage | Dependencies |
|---------|-----------|---------------|--------------|
| redis | TCP :6379 | In-memory (ephemeral) | None |
| orchestrator | Redis producer | None (one-shot, stays alive) | redis, libCRS (download) |
| coverage-bot | Redis consumer/producer | `/artifacts/` (node-local) | redis, COVERAGE build |
| seed-gen | Redis consumer, file writer | `/artifacts/` (node-local) | redis, FUZZER build, codequery |

### Service Communication

**All communication via Redis:**
- No direct service-to-service calls
- No shared memory/volumes between services
- Redis provides:
  - Task discovery (HarnessWeights)
  - Build artifact location (BuildMap)
  - Coverage guidance (CoverageMap)

**External interfaces:**
- libCRS API (download builds, submit artifacts)
- Host filesystem (`/artifacts/` volume mount)

## Build Order for Changes

### Phase 1: Remove fuzzer-bot service

**Changes:**
1. Edit `oss-crs/crs.yaml` — delete `fuzzer-bot` section
2. Edit `oss-crs/bin/buttercup_entrypoint` — remove fuzzer case
3. Edit `oss-crs/bin/buttercup_entrypoint` — remove POV registration
4. Edit `oss-crs/bin/buttercup_entrypoint` — remove shared corpus registration

**Validation:**
- Services start without fuzzer-bot
- No POV-related directories created
- Seed-gen still runs and generates seeds

**Risk:** LOW — Clean service removal, no shared dependencies

### Phase 2: Configure seed submission

**Changes:**
1. Edit `oss-crs/bin/buttercup_entrypoint` — ensure seedgen case still has `libCRS register-submit-dir seed`
2. Verify corpus directory structure matches libCRS expectations
3. Update `CORPUS_DIR` environment variable if needed

**Validation:**
- Seeds written by seed-gen appear in `/artifacts/corpus/`
- libCRS detects and submits seeds to competition API

**Risk:** LOW — libCRS already handles submission, just need correct path mapping

### Phase 3: Update documentation

**Changes:**
1. Update `oss-crs/` README if exists
2. Update deployment instructions
3. Document simplified architecture

**Validation:**
- Documentation matches actual behavior
- Setup instructions work end-to-end

**Risk:** None (documentation only)

## Architecture Patterns to Follow

### Pattern 1: Redis-mediated task discovery

**What:** Services discover work via shared Redis data structures, not direct calls

**When:** Any multi-service coordination

**Example:**
```python
class TaskLoop(ABC):
    def serve_item(self) -> bool:
        # Pull tasks from HarnessWeights (populated by orchestrator)
        weighted_items = self.harness_weights.list_harnesses()
        # Select task and run
        chc = random.choices(weighted_items, weights=[it.weight for it in weighted_items])[0]
        builds = {reqbuild: self.builds.get_builds(chc.task_id, reqbuild)
                  for reqbuild in self.required_builds()}
        self.run_task(chc, builds)
```

**Why:** Decouples services, allows horizontal scaling, simplifies deployment

### Pattern 2: Corpus as file-backed state

**What:** Seeds/POVs managed as files with hash-based names, not database records

**When:** Managing test inputs, crashes, coverage corpus

**Example:**
```python
class Corpus(InputDir):
    def copy_corpus(self, src_dir: str) -> list[str]:
        # Hash each file and copy to corpus directory
        files = []
        for file in os.listdir(src_dir):
            files.append(self.copy_file(file_path, only_local=True))
        return files
```

**Why:**
- libCRS watches directories for submission
- Deduplication via SHA256 filenames
- Easy to inspect/debug
- No database overhead

### Pattern 3: libCRS as submission interface

**What:** Use `libCRS register-submit-dir <type> <path>` to monitor directories and submit artifacts

**When:** Submitting seeds, POVs, patches to competition API

**Example:**
```bash
# In entrypoint script
libCRS register-submit-dir seed "$CORPUS_DIR" --log /tmp/seed_submit.log &
```

**Why:**
- Standard interface for OSS-CRS competition
- Automatic batching and retry
- Handles API authentication
- Decouples artifact generation from submission

## Anti-Patterns to Avoid

### Anti-Pattern 1: Direct service communication

**What:** Services calling each other's APIs or sharing volumes

**Why bad:** Tight coupling, deployment complexity, race conditions

**Instead:** Use Redis as message broker, files for large artifacts

### Anti-Pattern 2: Custom submission logic

**What:** Writing custom code to submit artifacts to competition API

**Why bad:** Reimplementing libCRS functionality, auth complexity, no retry logic

**Instead:** Use `libCRS register-submit-dir` and write to watched directories

### Anti-Pattern 3: Corpus sync between pods

**What:** Trying to sync corpus across multiple seed-gen instances

**Why bad:** In seedgen-only mode, single seed-gen writes directly to submission directory

**Instead:** Single seed-gen writes to `/artifacts/corpus/`, libCRS handles submission

## Scalability Considerations

| Concern | At 1 harness | At 10 harnesses | Notes |
|---------|--------------|-----------------|-------|
| **Redis memory** | <100MB | <1GB | Mostly coverage data, scales with codebase size not harness count |
| **Disk I/O** | Low | Medium | Corpus writes, codequery database reads |
| **CPU** | 1-2 cores per service | Same | Seedgen-only doesn't parallelize per-harness |
| **Submission rate** | ~1 seed/min | ~10 seeds/min | libCRS batches submissions, network-limited |

**Bottlenecks:**
- Seed generation is CPU-bound (LLM calls, code analysis)
- Coverage analysis is I/O-bound (reading corpus, running instrumented binaries)
- Submission is network-bound (competition API rate limits)

**Not a concern for seedgen-only:**
- Fuzzing is most resource-intensive component (removed)
- No need for horizontal scaling (single-harness focus typical for OSS-CRS)

## Directory Structure

### Current (/artifacts/)

```
/artifacts/
├── task/                    # Main build (FUZZER type)
│   ├── task_meta.json
│   ├── src/                 # Source snapshot
│   └── fuzz-tooling/
│       └── build/out/
│           └── <project>/   # Fuzz targets
├── task-coverage/           # Coverage build (COVERAGE type)
│   ├── task_meta.json
│   └── fuzz-tooling/...
├── cqdb/                    # Codequery database (build output)
│   └── *.cqdb.tgz
├── <task_id>/               # Runtime state
│   ├── corpus_<harness>/    # Seeds (local + remote via node_local)
│   ├── crash_<harness>/     # POVs (removed in target)
│   └── <task_id>.cqdb.tgz   # Extracted cqdb
├── corpus/                  # CURRENT: fuzzer-bot writes here
│                            # TARGET: seed-gen writes here (for libCRS)
└── povs/                    # REMOVED in target
```

### Target (/artifacts/)

```
/artifacts/
├── task/                    # Main build
├── task-coverage/           # Coverage build
├── cqdb/                    # Codequery database
├── <task_id>/               # Runtime state
│   ├── corpus_<harness>/    # Seed-gen internal corpus
│   └── <task_id>.cqdb.tgz
└── corpus/                  # Seeds for libCRS submission
    └── <sha256-hash>        # Generated seeds (hash-named)
```

**Key change:** `/artifacts/corpus/` becomes the direct submission directory, not an intermediate location for fuzzer-bot.

## Critical Path

**For seed generation to work:**

1. orchestrator must register FUZZER build in BuildMap
2. orchestrator must register harness in HarnessWeights
3. coverage-bot must populate CoverageMap with function coverage
4. seed-gen must read from Redis and write to corpus directory
5. libCRS must watch corpus directory and submit to API

**No longer required:**
- fuzzer-bot reading corpus
- POV generation and submission
- Shared corpus synchronization

## Sources

All information from codebase analysis:
- `oss-crs/crs.yaml` — Service definitions
- `oss-crs/orchestrator.py` — Redis population logic
- `oss-crs/bin/buttercup_entrypoint` — Service routing and libCRS integration
- `seed-gen/src/buttercup/seed_gen/seed_gen_bot.py` — Seed generation logic
- `fuzzer/src/buttercup/fuzzing_infra/coverage_bot.py` — Coverage measurement
- `fuzzer/src/buttercup/fuzzing_infra/fuzzer_bot.py` — Fuzzing logic (to be removed)
- `common/src/buttercup/common/corpus.py` — Corpus management
- `common/src/buttercup/common/maps.py` — Redis data structures
- `common/src/buttercup/common/default_task_loop.py` — Task discovery pattern

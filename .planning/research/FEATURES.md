# Feature Landscape: Standalone Seedgen

**Domain:** Seed generation for fuzzing
**Researched:** 2026-03-10

## Table Stakes

Features users expect for a seed generation tool. Missing = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Seed generation from harness analysis | Core purpose of tool | High | LLM-based analysis of fuzzer harness |
| CodeQuery integration | Semantic code navigation | Medium | Required for context gathering |
| Multiple generation strategies | Coverage vs exploration trade-offs | Medium | seed-init, seed-explore, vuln-discovery |
| Coverage-based targeting | Focus on uncovered code | Medium | Function selector uses coverage data |
| Redis queue communication | Distributed task coordination | Low | Already exists, proven |
| Sandbox execution | Safe execution of generated code | Medium | Runs untrusted LLM output |
| Build artifact handling | Access to compiled binaries | Low | Read from task directories |
| Seed output to disk | Deliver generated seeds | Low | Write to corpus directory |

## Core Features: Must Keep

Features required for standalone seedgen to function with libcrs submission.

### Seed Generation Tasks

| Feature | Current Location | Keep/Modify | Notes |
|---------|-----------------|-------------|-------|
| **Seed-init** | `seed_init.py` | **KEEP** | Generates initial seeds from harness analysis |
| **Seed-explore** | `seed_explore.py` | **KEEP** | Targets specific functions based on coverage |
| **Vuln-discovery** | `vuln_discovery_*.py` | **REMOVE** | Only useful with fuzzer to test POVs |

**Keep rationale:** Seed-init and seed-explore are pure seed generation. Vuln-discovery tests POVs which requires fuzzer infrastructure.

### Infrastructure Components

| Feature | Current Location | Keep/Modify | Notes |
|---------|-----------------|-------------|-------|
| **Task loop** | `seed_gen_bot.py`, `default_task_loop.py` | **KEEP** | Redis-based task selection |
| **CodeQuery access** | `task.py` | **KEEP** | Semantic code analysis for context |
| **LLM integration** | `task.py` | **KEEP** | Claude/GPT for seed generation |
| **Sandbox execution** | `sandbox/` | **KEEP** | Safe execution of generated Python |
| **Function selector** | `function_selector.py` | **KEEP** | Coverage-based function sampling |
| **Harness finder** | `find_harness.py` | **KEEP** | Locates fuzzer harness code |
| **Orchestrator** | `oss-crs/orchestrator.py` | **KEEP** | Populates Redis from build artifacts |
| **Coverage-bot** | `fuzzer/coverage_bot.py` | **KEEP** | Provides coverage data for targeting |

### Output Path Modification

| Feature | Current Behavior | Required Change | Notes |
|---------|-----------------|-----------------|-------|
| **Corpus copy** | `Corpus.copy_corpus()` → local corpus | **MODIFY** | Must write to libcrs submit dir |
| **POV submission** | Writes to crash queue | **REMOVE** | No POVs without fuzzer |
| **Crash handling** | `CrashSubmit` class | **REMOVE** | Not needed without fuzzer |

**Critical change:** Current flow writes to `self.wdir/task_id/corpus_harness/`, then fuzzer-bot watches this. New flow must write to `CORPUS_ROOT` which is registered with `libcrs register-submit-dir seed`.

## Fuzzer-Specific Features: Can Remove

Features that only make sense in the context of running a fuzzer.

### POV/Crash Pipeline

| Feature | Location | Remove Rationale |
|---------|----------|------------------|
| **POV testing** | `vuln_base_task.py::_test_povs()` | Tests crashes with fuzzer |
| **Crash submission** | `vuln_base_task.py::CrashSubmit` | Submits to crash queue for triaging |
| **Crash reproduction** | `ReproduceMultiple` | Verifies crash reproducibility |
| **CrashDir** | `corpus.py::CrashDir` | Crash file storage |
| **Crash queue** | `seed_gen_bot.py` | Redis queue for crashes |
| **Crash set** | `seed_gen_bot.py` | Deduplication of crashes |
| **SARIF integration** | `vuln_base_task.py` | Static analysis hints for vulns |

### Fuzzer Coordination

| Feature | Location | Remove Rationale |
|---------|----------|------------------|
| **Fuzzer-bot** | `crs.yaml::fuzzer-bot` | Not running fuzzer |
| **POV submit directory** | `buttercup_entrypoint` line 116 | No POVs generated |
| **Corpus merging** | `corpus.py::sync_to_remote()` | No multi-fuzzer coordination |

## Features Needing Modification

Features that exist but need changes for standalone operation.

### Output Path Changes

| Feature | Current Implementation | Required Change | Complexity |
|---------|----------------------|-----------------|-----------|
| **Seed output** | `SeedGenBot::run_task()` writes to temp, calls `corp.copy_corpus()` | Change `CORPUS_ROOT` to libcrs submit dir | Low |
| **Corpus class** | `Corpus` extends `InputDir`, has local/remote sync | Use only `copy_corpus()` to `CORPUS_ROOT`, remove sync | Low |

**Current flow:**
```python
# seed_gen_bot.py line 256
copied_files = corp.copy_corpus(str(out_dir))
logger.info("Copied %d files to corpus %s", len(copied_files), corp.corpus_dir)
```

**New flow:**
```python
# Change CORPUS_ROOT to point to libcrs submit directory
# corpus_root = "/artifacts/corpus" (registered with libcrs)
# Corpus copies directly there, libcrs picks it up
```

### Configuration Changes

| Config | Current | New | Notes |
|--------|---------|-----|-------|
| `corpus_root` | Optional, used for remote sync | **Required**, points to libcrs dir | Already supported in config |
| `crash_dir_count_limit` | Limits crashes per token | **Remove** | No crash handling |
| `max_pov_size` | POV size limit | **Remove** | No POVs |
| `max_corpus_seed_size` | 64KB default | **Keep** | Still useful for seed size |

### Entrypoint Changes

| Component | Current | New | Notes |
|-----------|---------|-----|-------|
| **buttercup_entrypoint** | Registers both seed and pov dirs (lines 116-117) | Remove POV registration (line 116) | Keep line 117 for seeds |
| **crs.yaml** | Defines fuzzer-bot, coverage-bot, seed-gen, orchestrator | Remove fuzzer-bot | Coverage-bot still needed |

## Feature Dependencies

```
Seed Generation
    ├── LLM Integration (Claude/GPT)
    ├── CodeQuery (semantic code analysis)
    │   └── Build artifacts (cqdb)
    ├── Harness Source (find_harness)
    ├── Coverage Data (coverage-bot)
    │   └── Coverage Build
    └── Sandbox Execution (safe Python exec)

Task Discovery
    ├── Redis (task queue)
    ├── Orchestrator (populates Redis from builds)
    │   └── Build artifacts (task directory)
    └── Task Loop (polls Redis)

Seed Output
    └── Corpus Root (libcrs submit directory)
```

**Removed dependencies:**
- Fuzzer Build (still needed for other purposes, but not fuzzer-bot)
- Crash Queue (no crashes without fuzzer)
- POV Directory (no POVs without fuzzer)

## Service Architecture

### Current (Full OSS-CRS)

```
orchestrator → Redis
                 ↓
    ┌────────────┼────────────┐
    ↓            ↓            ↓
fuzzer-bot  coverage-bot  seed-gen
    ↓            ↓            ↓
 (POVs)     (coverage)    (seeds)
    ↓                         ↓
libcrs POV              libcrs seed
```

### New (Standalone Seedgen)

```
orchestrator → Redis
                 ↓
         ┌──────┴──────┐
         ↓             ↓
   coverage-bot    seed-gen
         ↓             ↓
    (coverage)     (seeds)
                       ↓
                  libcrs seed
```

**Removed:** fuzzer-bot, POV submission path

## Task Type Distribution

### Current Probabilities

**Full mode:**
- seed-init: 5%
- vuln-discovery: 35%
- seed-explore: 60%

**Delta mode:**
- seed-init: 5%
- vuln-discovery: 45%
- seed-explore: 50%

### New Probabilities

**Full mode:**
- seed-init: 40%
- seed-explore: 60%

**Delta mode:**
- seed-init: 40%
- seed-explore: 60%

**Rationale:** Without vuln-discovery (which tests POVs), redistribute probability to seed-init for broader exploration.

## MVP Recommendation

### Phase 1: Remove Fuzzer Components

**Priority:** Critical
**Effort:** Low

1. Remove `fuzzer-bot` from `crs.yaml`
2. Remove POV directory registration from `buttercup_entrypoint` (line 116)
3. Set `crash_submit=None` in `SeedGenBot.__init__()` (already optional)
4. Remove vuln-discovery task selection from `sample_task()`

**Result:** Seedgen runs without fuzzer, no POV generation

### Phase 2: Verify Seed Submission

**Priority:** Critical
**Effort:** Low

1. Verify `CORPUS_ROOT` points to `/artifacts/corpus`
2. Verify `libcrs register-submit-dir seed "$CORPUS_DIR"` runs (line 143)
3. Test that `corp.copy_corpus()` writes to correct location

**Result:** Seeds reach competition API via libcrs

### Phase 3: Adjust Task Distribution

**Priority:** Medium
**Effort:** Low

1. Update `sample_task()` probabilities (remove vuln-discovery, increase seed-init/explore)
2. Test task selection works with two tasks instead of three

**Result:** Better task distribution without vuln-discovery

## Deferred Features

| Feature | Why Defer | When to Add |
|---------|-----------|-------------|
| **Vuln-discovery without fuzzer** | Requires POV verification mechanism | If static-only POV validation added |
| **Remote corpus sync** | Not needed for single-node deployment | If multi-node seedgen added |
| **Crash deduplication** | No crashes without fuzzer | Never for standalone seedgen |
| **SARIF hints** | Only useful for vuln-discovery | If vuln-discovery re-enabled |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Built-in fuzzing** | Scope creep, defeats purpose of standalone tool | Use full Buttercup if fuzzing needed |
| **POV validation** | Requires fuzzer infrastructure | Remove vuln-discovery task entirely |
| **Multi-node corpus sync** | Unnecessary complexity for OSS-CRS | Single node is sufficient |
| **Custom submission logic** | Reinventing libcrs | Use `libcrs register-submit-dir` |

## Sources

**Internal codebase analysis:**
- `/home/andrew/post/buttercup-bugfind/seed-gen/src/buttercup/seed_gen/seed_gen_bot.py` - Main bot logic
- `/home/andrew/post/buttercup-bugfind/seed-gen/src/buttercup/seed_gen/vuln_base_task.py` - POV/crash handling
- `/home/andrew/post/buttercup-bugfind/common/src/buttercup/common/corpus.py` - Corpus management
- `/home/andrew/post/buttercup-bugfind/oss-crs/bin/buttercup_entrypoint` - Service entrypoint
- `/home/andrew/post/buttercup-bugfind/oss-crs/crs.yaml` - Service definitions
- `/home/andrew/post/buttercup-bugfind/fuzzer/src/buttercup/fuzzing_infra/coverage_bot.py` - Coverage collection

**Confidence:** HIGH - Based on direct codebase inspection and existing deployment patterns.

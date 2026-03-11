# Project Research Summary

**Project:** Buttercup Seedgen Standalone (OSS-CRS Extraction)
**Domain:** Microservices refactoring - extracting seed generation service from full CRS pipeline
**Researched:** 2026-03-10
**Confidence:** HIGH

## Executive Summary

The Buttercup OSS-CRS system currently operates as a complete Cyber Reasoning System with orchestrator, fuzzer-bot, coverage-bot, and seed-gen services coordinating through Redis to find and exploit vulnerabilities. The goal is to extract seed-gen as a standalone service that generates targeted test inputs and submits them directly to the competition API via libCRS, without requiring the fuzzing pipeline.

The research reveals that **minimal code changes are needed** because the seed submission mechanism is already implemented correctly. Seeds are written to a corpus directory and automatically submitted by a libCRS background watcher. The primary work involves removing fuzzer-bot from service definitions and cleaning up POV-related infrastructure. The architecture already supports this extraction because services communicate exclusively through Redis with no direct dependencies.

The critical risks center on orphaned queue consumers (seedgen reading from crash queues that fuzzer-bot no longer populates), implicit corpus dependencies (coverage-bot expecting fuzzer-generated inputs), and configuration drift in the shared entrypoint script. However, these risks are well-understood and preventable through systematic dependency mapping before service removal.

## Key Findings

### Recommended Stack

**Current architecture is already optimal for standalone operation.** The existing technology choices (Redis for coordination, libCRS for submission, file-based corpus management) were designed for distributed operation and require no replacement.

**Core technologies:**
- **Redis**: Message broker and shared state store — provides task discovery (HarnessWeights), build artifact location (BuildMap), and coverage guidance (CoverageMap) without tight service coupling
- **libCRS CLI**: Competition API integration via `register-submit-dir` — background watcher automatically submits seeds written to monitored directories, decoupling generation from submission
- **Corpus file system**: Hash-based seed storage — SHA256 filenames provide automatic deduplication, directory watching enables submission, simple debugging
- **Docker multi-stage builds**: Service isolation via buttercup-runner.Dockerfile — single Dockerfile with service-specific entrypoint routing allows component removal by deleting builder stages
- **Protobuf shared messages**: BuildType, BuildMap, HarnessWeights — retained services still need BuildType.FUZZER enum for harness processing despite fuzzer-bot removal

**Critical finding:** No new technologies needed. The extraction is a subtraction problem, not an addition problem.

### Expected Features

**Seed generation is already feature-complete for standalone operation.** The current implementation includes all table stakes features and the only required changes are removals of fuzzer-specific capabilities.

**Must keep (core seed generation):**
- Seed-init task (40% probability) — generates initial seeds from harness analysis
- Seed-explore task (60% probability) — targets specific functions based on coverage data
- CodeQuery integration — semantic code navigation for context gathering
- Coverage-based targeting — FunctionSelector uses CoverageMap from coverage-bot
- LLM integration (Claude/GPT) — generates seeds via prompt-based analysis
- Sandbox execution — safe execution of LLM-generated Python code
- Redis task coordination — discovers work via HarnessWeights, reads builds from BuildMap

**Must remove (fuzzer-specific):**
- Vuln-discovery tasks (35-45% probability in current system) — tests POVs which requires fuzzer infrastructure
- POV submission path — `libCRS register-submit-dir pov` registration in entrypoint
- Crash handling — CrashSubmit class, crash_queue, crash_set infrastructure
- Fuzzer-bot service — entire service definition in crs.yaml and entrypoint case

**Modified output behavior:**
- Seeds currently written to `/artifacts/<task_id>/corpus_<harness>/` for fuzzer-bot consumption
- libCRS watcher already monitors `/artifacts/corpus/` for submission (configured in seedgen entrypoint line 143)
- **No code changes needed** to seed-gen bot itself — Corpus.copy_corpus() already writes to correct location

**Defer (not needed for standalone):**
- Multi-node corpus synchronization — single seed-gen instance writes directly to submission directory
- Remote corpus sync logic — Corpus class has sync_to_remote() but not needed without fuzzer coordination
- SARIF integration — static analysis hints only useful for vuln-discovery tasks

### Architecture Approach

**Services communicate exclusively through Redis with no direct inter-service calls.** This design already supports extraction because removing fuzzer-bot doesn't break API contracts or shared volumes between seed-gen and other services. The corpus flow is file-based with libCRS watching directories, not service-to-service messaging.

**Major components to retain:**
1. **redis** — Message broker providing HarnessWeights (task discovery), BuildMap (artifact location), CoverageMap (targeting guidance)
2. **orchestrator** — Populates Redis from disk artifacts downloaded by libCRS, registers FUZZER and COVERAGE builds
3. **coverage-bot** — Measures code coverage to populate CoverageMap, informs seed-gen's FunctionSelector which functions to target
4. **seed-gen** — Generates targeted inputs via LLM analysis, writes to corpus directory for libCRS submission

**Data flow (target state):**
```
libCRS API (downloads builds)
    ↓
orchestrator → Redis (BuildMap, HarnessWeights)
    ↓
coverage-bot → Redis (CoverageMap)
    ↓
seed-gen → /artifacts/corpus/ (hash-named seed files)
    ↓
libCRS watcher → Competition API (automatic submission)
```

**Removed components:**
- **fuzzer-bot** — consumed seeds and generated POVs, no longer needed
- **Shared corpus sync** — `libCRS register-shared-dir` removed, single seed-gen writes directly
- **POV submission** — no POV generation without fuzzer infrastructure

**Critical architectural insight:** The Redis-mediated coordination pattern means services are loosely coupled. Removing fuzzer-bot doesn't cascade because seed-gen discovers tasks independently from HarnessWeights, not from fuzzer-bot notifications.

### Critical Pitfalls

1. **Orphaned Redis queue consumers** — Seedgen contains crash_queue and crash_set infrastructure (lines 56-57 in seed_gen_bot.py) that expects fuzzer-bot to populate crash data. When fuzzer is removed, these queues have no producer but seedgen still initializes them. **Prevention:** Remove CrashSubmit initialization, crash_queue, and crash_set from seed_gen_bot.py in Phase 1. Disable vuln-discovery task selection (35-45% probability currently) or strip crash handling entirely.

2. **POV vs. seed submission confusion** — The entrypoint registers two submit directories: POVs (line 116) and seeds (line 117 for fuzzer, line 143 for seedgen). Developers assume "no fuzzer = no POVs" but seedgen's vuln-discovery tasks ALSO generate POVs (35-45% task probability). **Prevention:** Decide POV scope upfront in Phase 0. If POVs out of scope, remove vuln-discovery from task distribution AND remove POV registration from seedgen entrypoint. If POVs in scope, keep both registrations.

3. **Shared corpus directory implicit coupling** — Coverage-bot measures coverage by running harnesses with corpus inputs. In the full pipeline, fuzzer-bot populates the corpus heavily. When fuzzer is removed, coverage-bot runs against a sparse corpus (only seedgen outputs), potentially reporting artificially low metrics. **Prevention:** Verify coverage-bot corpus source in Phase 1. Ensure seedgen writes ALL generated seeds to corpus, not filtering for quality. Document expected coverage drop as acceptable baseline.

4. **Docker build cache contains dead code** — The buttercup-runner.Dockerfile has a fuzzer-builder stage (lines 38-65) that's copied into the final runtime stage (lines 121-123). Removing fuzzer-bot from crs.yaml doesn't remove the ~200MB of unused Python packages and binaries. **Prevention:** Delete fuzzer-builder stage, remove fuzzer COPY commands, remove /app/fuzzer/.venv/bin from PATH (line 133), run `docker system prune --volumes` to clear cache.

5. **Environment variable configuration drift** — The single Dockerfile, multi-service pattern (RUN_TYPE routing in buttercup_entrypoint) creates shared initialization logic. Fuzzer-bot's entrypoint block may contain setup that seedgen also needs (shared corpus registration, environment variables). **Prevention:** Inventory ALL environment variables in buttercup_entrypoint per RUN_TYPE before fuzzer removal. Move shared setup logic from fuzzer-bot block to seedgen block if needed.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 0: Requirements Clarification (1 hour)
**Rationale:** Critical scope decision that affects all subsequent phases
**Delivers:** Explicit decision on whether POV generation is in scope for standalone seedgen
**Addresses:** POV submission confusion (Pitfall 2)
**Decision needed:**
- If POVs in scope: Keep vuln-discovery tasks, maintain POV submit-dir registration
- If POVs out of scope: Remove vuln-discovery entirely, simplify to seed-only
**Recommended:** Remove POVs — standalone seedgen should focus on seed quality, not vulnerability discovery

### Phase 1: Service Removal (4-6 hours)
**Rationale:** Core extraction work with well-defined scope and low risk
**Delivers:**
- Fuzzer-bot removed from crs.yaml service definitions
- Fuzzer case removed from buttercup_entrypoint
- POV registration removed from entrypoint (if Phase 0 decides POVs out of scope)
- Fuzzer-builder stage removed from Dockerfile
- Seeds successfully submitted via libCRS watcher
**Addresses:**
- Features: Remove fuzzer-bot, POV submission, crash handling
- Pitfalls: Docker dead code (Pitfall 4), environment drift (Pitfall 5)
**Avoids:** Service removal without Dockerfile cleanup (technical debt pattern)
**Validation:**
- `docker-compose up` starts only redis, orchestrator, coverage-bot, seed-gen
- Seeds appear in `/artifacts/corpus/` with hash-based names
- libCRS logs show successful seed submission to competition API
- No POV-related directories created

### Phase 2: Code Cleanup (2-3 hours)
**Rationale:** Remove dead code paths and orphaned dependencies from seed-gen
**Delivers:**
- CrashSubmit, crash_queue, crash_set removed from seed_gen_bot.py
- Vuln-discovery tasks removed from task distribution
- Task probabilities updated (seed-init: 40%, seed-explore: 60%)
- Crash directory handling removed from corpus.py
**Addresses:**
- Pitfalls: Orphaned queue consumers (Pitfall 1), POV submission confusion (Pitfall 2)
**Uses:** Python code refactoring, pytest for validation
**Validation:**
- All tests pass in seed-gen component (`cd seed-gen && uv run pytest`)
- No references to crash_queue, crash_set in retained code
- Task distribution sums to 100% with only seed-init and seed-explore

### Phase 3: Dependency Audit (1-2 hours)
**Rationale:** Verify protobuf, Redis, and corpus dependencies are correct
**Delivers:**
- Protobuf enum audit confirms BuildType.FUZZER is still needed
- Redis data structure usage documented (which services read/write which keys)
- Coverage-bot corpus dependency validated
**Addresses:**
- Pitfalls: Protobuf message definitions (Pitfall 2), shared corpus coupling (Pitfall 3)
**Implements:** Dependency mapping pattern from microservices extraction research
**Validation:**
- `grep -r "BuildType" seed-gen/ orchestrator/ coverage-bot/` shows all enum usage
- `grep -r "QueueFactory\|crash_queue" seed-gen/` returns no results
- Coverage-bot successfully populates CoverageMap with seedgen-only corpus

### Phase 4: Documentation and Testing (2-3 hours)
**Rationale:** Ensure deployment works end-to-end and is documented for future developers
**Delivers:**
- Updated README in oss-crs/ with standalone seedgen architecture diagram
- Deployment instructions for seedgen-only mode
- End-to-end integration test from task download → seed generation → API submission
**Addresses:**
- UX pitfall: Confusing metrics/dashboards after fuzzer removal
- Documentation gap: Expected coverage drop without fuzzer
**Validation:**
- Fresh deployment from scratch completes successfully
- Seed submission logs show seeds reaching competition API
- Documentation accurately describes current behavior (no fuzzer references)

### Phase Ordering Rationale

- **Phase 0 before Phase 1:** POV scope decision affects entrypoint changes (whether to keep POV submit-dir registration) — must resolve ambiguity before code changes
- **Phase 1 before Phase 2:** Service removal must happen before code cleanup to avoid orphaned references to removed services in configuration
- **Phase 2 before Phase 3:** Code cleanup removes crash handling before dependency audit to get accurate picture of what dependencies remain
- **Phase 3 before Phase 4:** Dependency audit must validate architecture before documenting it (avoid documenting incorrect assumptions)

**Dependencies discovered:**
- Coverage-bot depends on corpus inputs (currently from fuzzer AND seedgen, will become seedgen-only)
- Seed-gen depends on BuildType.FUZZER enum despite fuzzer-bot removal (still processing fuzzer harnesses)
- libCRS watcher depends on correct CORPUS_DIR environment variable in seedgen entrypoint

**Grouping rationale:**
- Phase 1 groups all service definition changes (crs.yaml, Dockerfile, entrypoint) to minimize deployment cycles
- Phase 2 isolates Python code changes to seed-gen component for focused testing
- Phase 3 is cross-component validation that requires Phase 1-2 stability

**Pitfall avoidance:**
- "Looks done but isn't" checklist from PITFALLS.md maps directly to phase completion criteria
- Recovery strategies are low-cost (mostly config/env fixes) because phases proceed incrementally

### Research Flags

**Phases with standard patterns (skip research-phase):**
- **Phase 1:** Service removal — well-documented in microservices extraction research, clear checklist from PITFALLS.md
- **Phase 2:** Code cleanup — standard Python refactoring, existing test suite provides validation
- **Phase 4:** Documentation — straightforward architecture description based on implemented changes

**Phases with implementation validation needs (not research):**
- **Phase 3:** Dependency audit — requires runtime testing (coverage metrics with seedgen-only corpus), not desk research

**No phases need `/gsd:research-phase`** — all information needed for implementation is contained in the four research files. The work is refactoring existing code with well-understood patterns, not building new capabilities with uncertain approaches.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All technologies observed directly in codebase, no external API integration needed |
| Features | HIGH | Feature requirements derived from existing implementation, not speculation about user needs |
| Architecture | HIGH | Data flow traced through actual code paths (Redis keys, file operations), not inferred from documentation |
| Pitfalls | HIGH | Based on microservices extraction research patterns applied to observed codebase structure |

**Overall confidence:** HIGH

All research is based on direct codebase analysis and established microservices patterns. The only external dependency is libCRS (competition infrastructure CLI), which is already in use and observed via entrypoint script. No untested assumptions about third-party APIs or undocumented behavior.

### Gaps to Address

**libCRS watcher implementation details** — How does `register-submit-dir` detect new files? Polling vs inotify? What is the submission batch size and retry logic?
- **Impact:** Low — interface is well-defined (write to directory, libCRS handles submission)
- **Mitigation:** Monitor `/tmp/seed_submit.log` in Phase 1 validation to verify submission success
- **When to address:** Only if submission reliability becomes an issue in production

**Corpus root configuration variable** — `BUTTERCUP_SEED_GEN_SERVER__CORPUS_ROOT` is set in entrypoint (line 121) but appears unused in seedgen code
- **Impact:** Low — seeds are written to correct location regardless
- **Mitigation:** Audit seed_gen/config.py in Phase 3 to determine if variable has undocumented usage
- **When to address:** Phase 3 dependency audit

**Coverage metrics baseline shift** — Unknown how much coverage will drop when fuzzer corpus contributions stop
- **Impact:** Medium — users may perceive seedgen as "broken" if coverage drops significantly
- **Mitigation:** Measure coverage before/after fuzzer removal, document expected delta in README
- **When to address:** Phase 4 testing and documentation

**Seed generation quality without fuzzer feedback** — Current system may use fuzzer-discovered crashes to inform seedgen targeting
- **Impact:** Medium — seed quality may degrade without fuzzer-driven exploration
- **Mitigation:** Monitor seed submission rate and coverage growth in standalone mode
- **When to address:** Post-deployment monitoring, not blocking for initial extraction

## Sources

All research is based on codebase analysis (HIGH confidence):

### Primary (Codebase — HIGH confidence)
- `/home/andrew/post/buttercup-bugfind/oss-crs/bin/buttercup_entrypoint` — libCRS CLI usage patterns, service initialization
- `/home/andrew/post/buttercup-bugfind/oss-crs/crs.yaml` — service definitions (redis, orchestrator, fuzzer-bot, coverage-bot, seed-gen)
- `/home/andrew/post/buttercup-bugfind/oss-crs/orchestrator.py` — Redis population logic (BuildMap, HarnessWeights)
- `/home/andrew/post/buttercup-bugfind/seed-gen/src/buttercup/seed_gen/seed_gen_bot.py` — main bot logic, task distribution, crash handling
- `/home/andrew/post/buttercup-bugfind/seed-gen/src/buttercup/seed_gen/config.py` — environment variable configuration
- `/home/andrew/post/buttercup-bugfind/common/src/buttercup/common/corpus.py` — corpus management, hash-based storage
- `/home/andrew/post/buttercup-bugfind/common/src/buttercup/common/maps.py` — Redis data structures
- `/home/andrew/post/buttercup-bugfind/fuzzer/src/buttercup/fuzzing_infra/coverage_bot.py` — coverage measurement
- `/home/andrew/post/buttercup-bugfind/fuzzer/src/buttercup/fuzzing_infra/fuzzer_bot.py` — fuzzing logic (to be removed)
- `/home/andrew/post/buttercup-bugfind/oss-crs/dockerfiles/buttercup-runner.Dockerfile` — multi-stage build with fuzzer-builder

### Secondary (Microservices Patterns — HIGH confidence)
- [Refactoring Towards Microservices: Preparing the Ground for Service Extraction](https://arxiv.org/html/2510.03050) — Dependency mapping before extraction
- [How to break a Monolith into Microservices](https://martinfowler.com/articles/break-monolith-into-microservices.html) — Dependency elimination patterns
- [Redis in Microservices Architecture: Patterns and Anti-Patterns](https://reintech.io/blog/redis-microservices-patterns-antipatterns) — Queue consumer coupling
- [How to Use Redis Lists for Message Queues](https://oneuptime.com/blog/post/2026-01-25-redis-lists-message-queues/view) — Message loss patterns
- [How to Handle Protocol Buffer Evolution](https://oneuptime.com/blog/post/2026-01-24-protocol-buffer-evolution/view) — Schema evolution without breaking changes

### Tertiary (libCRS — MEDIUM confidence)
- libCRS is AIxCC competition infrastructure (not open-source)
- Interface observed via buttercup_entrypoint usage patterns
- Behavior inferred from log file patterns and directory watching
- **Confidence limitation:** Implementation details unknown, only interface contract observed

---
*Research completed: 2026-03-10*
*Ready for roadmap: yes*

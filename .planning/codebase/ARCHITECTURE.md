# Architecture

**Analysis Date:** 2026-03-10

## Pattern Overview

**Overall:** Distributed microservices architecture using message-driven asynchronous processing with Redis queues as the central coordination backbone.

**Key Characteristics:**
- **Queue-driven coordination**: Redis-based reliable queues with consumer groups for distributed task processing
- **Microservice isolation**: Each component (fuzzer, patcher, seed-gen, etc.) runs independently and communicates via queues
- **Protobuf serialization**: Structured message formats for reliable inter-service communication
- **Task-centric workflow**: All operations center around `Task` objects with lifecycle management through task registry
- **Container-native**: Kubernetes-orchestrated microservices with shared storage volumes and network isolation

## Layers

**API Layer:**
- Purpose: External task submission and status monitoring
- Location: `orchestrator/src/buttercup/orchestrator/task_server/`
- Contains: FastAPI REST server, HTTP Basic auth, task submission endpoints
- Depends on: Redis (task queue), task registry
- Used by: Competition API, external clients

**Orchestration Layer:**
- Purpose: Central workflow coordination and state machine management
- Location: `orchestrator/src/buttercup/orchestrator/scheduler/`, `orchestrator/src/buttercup/orchestrator/downloader/`
- Contains: Scheduler (state transitions, patch coordination), Downloader (source acquisition), Cancellation handler
- Depends on: Multiple queues (build, ready, patch, crash), task registry, build map, harness weights
- Used by: All processing components (pulls tasks via reliable queues)

**Vulnerability Discovery Layer:**
- Purpose: Find vulnerabilities through fuzzing and seed generation
- Location: `fuzzer/src/buttercup/fuzzing_infra/`, `seed-gen/src/buttercup/seed_gen/`
- Contains: FuzzerBot, BuildBot, CoverageBot, TracerBot (fuzzer), SeedGenBot with task variants (seed-gen)
- Depends on: BuildOutput queue, ChallengeTask, CodeQuery (program analysis), crash corpus
- Used by: Produces crashes → traced vulnerabilities → patcher pipeline

**Patch Generation Layer:**
- Purpose: Generate and validate security patches for vulnerabilities
- Location: `patcher/src/buttercup/patcher/`
- Contains: Patcher orchestrator, PatcherLeaderAgent (multi-agent LLM coordination), patch agents
- Depends on: ConfirmedVulnerability queue, ChallengeTask, LLM (OpenAI/Anthropic via LiteLLM), program analysis
- Used by: Produces patches → submission bundle → competition API

**Analysis Layer:**
- Purpose: Semantic code understanding for targeted fuzzing and patching
- Location: `program-model/src/buttercup/program_model/`
- Contains: CodeQuery wrapper, function/type extraction, codebase indexing
- Depends on: ChallengeTask, Tree-sitter/CodeQuery runtime
- Used by: Seed-gen (function selection), patcher (patch validation)

**Common Infrastructure:**
- Purpose: Shared utilities, message definitions, queue abstraction, task lifecycle
- Location: `common/src/buttercup/common/`
- Contains: Protobuf definitions, ReliableQueue (Redis consumer groups), ChallengeTask (task I/O), logging, telemetry, maps (build/harness registry)
- Depends on: Redis, Protobuf runtime
- Used by: All components

## Data Flow

**Task Ingestion & Preparation:**

1. Competition API submits `TaskDownload` message to `orchestrator_download_tasks_queue`
2. Downloader consumes from queue, downloads sources (repo, fuzz tooling, optional diff)
3. Downloader verifies SHA256, extracts tarballs, creates read-only task directory structure
4. Downloader publishes `TaskReady` message to `tasks_ready_queue` (indexed by task_id)
5. Scheduler monitors task registry for new ready tasks

**Vulnerability Discovery (Concurrent pipelines per harness):**

1. Scheduler distributes weighted harnesses to fuzzer via `HarnessWeights` map
2. BuildBot consumes `BuildRequest` from queue, compiles fuzzing harness, publishes `BuildOutput`
3. FuzzerBot (or CoverageBot) reads `BuildOutput`, runs fuzzing, finds crashes
4. FuzzerBot publishes `Crash` messages to `fuzzer_crash_queue` (unordered discovery)
5. Crashes accumulated in corpus per (task_id, harness_name) pair
6. SeedGenBot processes weighted harnesses, generates/explores seed inputs to discover vulnerabilities
7. When vulnerability confirmed: TracerBot re-traces crash with debug symbols, publishes `TracedCrash` + `ConfirmedVulnerability`

**Patch Generation:**

1. Scheduler monitors `confirmed_vulnerabilities_queue` for `ConfirmedVulnerability` messages
2. Patcher consumes vulnerability with crash stack traces
3. PatcherLeaderAgent uses multi-agent framework:
   - Analyzer agent: understands vulnerability from stack trace + code context
   - Generator agent: uses LLM to propose patches
   - Validator agents: test patches against original crash inputs
4. Patcher publishes `Patch` message to `patches_queue`
5. Scheduler consumes patch, coordinates validation

**Submission & Feedback:**

1. Scheduler assembles patches + crashes into `Bundle` submission
2. Scheduler publishes bundle to Competition API (includes SARIF for vulnerability details)
3. Scheduler monitors Competition API responses for pass/fail feedback
4. Failed patches trigger retry cycle (up to `patch_submission_retry_limit` attempts)
5. Successful patches accumulate in submission tracking

**State Management:**

- **Task Registry** (Redis hash): Central source of truth for task lifecycle
  - Keys: task_id → {status, metadata, cancelled_flag, deadline}
  - Updated by: Downloader (READY), Scheduler (state transitions), Cancellation handler

- **Build Map** (Redis hash): Maps task_id + build_type → list of BuildOutput
  - Built by: BuildBot after compilation
  - Consumed by: FuzzerBot, CoverageBot, TracerBot (required_builds check)

- **Harness Weights** (Redis sorted set): Prioritization of fuzzing targets
  - Built by: Scheduler based on vulnerability discovery progress
  - Consumed by: FuzzerBot, SeedGenBot, CoverageBot (weighted random selection)

- **Crash Set** (Redis set per task): Deduplicated crash tokens for idempotency
  - Updated by: FuzzerBot on crash discovery
  - Checked by: SeedGenBot to avoid reprocessing same crashes

## Key Abstractions

**ReliableQueue (Generic over Protobuf Message types):**
- Purpose: Message-oriented queue with at-least-once delivery semantics
- Examples: `QueueFactory.create(QueueNames.BUILD, GroupNames.BUILDER_BOT)` → `ReliableQueue[BuildRequest]`
- Pattern: Redis XREAD consumer groups with manual acknowledgment via XACK
- Guarantees: Messages remain in queue until `acknowledge()` called, preventing loss on worker crash

**TaskLoop (Abstract base class):**
- Purpose: Common pattern for worker bots that process weighted harnesses
- Examples: FuzzerBot, CoverageBot, TracerBot, SeedGenBot all inherit from TaskLoop
- Pattern: `required_builds()` declares build dependencies, `run_task()` processes WeightedHarness with available builds
- Used in: Implements weighted random selection and build validation before task execution

**ChallengeTask:**
- Purpose: Abstract read-only and read-write access to task source code and build artifacts
- Examples: `task.get_rw_copy(work_dir=td)` creates isolated copy for modification
- Pattern: Wraps task directory, provides methods for accessing source, project YAML, build directory
- Used in: Every bot that needs to inspect or modify task sources

**Scheduler State Machine:**
- Purpose: Coordinates multi-stage task lifecycle with resilience to component failures
- States: WAIT_BUILD → WAIT_FUZZ → WAIT_PATCH → (WAIT_PATCH_VALIDATION) → SUBMIT_BUNDLE → (retry or complete)
- Pattern: Checks task registry for state, emits queue messages, monitors downstream queues for completion
- Resilience: Cached task status, timeout-based retry, cancellation monitoring

## Entry Points

**Task Server REST API:**
- Location: `orchestrator/src/buttercup/orchestrator/task_server/server.py`
- Triggers: HTTP POST /tasks (from competition API)
- Responsibilities: Validate credentials, insert TaskDownload into queue, return 202 Accepted

**Task Downloader:**
- Location: `orchestrator/src/buttercup/orchestrator/downloader/downloader.py`
- Triggers: Consumes from `orchestrator_download_tasks_queue`
- Responsibilities: Download sources, verify SHA256, extract tarballs, publish TaskReady

**Scheduler:**
- Location: `orchestrator/src/buttercup/orchestrator/scheduler/scheduler.py`
- Triggers: Polling on task registry changes and queue readiness
- Responsibilities: Coordinate entire vulnerability→patch→submit workflow, manage state transitions

**Build Bot:**
- Location: `fuzzer/src/buttercup/fuzzing_infra/builder_bot.py`
- Triggers: Consumes from `fuzzer_build_queue`
- Responsibilities: Compile fuzzing harness with sanitizers, publish BuildOutput

**Fuzzer Bot:**
- Location: `fuzzer/src/buttercup/fuzzing_infra/fuzzer_bot.py`
- Triggers: Polling via TaskLoop for available WeightedHarness with FUZZER BuildOutput
- Responsibilities: Execute libfuzzer, detect crashes, publish to crash queue

**Coverage Bot:**
- Location: `fuzzer/src/buttercup/fuzzing_infra/coverage_bot.py`
- Triggers: Polling via TaskLoop for available WeightedHarness with COVERAGE BuildOutput
- Responsibilities: Generate coverage reports, instrument metrics

**Tracer Bot:**
- Location: `fuzzer/src/buttercup/fuzzing_infra/tracer_bot.py`
- Triggers: Consumes from `fuzzer_crash_queue`
- Responsibilities: Re-trace crash with debug symbols, enrich stack trace, publish TracedCrash → ConfirmedVulnerability

**Seed Gen Bot:**
- Location: `seed-gen/src/buttercup/seed_gen/seed_gen_bot.py`
- Triggers: Polling via TaskLoop for available WeightedHarness with FUZZER BuildOutput
- Responsibilities: Generate targeted seed inputs based on code analysis and crash patterns

**Patcher:**
- Location: `patcher/src/buttercup/patcher/patcher.py`
- Triggers: Consumes from `confirmed_vulnerabilities_queue`
- Responsibilities: Invoke multi-agent LLM framework to generate and validate patches

**Program Model (Indexing):**
- Location: `program-model/src/buttercup/program_model/program_model.py`
- Triggers: Consumes from `index_queue` or invoked directly by seed-gen/patcher
- Responsibilities: Index codebase with CodeQuery, extract function/type information for analysis

## Error Handling

**Strategy:** Graceful degradation with queue-based retry, timeout-based backoff, and cancellation support.

**Patterns:**

1. **Queue Timeout & Retry**: Each queue has configurable timeout (e.g., `BUILD_TASK_TIMEOUT_MS = 15 min`). On worker crash, Redis automatically retries message after timeout.

2. **Crash-safe Queueing**: `ReliableQueue.acknowledge()` only removes message after successful processing. If worker dies mid-task, message remains for retry.

3. **Cancellation**: Scheduler polls `task_registry.should_stop_processing(task_id)` to gracefully exit before processing. TaskDelete messages trigger cancellation flag in registry.

4. **Build Failure Fallback**: If build fails, Scheduler waits for build timeout, then retries BuildRequest. Failing builds are logged but don't block harness processing (fallback to existing build or skip).

5. **Patch Retry Loop**: Failed patch submissions retry up to `patch_submission_retry_limit` (default 60). Each retry fetches fresh vulnerability data, allowing LLM to adapt.

6. **Memory Management**: FuzzerBot respects `-rss_limit_mb` from project.yaml, kills fuzzer on OOM. Crashes from OOM processes are skipped rather than erroring.

7. **Timeout Handling**: FuzzerBot/TracerBot enforce `timeout_seconds` for long-running operations. AIxCC helper.py times out at harness-defined timeout (default 120s).

## Cross-Cutting Concerns

**Logging:** OpenTelemetry instrumentation via `setup_package_logger()` in common. Components use standard Python logging module with structured log fields. Logs stream to SigNoz (local observability) or cloud logging.

**Validation:** ChallengeTask validates task directory structure on creation. Protobuf message validation at serialization/deserialization. BuildRequest validates build parameters before queueing.

**Authentication:** Task Server uses Argon2ID password hashing for HTTP Basic Auth. API key is UUID (username), token is 32+ char alphanumeric (hashed password). No inter-service auth (internal Kubernetes network assumed trusted).

**Telemetry:** OpenTelemetry spans for major operations (run_fuzzer, generate_patch, submit_bundle). Attributes include task_id, harness_name, build_type. Traces exported to SigNoz.

**Idempotency:** Crash tokens in CrashSet prevent duplicate processing. Patch internal_patch_id maps BuildRequest → BuildOutput → Patch for matching. Competition API submission uses idempotent bundle IDs.

---

*Architecture analysis: 2026-03-10*

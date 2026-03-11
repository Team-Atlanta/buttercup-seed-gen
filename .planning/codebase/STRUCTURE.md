# Codebase Structure

**Analysis Date:** 2026-03-10

## Directory Layout

```
buttercup-bugfind/
├── common/                    # Shared utilities and protobuf definitions
│   ├── src/buttercup/common/  # Reusable modules (queues, tasks, logging, maps)
│   ├── protos/                # Protobuf message definitions (msg.proto)
│   └── tests/                 # Unit tests for common modules
├── orchestrator/              # Central coordination (task submission, scheduling, patching)
│   ├── src/buttercup/orchestrator/
│   │   ├── task_server/       # REST API for task submission
│   │   ├── downloader/        # Download and prepare task sources
│   │   ├── scheduler/         # State machine coordination
│   │   └── pov_reproducer/    # POV reproduction service
│   └── test/                  # Integration tests
├── fuzzer/                    # Vulnerability discovery via fuzzing
│   ├── src/buttercup/fuzzing_infra/
│   │   ├── builder_bot.py     # Compile fuzzing harnesses
│   │   ├── fuzzer_bot.py      # Execute fuzzer and detect crashes
│   │   ├── coverage_bot.py    # Generate coverage metrics
│   │   ├── tracer_bot.py      # Re-trace crashes with debug symbols
│   │   └── corpus_merger.py   # Merge crash corpus across workers
│   └── tests/                 # Unit tests
├── seed-gen/                  # Intelligent seed/input generation
│   ├── src/buttercup/seed_gen/
│   │   ├── seed_gen_bot.py    # Main worker dispatching tasks
│   │   ├── task.py            # Task types and orchestration
│   │   ├── seed_init.py       # Initial seed generation
│   │   ├── seed_explore.py    # Seed exploration and mutation
│   │   ├── vuln_base_task.py  # Vulnerability-specific seed logic
│   │   └── function_selector.py # CodeQuery-based function selection
│   └── test/                  # Unit tests
├── patcher/                   # LLM-powered patch generation
│   ├── src/buttercup/patcher/
│   │   ├── patcher.py         # Main patcher orchestrator
│   │   ├── agents/            # Multi-agent LLM framework (leader, analyzer, generator, validator)
│   │   └── utils.py           # Patch input/output types
│   └── tests/                 # Unit tests
├── program-model/             # Semantic code analysis
│   ├── src/buttercup/program_model/
│   │   ├── codequery.py       # CodeQuery API wrapper and persistence
│   │   ├── program_model.py   # Main indexing orchestrator
│   │   ├── api/               # API server for codebase queries
│   │   └── utils/             # Helper utilities
│   └── tests/                 # Unit tests
├── fuzzer_runner/             # Fuzzer execution harness (OSS-Fuzz integration)
│   ├── src/                   # Fuzzer runner implementation
│   └── tests/                 # Tests
├── deployment/                # Kubernetes and local deployment
│   ├── k8s/                   # Helm charts for all services
│   ├── env.template           # Environment configuration template
│   └── Makefile               # Deployment commands
├── scripts/                   # Utility scripts
├── dev/                       # Local development configuration
├── common/protos/             # Protocol buffer definitions
├── oss-crs/                   # OSS-Fuzz integration module
├── Makefile                   # Root build commands (lint, test, deploy)
└── CLAUDE.md                  # Development guidelines
```

## Directory Purposes

**common/:**
- Purpose: Centralized shared code and message protocols
- Contains: Queue abstractions, task I/O, logging, Redis maps, protobuf generated code, telemetry
- Key files: `src/buttercup/common/queues.py` (ReliableQueue), `challenge_task.py` (task I/O), `task_registry.py` (state tracking)

**orchestrator/:**
- Purpose: Central hub for task coordination and external communication
- Contains: REST API, task downloading, scheduler state machine, submission coordination
- Key files: `task_server/server.py` (FastAPI app), `scheduler/scheduler.py` (state machine), `downloader/downloader.py` (source download)

**fuzzer/:**
- Purpose: Vulnerability discovery through automated fuzzing
- Contains: Compiler bots, fuzzer execution, coverage analysis, crash tracing
- Key files: `fuzzing_infra/builder_bot.py` (compile), `fuzzer_bot.py` (execute), `tracer_bot.py` (debug trace)

**fuzzer_runner/:**
- Purpose: Lightweight harness for executing fuzzers via subprocess
- Contains: OSS-Fuzz runner proxy, timeout management
- Used by: FuzzerBot, CoverageBot for isolated fuzzer execution

**seed-gen/:**
- Purpose: Intelligent test case generation for targeted fuzzing
- Contains: Multiple task types (init, explore, vuln discovery), LLM-based seed generation
- Key files: `seed_gen_bot.py` (dispatcher), `task.py` (base task), `vuln_discovery_full.py` (for full mode), `vuln_discovery_delta.py` (for delta mode)

**patcher/:**
- Purpose: LLM-powered security patch generation and validation
- Contains: Multi-agent framework (leader, analyzer, generator, validator agents)
- Key files: `patcher.py` (main orchestrator), `agents/leader.py` (agent coordinator)

**program-model/:**
- Purpose: Semantic understanding of source code for targeted analysis
- Contains: CodeQuery wrapper, codebase indexing, function/type extraction
- Key files: `codequery.py` (CodeQuery integration), `program_model.py` (indexing), `api/` (query server)

**deployment/k8s/:**
- Purpose: Kubernetes manifests and Helm charts for all services
- Contains: One Helm chart per service (task-server, scheduler, fuzzer-bot, etc.)
- Files: `charts/{service}/Chart.yaml`, `values.yaml`, `templates/deployment.yaml`

**deployment/:**
- Purpose: Configuration and orchestration for local and cloud deployment
- Contains: Makefile for deploy/undeploy, environment configuration, terraform for AKS
- Key files: `env.template` (environment vars), `Makefile` (deploy commands)

## Key File Locations

**Entry Points:**

- `orchestrator/src/buttercup/orchestrator/task_server/server.py`: FastAPI REST API listening on port 8000 (default)
- `orchestrator/src/buttercup/orchestrator/downloader/__cli__.py`: CLI entry point for downloader worker
- `orchestrator/src/buttercup/orchestrator/scheduler/__cli__.py`: CLI entry point for scheduler worker
- `fuzzer/src/buttercup/fuzzing_infra/builder_bot.py`: BuildBot worker (method: `run()`)
- `fuzzer/src/buttercup/fuzzing_infra/fuzzer_bot.py`: FuzzerBot worker (method: `run()`)
- `seed-gen/src/buttercup/seed_gen/_cli.py`: CLI entry point for seed-gen bot
- `patcher/src/buttercup/patcher/__cli__.py`: CLI entry point for patcher worker
- `program-model/src/buttercup/program_model/__cli__.py`: CLI entry point for indexing service

**Configuration:**

- `common/src/buttercup/common/challenge_task.py`: Task structure and file layout
- `orchestrator/src/buttercup/orchestrator/task_server/config.py`: TaskServer settings (host, port, redis_url)
- `orchestrator/src/buttercup/orchestrator/scheduler/config.py`: Scheduler settings
- `fuzzer_runner/src/buttercup/fuzzer_runner/config.py`: Fuzzer runner configuration
- `seed-gen/src/buttercup/seed_gen/config.py`: Seed-gen configuration
- `patcher/src/buttercup/patcher/config.py`: Patcher settings
- `program-model/src/buttercup/program_model/settings.py`: Program model settings

**Core Logic:**

- `common/src/buttercup/common/queues.py`: ReliableQueue implementation (Redis consumer groups)
- `common/src/buttercup/common/task_registry.py`: Task state and lifecycle tracking
- `common/src/buttercup/common/maps.py`: BuildMap and HarnessWeights (Redis-backed)
- `common/src/buttercup/common/challenge_task.py`: Read-only and read-write task access
- `orchestrator/src/buttercup/orchestrator/scheduler/scheduler.py`: State machine (100+ lines)
- `orchestrator/src/buttercup/orchestrator/scheduler/submissions.py`: Patch submission logic
- `fuzzer/src/buttercup/fuzzing_infra/fuzzer_bot.py`: Fuzzer execution (TaskLoop subclass)
- `seed-gen/src/buttercup/seed_gen/seed_gen_bot.py`: Seed generation dispatcher
- `patcher/src/buttercup/patcher/patcher.py`: Patcher orchestrator

**Testing:**

- `common/tests/`: Unit tests for shared modules
- `orchestrator/test/`: Integration tests (uses pytest)
- `fuzzer/tests/`: Fuzzer component tests
- `seed-gen/test/`: Seed-gen tests
- `patcher/tests/`: Patcher tests
- `program-model/tests/`: Program model tests

## Naming Conventions

**Files:**

- `{component}_bot.py`: Worker bot that consumes and processes queue items (builder_bot, fuzzer_bot, tracer_bot, merger_bot)
- `{component}.py`: Main orchestrator or entry point (patcher.py, downloader.py, scheduler.py)
- `__cli__.py`: Command-line interface entry point for executable components
- `config.py`: Component-specific Pydantic settings class
- `_pb2.py`: Generated protobuf Python files (in `datastructures/`)

**Directories:**

- `src/buttercup/{component}/`: Main source code for each component
- `agents/`: LLM agent classes (patcher/agents/)
- `prompt/`: LLM prompt templates (seed-gen/prompt/)
- `sandbox/`: Isolated execution environment (seed-gen/sandbox/)
- `clusterfuzz_*`: OSS-Fuzz integration utilities (clusterfuzz_env/, clusterfuzz_parser/)

**Functions/Classes:**

- `Bot` suffix: Worker classes that run task loops (FuzzerBot, CoverageBot, BuildBot)
- `TaskLoop` base class: Parent for worker bots
- `ReliableQueue[T]`: Generic queue typed to protobuf message
- `ChallengeTask`: Task directory abstraction
- Settings classes: Pydantic models for configuration (TaskServerSettings, SchedulerSettings)

## Where to Add New Code

**New Feature (e.g., new fuzzing strategy):**
- Primary code: `fuzzer/src/buttercup/fuzzing_infra/` (new bot class inheriting from TaskLoop)
- Tests: `fuzzer/tests/` (unit tests using pytest)
- Entry point: Add `__cli__.py` entry point if standalone worker
- Deployment: Add Helm chart in `deployment/k8s/charts/{new-bot}/`

**New Vulnerability Check/Analysis:**
- Implementation: `program-model/src/buttercup/program_model/` (new method in codequery.py or api/)
- Tests: `program-model/tests/`
- Usage: Called from patcher agents or seed-gen function_selector

**New Message Type:**
- Definition: `common/protos/msg.proto` (add new message)
- Regeneration: Run `cd common && uv run ../protoc.sh` from project root
- Queue: Add `QueueNames` enum entry in `common/src/buttercup/common/queues.py`
- Usage: Create `ReliableQueue[NewMessageType]` in consuming component

**New Scheduler State or Transition:**
- State machine: `orchestrator/src/buttercup/orchestrator/scheduler/scheduler.py`
- Submissions: `orchestrator/src/buttercup/orchestrator/scheduler/submissions.py` (if new submission type)
- Tests: `orchestrator/test/` (integration tests)

**New Configuration Parameter:**
- Define in component's `config.py` as Pydantic field
- Add to `deployment/env.template` for documentation
- Reference in CLAUDE.md COMMON DEVELOPMENT COMMANDS section

**Utilities/Helpers:**
- Shared across multiple components: `common/src/buttercup/common/utils.py` or `logger.py`
- Component-specific: `{component}/src/buttercup/{component}/utils.py`

## Special Directories

**crs_scratch/:**
- Purpose: Local working directory for task builds and fuzzing (created on first run)
- Generated: Yes (by downloader, builder_bot)
- Committed: No (git-ignored, contains build artifacts)

**deployment/k8s/charts/:**
- Purpose: Helm charts for Kubernetes deployment
- Generated: No (manually maintained)
- Committed: Yes

**common/src/buttercup/common/datastructures/:**
- Purpose: Generated protobuf Python files
- Generated: Yes (by `protoc.sh` from msg.proto)
- Committed: Yes (version-controlled for consistency)

**.planning/:**
- Purpose: GSD planning documents
- Generated: Yes (by `/gsd:map-codebase` command)
- Committed: Yes (tracked for reference)

**oss-crs/:**
- Purpose: OSS-Fuzz compatibility layer for AIxCC finals
- Generated: No (maintained source)
- Committed: Yes

---

*Structure analysis: 2026-03-10*

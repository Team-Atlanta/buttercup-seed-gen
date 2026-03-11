---
name: run-oss-crs
description: Build and run buttercup through oss-crs-6
---

# OSS-CRS Build & Run for Buttercup

This skill builds and runs the buttercup fuzzer through oss-crs-6.

## Working Directory

All commands run from `$OSS_CRS`.
If environment variable isn't set, try the following:
- `~/post/oss-crs-6`
- `~/post/oss-crs-2`
- `~/projects/oss-crs`
or crawl to see if you can find a dir.

For oss-fuzz directory, `$OSS_FUZZ`.
If environment variable isn't set, try the following:
- `~/post/oss-fuzz-clean`
- `~/projects/oss-fuzz`

For a cloned project repo, `$PROJECT_CLONE`.
If environment variable isn't set, try the following:
- `~/post/clone`
- `~/clone`

## Current Interface (oss-crs-6)

The current oss-crs-6 uses the `oss-crs` command with compose files.

**IMPORTANT:** Always `source .env` before running commands.

### CRS Configuration

Buttercup uses two configuration layers:
1. **CRS Definition** (`buttercup-bugfind/oss-crs/crs.yaml`) - Defines services, Dockerfiles, and capabilities
2. **Compose File** (`oss-crs-6/example/buttercup-bugfind/buttercup-compose.yaml`) - Specifies runtime resources and source location

### Prepare Command

Prepare the CRS (pull images, set up dependencies):

```bash
cd $OSS_CRS && source .env && uv run oss-crs prepare \
    --compose-file ./example/buttercup-bugfind/buttercup-compose.yaml
```

### Build Command

Build the target project:

```bash
cd $OSS_CRS && source .env && uv run oss-crs build-target \
    --compose-file ./example/buttercup-bugfind/buttercup-compose.yaml \
    --fuzz-proj-path $OSS_FUZZ/projects/aixcc/c/sanity-mock-c-delta-01 \
    --target-source-path $PROJECT_CLONE/mock-c
```

### Run Command

Run buttercup (LLM keys configured via .env and litellm-config.yaml):

```bash
cd $OSS_CRS && source .env && uv run oss-crs run \
    --compose-file ./example/buttercup-bugfind/buttercup-compose.yaml \
    --fuzz-proj-path $OSS_FUZZ/projects/aixcc/c/sanity-mock-c-delta-01 \
    --target-source-path $PROJECT_CLONE/mock-c \
    --target-harness fuzz_process_input_header
```

### Alternative Targets

**libxml2:**
```bash
# Build
cd $OSS_CRS && source .env && uv run oss-crs build-target \
    --compose-file ./example/buttercup-bugfind/buttercup-compose.yaml \
    --fuzz-proj-path $OSS_FUZZ/projects/aixcc/c/afc-libxml2-delta-01 \
    --target-source-path $PROJECT_CLONE/official-afc-libxml2

# Run
cd $OSS_CRS && source .env && uv run oss-crs run \
    --compose-file ./example/buttercup-bugfind/buttercup-compose.yaml \
    --fuzz-proj-path $OSS_FUZZ/projects/aixcc/c/afc-libxml2-delta-01 \
    --target-source-path $PROJECT_CLONE/official-afc-libxml2 \
    --target-harness html
```

## Usage

- `/run-oss-crs` or `/run-oss-crs build run` - Run prepare, build, and run sequentially
- `/run-oss-crs prepare` - Just prepare
- `/run-oss-crs build` - Just build (assumes prepared)
- `/run-oss-crs run` - Just run (assumes already built)

## Environment Variables

LLM API keys are configured via `.env` file (source it before running):
- Contains `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`
- LiteLLM config in `./example/buttercup-bugfind/litellm-config.yaml`

## Parameters

- `--compose-file` - Path to CRS compose YAML file
- `--fuzz-proj-path` - Path to target project (OSS-Fuzz format)
- `--target-source-path` - Path to source repo (if separate from OSS-Fuzz project)
- `--target-harness` - Harness name to run

## Interactive Run Behavior

When running the fuzzer:
1. Start the run command in the background
2. Wait for initial output (60-120 seconds) to confirm startup success
3. Look for these success indicators in the logs:
   - "Initializing codequery" - CodeQuery database loaded
   - "Running seed-gen task:" - Seed generation running
   - "Copied X files to corpus" - Seeds generated
4. After confirming success OR after timeout (2 minutes), ask user:
   - "Continue running?" - keep fuzzer going
   - "Stop now?" - stop and cleanup

## Stopping the Fuzzer

**IMPORTANT:** Always stop by killing the `oss-crs` process, not the docker containers:
```bash
pkill -f "oss-crs run"
```

The process handles container cleanup automatically. Do NOT run `docker stop` on containers directly - this can kill unrelated containers.

## Checking Fuzzer Success

### Container Logs

```bash
SEED_GEN=$(docker ps --filter "name=seed-gen" -q | head -1)
docker logs "$SEED_GEN" 2>&1 | tail -100
```

Look for these log messages:
- `"Initializing codequery"` - CodeQuery loaded successfully
- `"Running seed-gen task: seed-init"` - Initial seed generation
- `"Running seed-gen task: seed-explore"` - Coverage-guided seed generation
- `"Copied X files to corpus"` - Seeds produced

### Output Locations

Generated artifacts are in:
- `/artifacts/corpus/` - Fuzzing corpus (test inputs)
- `/artifacts/povs/` - Proof of Vulnerability files (crashes)

---

## Legacy Interface (oss-crs-2 with crs-compose)

The older oss-crs-2 uses the `crs-compose` command.

### Legacy Build Command

```bash
cd $OSS_CRS && uv run crs-compose build-target \
    --compose-file ./example_configs/buttercup-scan/buttercup-compose.yaml \
    --target-proj-path $OSS_FUZZ/projects/aixcc/c/sanity-mock-c-delta-01 \
    --target-repo-path $PROJECT_CLONE/mock-c \
    --no-checkout
```

### Legacy Run Command

```bash
cd $OSS_CRS && uv run crs-compose run \
    --compose-file ./example_configs/buttercup-scan/buttercup-compose.yaml \
    --target-proj-path $OSS_FUZZ/projects/aixcc/c/sanity-mock-c-delta-01 \
    --target-repo-path $PROJECT_CLONE/mock-c \
    --no-checkout \
    --target-harness fuzz_process_input_header
```

### Legacy Parameters

- `--target-proj-path` - Path to target project (deprecated, use `--fuzz-proj-path`)
- `--target-repo-path` - Path to source repo (deprecated, use `--target-source-path`)
- `--no-checkout` - Skip git checkout (no longer needed in oss-crs-6)

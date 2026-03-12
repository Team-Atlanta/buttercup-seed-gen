---
name: run-oss-crs
description: Build and run buttercup through oss-crs-6
---

# OSS-CRS Build & Run for Buttercup

This skill builds and runs the buttercup fuzzer through oss-crs-6.

## Working Directory

All commands run from `$OSS_CRS`.
If environment variable isn't set, use: `~/post/oss-crs-6`

For CRSBench benchmarks: `~/post/CRSBench/benchmarks/`

## Current Interface (oss-crs-6)

The current oss-crs-6 uses the `oss-crs` command with compose files.

**IMPORTANT:** Always `source .env` before running commands.

### Prepare Command

Prepare the CRS (pull images, set up dependencies):

```bash
cd ~/post/oss-crs-6 && source .env && uv run oss-crs prepare \
    --compose-file example/buttercup-bugfind/compose.yaml
```

### Build Command

Build the target project:

```bash
cd ~/post/oss-crs-6 && source .env && uv run oss-crs build-target \
    --compose-file example/buttercup-bugfind/compose.yaml \
    --fuzz-proj-path ~/post/CRSBench/benchmarks/afc-freerdp-delta-01
```

### Run Command

Run buttercup (LLM keys configured via .env):

```bash
cd ~/post/oss-crs-6 && source .env && uv run oss-crs run \
    --compose-file example/buttercup-bugfind/compose.yaml \
    --fuzz-proj-path ~/post/CRSBench/benchmarks/afc-freerdp-delta-01 \
    --target-harness TestFuzzCryptoCertificateDataSetPEM
```

### Example Targets

**sanity-mock-c-delta-01:**
```bash
cd ~/post/oss-crs-6 && source .env && uv run oss-crs build-target \
    --compose-file example/buttercup-bugfind/compose.yaml \
    --fuzz-proj-path ~/post/CRSBench/benchmarks/sanity-mock-c-delta-01

cd ~/post/oss-crs-6 && source .env && uv run oss-crs run \
    --compose-file example/buttercup-bugfind/compose.yaml \
    --fuzz-proj-path ~/post/CRSBench/benchmarks/sanity-mock-c-delta-01 \
    --target-harness fuzz_process_input_header
```

**afc-freerdp-delta-01:**
```bash
cd ~/post/oss-crs-6 && source .env && uv run oss-crs build-target \
    --compose-file example/buttercup-bugfind/compose.yaml \
    --fuzz-proj-path ~/post/CRSBench/benchmarks/afc-freerdp-delta-01

cd ~/post/oss-crs-6 && source .env && uv run oss-crs run \
    --compose-file example/buttercup-bugfind/compose.yaml \
    --fuzz-proj-path ~/post/CRSBench/benchmarks/afc-freerdp-delta-01 \
    --target-harness TestFuzzCryptoCertificateDataSetPEM
```

## Usage

- `/run-oss-crs` or `/run-oss-crs build run` - Run prepare, build, and run sequentially
- `/run-oss-crs prepare` - Just prepare
- `/run-oss-crs build` - Just build (assumes prepared)
- `/run-oss-crs run` - Just run (assumes already built)

## Parameters

- `--compose-file` - Path to CRS compose YAML file
- `--fuzz-proj-path` - Path to target project (CRSBench benchmark or OSS-Fuzz format)
- `--target-harness` - Harness name to run

## Stopping the Fuzzer

**IMPORTANT:** Always stop by killing the `oss-crs` process, not the docker containers:
```bash
pkill -f "oss-crs run"
```

The process handles container cleanup automatically. Do NOT run `docker stop` on containers directly.

## Checking Success

### Container Logs

```bash
SEED_GEN=$(docker ps --filter "name=seed-gen" -q | head -1)
docker logs "$SEED_GEN" 2>&1 | tail -100
```

**Success indicators:**
- `"Initializing codequery"` - CodeQuery loaded successfully
- `"Running seed-gen task: seed-init"` - Initial seed generation
- `"Generating seeds for challenge"` - LLM seed generation active
- `"Copied X files to corpus"` - Seeds produced

**Codequery active (using pre-built indexes):**
- `"Multiple harnesses found"` - CodeQuery queries working
- `"Getting context"` - Extracting code context for LLM

### Output Locations

Generated artifacts are in:
- `/artifacts/corpus/` - Fuzzing corpus (test inputs)
- `/artifacts/povs/` - Proof of Vulnerability files (crashes)

## Troubleshooting

**"No function coverage data found"** in seed-explore:
- Coverage-bot hasn't run yet or hasn't populated Redis
- seed-explore requires coverage data; seed-init works without it

**"Getting context" then nothing:**
- Check LLM configuration in `.env`
- LLM API keys must be set for seed generation

**"No code query package":**
- Codequery binaries missing in runner image
- Rebuild with `oss-crs prepare`

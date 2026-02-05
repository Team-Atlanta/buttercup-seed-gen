---
name: run-oss-crs
description: Build and run buttercup through oss-crs-2
---

# OSS-CRS Build & Run for Buttercup

This skill builds and runs the buttercup fuzzer through oss-crs-2.

## Working Directory

All commands run from `$OSS_CRS`.
If environment variable isn't set, try the following:
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

## Build Command

Build the project:

```bash
cd $OSS_CRS && uv run oss-bugfind-crs build \
    --project-image-prefix aixcc-afc \
    --oss-fuzz-dir $OSS_FUZZ \
    example_configs/buttercup-scan/ \
    aixcc/c/sanity-mock-c-delta-01 \
    $PROJECT_CLONE/mock-c
```

## Run Command

Run buttercup (requires `.env` with LITELLM_URL and LITELLM_KEY for LLM features):

```bash
cd $OSS_CRS && source .env && uv run oss-bugfind-crs run \
    --external-litellm \
    example_configs/buttercup-scan/ \
    aixcc/c/sanity-mock-c-delta-01 \
    fuzz_process_input_header
```

## Run with Diff (Delta Mode)

For bug-finding with a known vulnerable diff:

```bash
cd $OSS_CRS && source .env && uv run oss-bugfind-crs run \
    --external-litellm \
    --diff $OSS_FUZZ/projects/aixcc/c/sanity-mock-c-delta-01/.aixcc/ref.diff \
    example_configs/buttercup-scan/ \
    aixcc/c/sanity-mock-c-delta-01 \
    fuzz_process_input_header
```

When `--diff` is provided:
- The diff is mounted at `/ref.diff` in the container
- Buttercup triggers vulnerability discovery mode
- LLM analyzes the diff to identify vulnerabilities
- PoVs are generated targeting the vulnerable code paths

## Alternative Target: libxml2

Build libxml2:

```bash
cd $OSS_CRS && uv run oss-bugfind-crs build \
    --project-image-prefix aixcc-afc \
    --oss-fuzz-dir $OSS_FUZZ \
    example_configs/buttercup-scan/ \
    aixcc/c/afc-libxml2-delta-01 \
    $PROJECT_CLONE/official-afc-libxml2
```

Run libxml2 with html harness:

```bash
cd $OSS_CRS && source .env && uv run oss-bugfind-crs run \
    --external-litellm \
    example_configs/buttercup-scan/ \
    aixcc/c/afc-libxml2-delta-01 \
    html
```

## Usage

- `/run-oss-crs` or `/run-oss-crs build run` - Run both build and run sequentially
- `/run-oss-crs build` - Just build
- `/run-oss-crs run` - Just run (assumes already built)

## Environment Variables

The `.env` file in oss-crs-2 should contain:
- `LITELLM_URL` - LiteLLM proxy URL
- `LITELLM_KEY` - LiteLLM API key

## Parameters

- `example_configs/buttercup-scan/` - CRS config for buttercup
- `aixcc/c/sanity-mock-c-delta-01` - Target project config (mock-c)
- `aixcc/c/afc-libxml2-delta-01` - Target project config (libxml2)
- `fuzz_process_input_header` - Harness name for mock-c
- `html` - Harness name for libxml2
- `--external-litellm` - Use external LiteLLM proxy
- `--project-image-prefix aixcc-afc` - Docker image prefix
- `--oss-fuzz-dir` - Path to clean oss-fuzz checkout

## Interactive Run Behavior

When running the fuzzer:
1. Start the run command in the background
2. Wait for initial output (30-60 seconds) to confirm startup success
3. Look for these success indicators in the logs:
   - "Starting Buttercup CRS for harness:"
   - "Starting fuzzer with timeout="
   - "Fuzzing iteration X:" (continuous operation)
   - "New crash found:" (if finding bugs)
4. After confirming success OR after timeout (2 minutes), ask user:
   - "Continue running?" - keep fuzzer going
   - "Stop now?" - stop the container and cleanup
5. To stop the fuzzer, kill the `oss-bugfind-crs` process (NOT the docker containers directly):
   ```bash
   pkill -f "oss-bugfind-crs run"
   ```
   This automatically cleans up containers properly.

## Stopping the Fuzzer

**IMPORTANT:** Always stop by killing the `oss-bugfind-crs` process, not the docker containers:
```bash
pkill -f "oss-bugfind-crs run"
```

The process handles container cleanup automatically. Do NOT run `docker stop` on crs-run containers directly.

## Emergency Cleanup

Only if the process was killed improperly and containers are orphaned:
```bash
docker ps --filter "name=crs-run" -q | xargs -r docker stop
docker ps --filter "name=crs-run" -aq | xargs -r docker rm
```

## Checking Fuzzer Success

### Container Logs

Look for these log messages:
- `"Starting Buttercup CRS for harness:"` - Fuzzer starting
- `"LLM available: True"` - LLM seed generation enabled
- `"Delta mode: True"` - Vulnerability discovery mode active
- `"Running seed initialization"` - LLM generating seeds
- `"Generated X seeds"` - LLM produced seeds
- `"Starting fuzzing phase"` - ClusterFuzz fuzzing started
- `"Fuzzing iteration X:"` - Continuous fuzzing in progress
- `"New crash found:"` - Bug discovered
- `"Fuzzing complete after X iterations"` - Final results

```bash
CONTAINER=$(docker ps --filter "name=crs-run" -q | head -1)
docker logs $CONTAINER 2>&1 | grep -E "(Starting Buttercup|LLM available|Delta mode|Generated.*seeds|Fuzzing iteration|New crash|Fuzzing complete)"
```

### Output Locations

Generated artifacts are in:
- `/artifacts/corpus/` - Fuzzing corpus (test inputs)
- `/artifacts/povs/` - Proof of Vulnerability files (crashes)

View them with:
```bash
docker exec $CONTAINER ls -la /artifacts/corpus/
docker exec $CONTAINER ls -la /artifacts/povs/
```

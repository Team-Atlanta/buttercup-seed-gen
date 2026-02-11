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

## New Interface (crs-compose)

The new oss-crs-2 uses `crs-compose` with compose files.

### CRS Configuration

Buttercup uses two configuration layers:
1. **CRS Definition** (`buttercup-bugfind/oss-crs/crs.yaml`) - Defines services, Dockerfiles, and capabilities
2. **Compose File** (`oss-crs-2/example_configs/buttercup-scan/buttercup-compose.yaml`) - Specifies runtime resources and source location

### Prepare Command

Prepare the CRS (pull images, set up dependencies):

```bash
cd $OSS_CRS && uv run crs-compose prepare \
    --compose-file ./example_configs/buttercup-scan/buttercup-compose.yaml
```

### Build Command

Build the target project:

```bash
cd $OSS_CRS && uv run crs-compose build-target \
    --compose-file ./example_configs/buttercup-scan/buttercup-compose.yaml \
    --target-proj-path $OSS_FUZZ/projects/libxml2
```

### Run Command

Run buttercup (requires LLM API keys for LLM features):

```bash
export ANTHROPIC_API_KEY=<your-key>
export OPENAI_API_KEY=<your-key>
cd $OSS_CRS && uv run crs-compose run \
    --compose-file ./example_configs/buttercup-scan/buttercup-compose.yaml \
    --target-proj-path $OSS_FUZZ/projects/libxml2 \
    --target-harness xml
```

### Alternative Target: json-c

```bash
# Build
cd $OSS_CRS && uv run crs-compose build-target \
    --compose-file ./example_configs/buttercup-scan/buttercup-compose.yaml \
    --target-proj-path $OSS_FUZZ/projects/json-c

# Run
cd $OSS_CRS && uv run crs-compose run \
    --compose-file ./example_configs/buttercup-scan/buttercup-compose.yaml \
    --target-proj-path $OSS_FUZZ/projects/json-c \
    --target-harness json_parse_fuzzer
```

### Alternative Target: sanity-mock-c-delta-01 (with separate repo)

For targets where the source repo is separate from the OSS-Fuzz project:

```bash
# Build
cd $OSS_CRS && uv run crs-compose build-target \
    --compose-file ./example_configs/buttercup-scan/buttercup-compose-nollm.yaml \
    --target-proj-path $OSS_FUZZ/projects/aixcc/c/sanity-mock-c-delta-01 \
    --target-repo-path $PROJECT_CLONE/mock-c \
    --no-checkout

# Run
cd $OSS_CRS && uv run crs-compose run \
    --compose-file ./example_configs/buttercup-scan/buttercup-compose-nollm.yaml \
    --target-proj-path $OSS_FUZZ/projects/aixcc/c/sanity-mock-c-delta-01 \
    --target-repo-path $PROJECT_CLONE/mock-c \
    --no-checkout \
    --target-harness fuzz_process_input_header
```

### No-LLM Configuration

Use `buttercup-compose-nollm.yaml` for fuzzing without LLM seed generation:
- Faster startup (no LiteLLM setup)
- No API keys required
- Useful for testing or when LLM is not needed

## Usage

- `/run-oss-crs` or `/run-oss-crs build run` - Run prepare, build, and run sequentially
- `/run-oss-crs prepare` - Just prepare
- `/run-oss-crs build` - Just build (assumes prepared)
- `/run-oss-crs run` - Just run (assumes already built)

## Environment Variables

LLM API keys can be set as environment variables:
- `OPENAI_API_KEY` - OpenAI API key
- `ANTHROPIC_API_KEY` - Anthropic API key
- `GEMINI_API_KEY` - Gemini API key

Or use `.env` file with `LITELLM_URL` and `LITELLM_KEY` for LiteLLM proxy.

## Parameters

- `--compose-file` - Path to CRS compose YAML file
- `--target-proj-path` - Path to target project (OSS-Fuzz format)
- `--target-repo-path` - Path to source repo (if separate from OSS-Fuzz project)
- `--target-harness` - Harness name to run
- `--no-checkout` - Skip git checkout (use existing repo state)

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
5. To stop the fuzzer, kill the `crs-compose` process (NOT the docker containers directly):
   ```bash
   pkill -f "crs-compose run"
   ```
   This automatically cleans up containers properly.

## Stopping the Fuzzer

**IMPORTANT:** Always stop by killing the `crs-compose` process, not the docker containers:
```bash
pkill -f "crs-compose run"
```

The process handles container cleanup automatically. Do NOT run `docker stop` on crs-run containers directly.

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

---

## Legacy Interface (oss-bugfind-crs)

The old oss-crs (at `~/post/oss-crs`) uses the `oss-bugfind-crs` command.

### Legacy Build Command

```bash
cd $OSS_CRS && uv run oss-bugfind-crs build \
    --project-image-prefix aixcc-afc \
    --oss-fuzz-dir $OSS_FUZZ \
    example_configs/buttercup-scan/ \
    aixcc/c/sanity-mock-c-delta-01 \
    $PROJECT_CLONE/mock-c
```

### Legacy Run Command

```bash
cd $OSS_CRS && source .env && uv run oss-bugfind-crs run \
    --external-litellm \
    example_configs/buttercup-scan/ \
    aixcc/c/sanity-mock-c-delta-01 \
    fuzz_process_input_header
```

### Legacy Run with Diff (Delta Mode)

```bash
cd $OSS_CRS && source .env && uv run oss-bugfind-crs run \
    --external-litellm \
    --diff $OSS_FUZZ/projects/aixcc/c/sanity-mock-c-delta-01/.aixcc/ref.diff \
    example_configs/buttercup-scan/ \
    aixcc/c/sanity-mock-c-delta-01 \
    fuzz_process_input_header
```

### Legacy libxml2

```bash
# Build
cd $OSS_CRS && uv run oss-bugfind-crs build \
    --project-image-prefix aixcc-afc \
    --oss-fuzz-dir $OSS_FUZZ \
    example_configs/buttercup-scan/ \
    aixcc/c/afc-libxml2-delta-01 \
    $PROJECT_CLONE/official-afc-libxml2

# Run
cd $OSS_CRS && source .env && uv run oss-bugfind-crs run \
    --external-litellm \
    example_configs/buttercup-scan/ \
    aixcc/c/afc-libxml2-delta-01 \
    html
```

### Legacy Parameters

- `example_configs/buttercup-scan/` - CRS config for buttercup
- `aixcc/c/sanity-mock-c-delta-01` - Target project config (mock-c)
- `aixcc/c/afc-libxml2-delta-01` - Target project config (libxml2)
- `fuzz_process_input_header` - Harness name for mock-c
- `html` - Harness name for libxml2
- `--external-litellm` - Use external LiteLLM proxy
- `--project-image-prefix aixcc-afc` - Docker image prefix
- `--oss-fuzz-dir` - Path to clean oss-fuzz checkout
- `--diff` - Path to vulnerable diff for delta mode

# Buttercup Bug-Finding CRS Integration

Full-stack Buttercup bug-finding with LLM-powered seed generation.

## Features

- **LLM-powered seed generation** via `seed-gen` component (uses Claude/GPT)
- **Intelligent fuzzing** using ClusterFuzz/libfuzzer
- **Embedded Redis** for component coordination
- **Automatic crash collection** to `/artifacts/povs/`

## Structure

```
oss-crs/
├── builder.Dockerfile    # Inherits from OSS-Fuzz project builder
├── runner.Dockerfile     # Full Buttercup stack (seed-gen, fuzzer, Redis)
├── scripts/
│   ├── entrypoint.sh     # Starts Redis, runs orchestrator
│   └── run_buttercup.py  # Main orchestration logic
└── README.md
```

## Setup

### GHCR token

```
echo $TOKEN | docker login ghcr.io -u hq1995 --password-stdin
```

## Build

```bash
cd /home/hanqing/agents/CRSes/buttercup
docker build -f oss-crs/runner.Dockerfile -t buttercup-bugfind-runner .
```

## Usage

### Basic Fuzzing (without LLM)

For basic fuzzing with libfuzzer (no LLM features):

```bash
docker run --rm \
    -v /path/to/oss-fuzz/build/out/json-c:/out:rw \
    -v /tmp/artifacts:/artifacts \
    -e FUZZ_TIME=300 \
    -e CPUSET_CPUS=0-3 \
    buttercup-bugfind-runner \
    json_array_fuzzer
```

### With LLM Seed Generation (Full Features)

For LLM-powered seed generation, you must mount:
1. **Source code** to `/src/<project_name>` - for CodeQuery analysis
2. **OSS-Fuzz** to `/oss-fuzz` - infrastructure with `infra/helper.py`

```bash
docker run --rm \
    -v /path/to/oss-fuzz/build/out/json-c:/out:rw \
    -v /path/to/json-c-source:/src/json-c:ro \
    -v /path/to/oss-fuzz:/oss-fuzz:ro \
    -v /tmp/artifacts:/artifacts \
    -e FUZZ_TIME=3600 \
    -e CPUSET_CPUS=0-7 \
    -e LITELLM_API_KEY="your-api-key" \
    -e LITELLM_API_BASE="https://your-litellm-proxy" \
    buttercup-bugfind-runner \
    json_array_fuzzer
```

**Prerequisites for LLM seed generation:**
- Source code mounted with actual C/C++/Java files
- OSS-Fuzz clone with `infra/helper.py`
- Valid `LITELLM_API_KEY` and `LITELLM_API_BASE`

If prerequisites aren't met, the runner will gracefully fall back to basic fuzzing.

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `HARNESS_NAME` | Yes* | - | Fuzzing harness name (or positional arg) |
| `FUZZ_TIME` | No | 3600 | Fuzzing timeout in seconds |
| `CPUSET_CPUS` | No | 0 | CPU cores (e.g., "0-7", "0,2,4") |
| `SANITIZER` | No | address | Sanitizer type |
| `LITELLM_API_KEY` | No | - | Enable LLM seed generation |
| `LITELLM_API_BASE` | No | - | LiteLLM proxy URL |
| `OSS_FUZZ_DIR` | No | /oss-fuzz | Alternative OSS-Fuzz location |

## Command Line Options

```bash
buttercup-bugfind-runner <harness_name> [options]

Options:
  --timeout N       Fuzzing timeout in seconds
  --no-seedgen      Skip LLM seed generation
  --project NAME    Project name (auto-detected if not set)
  --list-harnesses  List available harnesses and exit
```

## Output

- **POVs**: `/artifacts/povs/` - Crash inputs with stacktraces
- **Corpus**: `/artifacts/corpus/` - Coverage-increasing inputs

## How LLM Seed Generation Works

When prerequisites are met, Buttercup's seed-gen:
1. Indexes source code using CodeQuery (cscope)
2. Finds harness source file (e.g., `LLVMFuzzerTestOneInput`)
3. Uses LLM to analyze harness and generate Python seed functions
4. Executes seed functions in WASM sandbox to produce test inputs
5. Adds generated seeds to the fuzzing corpus

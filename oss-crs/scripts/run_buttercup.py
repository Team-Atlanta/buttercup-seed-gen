#!/usr/bin/env python3
"""
Buttercup Bug-Finding CRS - Full Stack Orchestrator

This script orchestrates Buttercup's intelligent bug-finding:
1. Sets up ChallengeTask structure from OSS-CRS environment
2. Runs LLM-powered seed generation (seed-init, seed-explore)
3. Executes fuzzing with generated seeds
4. Collects crashes to /artifacts/povs/

For LLM seed generation to work, you must mount:
  -v /path/to/source:/src/<project_name>     # Source code
  -v /path/to/oss-fuzz:/oss-fuzz             # OSS-Fuzz with infra/helper.py

Example:
  docker run --rm \\
    -v /path/to/oss-fuzz/build/out/json-c:/out:rw \\
    -v /path/to/json-c:/src/json-c \\
    -v /path/to/oss-fuzz:/oss-fuzz \\
    -e LITELLM_API_KEY="..." \\
    -e LITELLM_API_BASE="..." \\
    buttercup-bugfind-runner json_fuzzer
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

# OSS-CRS standard directories
OUT_DIR = Path("/out")
WORK_DIR = Path("/work")
ARTIFACTS_DIR = Path("/artifacts")
CORPUS_DIR = ARTIFACTS_DIR / "corpus"
POV_DIR = ARTIFACTS_DIR / "povs"

# Buttercup working directories
TASK_DIR = Path("/tmp/buttercup-task")
SEEDGEN_WDIR = Path("/tmp/seedgen")
SCRATCH_DIR = Path("/tmp/buttercup/scratch")

# Environment
FUZZ_TIME = int(os.environ.get("FUZZ_TIME", "3600"))
CPUSET_CPUS = os.environ.get("CPUSET_CPUS", "0")
LITELLM_API_KEY = os.environ.get("LITELLM_API_KEY", "")
LITELLM_API_BASE = os.environ.get("LITELLM_API_BASE", "")


def log(msg: str, level: str = "INFO"):
    """Print timestamped log message."""
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] [{level}] {msg}", flush=True)


def log_phase(phase: str):
    """Print phase header."""
    print(f"\n{'='*60}", flush=True)
    print(f"  PHASE: {phase}", flush=True)
    print(f"{'='*60}", flush=True)


def log_step(step: str):
    """Print step indicator."""
    print(f"\n>>> {step}", flush=True)


def setup_directories():
    """Create all required directories."""
    log_step("Creating directories")
    for d in [CORPUS_DIR, POV_DIR, TASK_DIR, SEEDGEN_WDIR, SCRATCH_DIR]:
        d.mkdir(parents=True, exist_ok=True)
        log(f"  Created: {d}")


def count_cpus(cpuset: str) -> int:
    """Count CPUs from range string."""
    count = 0
    for part in cpuset.split(","):
        if "-" in part:
            start, end = part.split("-")
            count += int(end) - int(start) + 1
        else:
            count += 1
    return max(1, count)


def find_project_name() -> str:
    """Detect project name from /out directory."""
    log_step("Auto-detecting project name")
    for f in OUT_DIR.iterdir():
        if f.is_file() and f.suffix == "" and f.stat().st_mode & 0o111:
            name = f.name.split("_")[0] if "_" in f.name else "unknown"
            log(f"  Detected: {name} (from {f.name})")
            return name
    log("  Could not detect, using 'unknown'", "WARN")
    return "unknown"


def list_available_harnesses():
    """List available harnesses in /out."""
    log_step("Available harnesses in /out")
    count = 0
    for f in sorted(OUT_DIR.iterdir()):
        if f.is_file() and f.suffix == "" and f.stat().st_mode & 0o111:
            size = f.stat().st_size / 1024 / 1024
            log(f"  - {f.name} ({size:.1f} MB)")
            count += 1
    log(f"  Total: {count} harnesses")


@dataclass
class SeedGenPrerequisites:
    """Check prerequisites for LLM seed generation."""
    source_path: Path | None = None
    oss_fuzz_path: Path | None = None
    has_source: bool = False
    has_oss_fuzz: bool = False
    has_helper: bool = False

    @property
    def can_run_seedgen(self) -> bool:
        return self.has_source and self.has_oss_fuzz and self.has_helper

    def describe_missing(self) -> list[str]:
        missing = []
        if not self.has_source:
            missing.append("Source code not found. Mount with: -v /path/to/source:/src/<project>")
        if not self.has_oss_fuzz:
            missing.append("OSS-Fuzz not found. Mount with: -v /path/to/oss-fuzz:/oss-fuzz")
        elif not self.has_helper:
            missing.append("OSS-Fuzz missing infra/helper.py")
        return missing


def check_seedgen_prerequisites(project_name: str) -> SeedGenPrerequisites:
    """Check if seed-gen prerequisites are met."""
    prereq = SeedGenPrerequisites()

    # Check for source code in common locations
    source_candidates = [
        Path("/src") / project_name,
        Path("/src"),
        WORK_DIR / "src" / project_name,
        WORK_DIR / "src",
    ]
    for candidate in source_candidates:
        if candidate.exists() and candidate.is_dir():
            # Check if it has actual source files
            has_c_files = any(candidate.rglob("*.c")) or any(candidate.rglob("*.cc"))
            has_cpp_files = any(candidate.rglob("*.cpp")) or any(candidate.rglob("*.cxx"))
            has_java_files = any(candidate.rglob("*.java"))
            if has_c_files or has_cpp_files or has_java_files:
                prereq.source_path = candidate
                prereq.has_source = True
                break

    # Check for OSS-Fuzz infrastructure
    oss_fuzz_candidates = [
        Path("/oss-fuzz"),
        WORK_DIR / "oss-fuzz",
        Path(os.environ.get("OSS_FUZZ_DIR", "/oss-fuzz")),
    ]
    for candidate in oss_fuzz_candidates:
        if candidate.exists() and candidate.is_dir():
            prereq.oss_fuzz_path = candidate
            prereq.has_oss_fuzz = True
            # Check for helper.py
            helper_path = candidate / "infra" / "helper.py"
            if helper_path.exists():
                prereq.has_helper = True
            break

    return prereq


def setup_challenge_task(project_name: str, harness_name: str, prereq: SeedGenPrerequisites) -> Path:
    """Create a ChallengeTask-compatible directory structure.

    ChallengeTask requires:
    - task_meta.json with project info
    - src/<focus>/ with source code
    - fuzz-tooling/ with OSS-Fuzz (including infra/helper.py)
    - fuzz-tooling/build/out/<project>/ with built fuzzers
    """
    log_step("Setting up ChallengeTask structure")

    task_dir = TASK_DIR / project_name
    if task_dir.exists():
        shutil.rmtree(task_dir)
    task_dir.mkdir(parents=True, exist_ok=True)
    log(f"  Task dir: {task_dir}")

    # Create task_meta.json
    task_meta = {
        "project_name": project_name,
        "focus": project_name,
        "task_id": f"oss-crs-{project_name}",
        "metadata": {}
    }
    (task_dir / "task_meta.json").write_text(json.dumps(task_meta, indent=2))
    log("  Created task_meta.json")

    # Copy source code (required for seed-gen)
    src_dir = task_dir / "src" / project_name
    if prereq.has_source and prereq.source_path:
        log(f"  Copying source from: {prereq.source_path}")
        shutil.copytree(prereq.source_path, src_dir, symlinks=True)
        file_count = sum(1 for _ in src_dir.rglob("*") if _.is_file())
        log(f"  Copied {file_count} source files")
    else:
        src_dir.mkdir(parents=True, exist_ok=True)
        log("  No source code available", "WARN")

    # Copy OSS-Fuzz infrastructure (required for seed-gen)
    fuzz_tooling = task_dir / "fuzz-tooling"
    if prereq.has_oss_fuzz and prereq.oss_fuzz_path:
        log(f"  Copying OSS-Fuzz from: {prereq.oss_fuzz_path}")
        shutil.copytree(prereq.oss_fuzz_path, fuzz_tooling, symlinks=True)
        log("  OSS-Fuzz infrastructure copied")
    else:
        fuzz_tooling.mkdir(parents=True, exist_ok=True)
        log("  No OSS-Fuzz infrastructure available", "WARN")

    # Link built fuzzers to fuzz-tooling/build/out/<project>
    build_out = fuzz_tooling / "build" / "out" / project_name
    build_out.mkdir(parents=True, exist_ok=True)
    copied = 0
    for f in OUT_DIR.iterdir():
        dst = build_out / f.name
        if not dst.exists():
            if f.is_dir():
                shutil.copytree(f, dst, symlinks=True)
            else:
                shutil.copy2(f, dst)
            copied += 1
    log(f"  Linked {copied} files from /out to fuzz-tooling/build/out/")

    return task_dir


def run_seed_init(task_dir: Path, project_name: str, harness_name: str) -> list[Path]:
    """Run LLM-powered seed initialization."""
    log_step("Running LLM Seed Generation")
    log(f"  Using LiteLLM at: {LITELLM_API_BASE[:50]}...")

    output_dir = SEEDGEN_WDIR / "seed-init-out"
    output_dir.mkdir(parents=True, exist_ok=True)

    cmd = [
        "seed-gen",
        "--wdir", str(SEEDGEN_WDIR),
        "process",
        "--challenge_task_dir", str(task_dir),
        "--package_name", project_name,
        "--harness_name", harness_name,
        "--task_type", "seed-init",
        "--output_dir", str(output_dir),
    ]

    env = {
        **os.environ,
        "BUTTERCUP_SEED_GEN_WDIR": str(SEEDGEN_WDIR),
        "LITELLM_API_KEY": LITELLM_API_KEY,
        "LITELLM_API_BASE": LITELLM_API_BASE,
    }

    log("  Calling seed-gen CLI...")
    start = time.time()
    result = subprocess.run(cmd, env=env, capture_output=True, text=True)
    elapsed = time.time() - start

    if result.returncode != 0:
        log(f"  Seed init failed (exit code {result.returncode})", "ERROR")
        if result.stderr:
            for line in result.stderr.strip().split('\n')[:10]:
                log(f"    {line}", "ERROR")
        return []

    # Collect generated seeds
    seeds = list(output_dir.glob("*"))
    log(f"  Generated {len(seeds)} seeds in {elapsed:.1f}s")
    for seed in seeds[:5]:
        log(f"    - {seed.name} ({seed.stat().st_size} bytes)")
    if len(seeds) > 5:
        log(f"    ... and {len(seeds) - 5} more")

    return seeds


def copy_seeds_to_corpus(seeds: list[Path]):
    """Copy generated seeds to corpus directory."""
    log_step("Adding seeds to corpus")
    added = 0
    for seed in seeds:
        if seed.is_file():
            dst = CORPUS_DIR / seed.name
            shutil.copy2(seed, dst)
            added += 1
    log(f"  Added {added} seeds to corpus")


def seed_from_existing_corpus(harness_name: str) -> int:
    """Copy existing seed corpus if available."""
    log_step("Checking for existing seed corpus")
    seed_corpus = OUT_DIR / f"{harness_name}_seed_corpus"
    if seed_corpus.is_dir():
        count = 0
        for f in seed_corpus.iterdir():
            if f.is_file():
                shutil.copy2(f, CORPUS_DIR / f.name)
                count += 1
        log(f"  Found and copied {count} seeds from {seed_corpus.name}")
        return count
    else:
        log("  No existing seed corpus found")
        return 0


def run_libfuzzer(harness_name: str, timeout: int, fork_jobs: int) -> list[Path]:
    """Run libfuzzer with generated seeds."""
    log_step("Running LibFuzzer")
    log(f"  Harness: {harness_name}")
    log(f"  Timeout: {timeout}s")
    log(f"  Fork jobs: {fork_jobs}")
    log(f"  Corpus: {CORPUS_DIR}")
    log(f"  Artifacts: {POV_DIR}")

    target = OUT_DIR / harness_name
    if not target.exists():
        log(f"  Harness not found at {target}", "ERROR")
        return []

    cmd = [
        str(target),
        str(CORPUS_DIR),
        f"-artifact_prefix={POV_DIR}/",
        f"-max_total_time={timeout}",
        f"-fork={fork_jobs}",
        "-ignore_crashes=1",
        "-ignore_timeouts=1",
        "-ignore_ooms=1",
        "-detect_leaks=0",
        "-close_fd_mask=3",
    ]

    log("  Starting fuzzer...")
    start = time.time()

    try:
        # Run with periodic status updates
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True
        )

        last_update = start
        while process.poll() is None:
            time.sleep(10)
            elapsed = time.time() - start
            if time.time() - last_update >= 30:
                corpus_size = len(list(CORPUS_DIR.iterdir()))
                crash_count = len([f for f in POV_DIR.iterdir() if f.name.startswith(("crash-", "timeout-", "oom-"))])
                log(f"  Progress: {elapsed:.0f}s elapsed, {corpus_size} corpus, {crash_count} crashes")
                last_update = time.time()

            if elapsed > timeout + 30:
                log("  Timeout reached, terminating...", "WARN")
                process.terminate()
                break

        process.wait()

    except subprocess.TimeoutExpired:
        log("  Fuzzer timeout", "WARN")
    except Exception as e:
        log(f"  Fuzzer error: {e}", "ERROR")

    elapsed = time.time() - start

    # Collect crashes
    crashes = [f for f in POV_DIR.iterdir() if f.is_file() and
               f.name.startswith(("crash-", "timeout-", "oom-", "leak-"))]

    log(f"  Completed in {elapsed:.1f}s")
    log(f"  Final corpus: {len(list(CORPUS_DIR.iterdir()))} files")
    log(f"  Crashes found: {len(crashes)}")

    return crashes


def run_fuzzer_with_clusterfuzz(harness_name: str, timeout: int) -> list[Path]:
    """Run fuzzer using buttercup-fuzzer-runner (clusterfuzz wrapper)."""
    log_step("Running Fuzzer via ClusterFuzz")

    target = OUT_DIR / harness_name
    if not target.exists():
        log(f"  Harness not found at {target}", "ERROR")
        return []

    log(f"  Harness: {harness_name}")
    log(f"  Timeout: {timeout}s")
    log(f"  Sanitizer: {os.environ.get('SANITIZER', 'address')}")

    cmd = [
        "buttercup-fuzzer-runner",
        "--timeout", str(timeout),
        "--corpusdir", str(CORPUS_DIR),
        "--engine", "libfuzzer",
        "--sanitizer", os.environ.get("SANITIZER", "address"),
        str(target),
        "fuzz"
    ]

    env = {
        **os.environ,
        "NODE_DATA_DIR": str(SCRATCH_DIR.parent),
        "JOB_NAME": f"libfuzzer_{os.environ.get('SANITIZER', 'address')}",
    }

    log("  Starting ClusterFuzz runner...")
    start = time.time()
    result = subprocess.run(cmd, env=env, capture_output=True, text=True)
    elapsed = time.time() - start

    crashes = []
    try:
        data = json.loads(result.stdout)
        log(f"  Execution time: {data.get('time_executed', 'unknown')}s")
        log(f"  Timed out: {data.get('timed_out', False)}")

        for crash in data.get("crashes", []):
            input_path = crash.get("input_path")
            if input_path and Path(input_path).exists():
                src = Path(input_path)
                dst = POV_DIR / src.name
                shutil.copy2(src, dst)
                crashes.append(dst)
                log(f"  Found crash: {src.name}")

                # Save stacktrace
                stacktrace = crash.get("stacktrace", "")
                if stacktrace:
                    (POV_DIR / f"{src.name}.stacktrace").write_text(stacktrace)

    except json.JSONDecodeError:
        log("  Failed to parse fuzzer JSON output", "WARN")
        if result.stderr:
            for line in result.stderr.strip().split('\n')[:5]:
                log(f"    {line}", "WARN")

    log(f"  Completed in {elapsed:.1f}s, {len(crashes)} crashes")
    return crashes


def print_summary(crashes: list[Path], start_time: float):
    """Print final summary."""
    elapsed = time.time() - start_time

    print(f"\n{'='*60}", flush=True)
    print("  FUZZING COMPLETE", flush=True)
    print(f"{'='*60}", flush=True)
    print(f"  Total time:   {elapsed:.1f}s ({elapsed/60:.1f} min)", flush=True)
    print(f"  Corpus size:  {len(list(CORPUS_DIR.iterdir()))} files", flush=True)
    print(f"  Crashes:      {len(crashes)}", flush=True)
    print(f"  POV dir:      {POV_DIR}", flush=True)
    print(f"  Corpus dir:   {CORPUS_DIR}", flush=True)

    if crashes:
        print(f"\n  Crash files:", flush=True)
        for crash in crashes[:10]:
            size = crash.stat().st_size
            print(f"    - {crash.name} ({size} bytes)", flush=True)
        if len(crashes) > 10:
            print(f"    ... and {len(crashes) - 10} more", flush=True)

    print(f"{'='*60}\n", flush=True)


def main():
    start_time = time.time()

    parser = argparse.ArgumentParser(description="Buttercup Bug-Finding CRS")
    parser.add_argument("harness_name", nargs="?", default=os.environ.get("HARNESS_NAME"),
                        help="Name of the fuzzing harness")
    parser.add_argument("--timeout", type=int, default=FUZZ_TIME,
                        help=f"Fuzzing timeout in seconds (default: {FUZZ_TIME})")
    parser.add_argument("--no-seedgen", action="store_true",
                        help="Skip LLM seed generation")
    parser.add_argument("--project", default=None,
                        help="Project name (auto-detected if not specified)")
    parser.add_argument("--list-harnesses", action="store_true",
                        help="List available harnesses and exit")
    args = parser.parse_args()

    # Header
    print(f"\n{'='*60}", flush=True)
    print("  BUTTERCUP BUG-FINDING CRS", flush=True)
    print(f"  Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}", flush=True)
    print(f"{'='*60}", flush=True)

    # List harnesses if requested
    if args.list_harnesses:
        list_available_harnesses()
        return

    harness_name = args.harness_name
    if not harness_name:
        log("Harness name required (positional arg or HARNESS_NAME env)", "ERROR")
        list_available_harnesses()
        sys.exit(1)

    project_name = args.project or find_project_name()

    # Configuration summary
    log_phase("CONFIGURATION")
    log(f"Project:     {project_name}")
    log(f"Harness:     {harness_name}")
    log(f"Timeout:     {args.timeout}s")
    log(f"CPUs:        {CPUSET_CPUS} ({count_cpus(CPUSET_CPUS)} cores)")
    log(f"LLM:         {'enabled' if LITELLM_API_KEY else 'disabled'}")
    log(f"Seed Gen:    {'disabled' if args.no_seedgen else 'enabled'}")

    # Phase 1: Setup
    log_phase("SETUP")
    setup_directories()
    list_available_harnesses()

    # Phase 2: Seed corpus
    log_phase("SEED CORPUS")
    existing_seeds = seed_from_existing_corpus(harness_name)

    # Phase 3: LLM seed generation
    if not args.no_seedgen and LITELLM_API_KEY:
        log_phase("LLM SEED GENERATION")

        # Check prerequisites
        prereq = check_seedgen_prerequisites(project_name)
        log(f"Prerequisites check:")
        log(f"  Source code:     {'Found at ' + str(prereq.source_path) if prereq.has_source else 'NOT FOUND'}")
        log(f"  OSS-Fuzz:        {'Found at ' + str(prereq.oss_fuzz_path) if prereq.has_oss_fuzz else 'NOT FOUND'}")
        log(f"  infra/helper.py: {'Found' if prereq.has_helper else 'NOT FOUND'}")

        if not prereq.can_run_seedgen:
            log("Cannot run LLM seed generation - missing prerequisites:", "WARN")
            for missing in prereq.describe_missing():
                log(f"  - {missing}", "WARN")
            log("Continuing with basic fuzzing...", "WARN")
        else:
            try:
                task_dir = setup_challenge_task(project_name, harness_name, prereq)
                seeds = run_seed_init(task_dir, project_name, harness_name)
                if seeds:
                    copy_seeds_to_corpus(seeds)
                else:
                    log("No seeds generated, continuing with basic fuzzing", "WARN")
            except Exception as e:
                log(f"Seed generation failed: {e}", "ERROR")
                import traceback
                for line in traceback.format_exc().split('\n')[-5:]:
                    if line.strip():
                        log(f"  {line}", "ERROR")
                log("Continuing with basic fuzzing...", "WARN")
    elif not args.no_seedgen and not LITELLM_API_KEY:
        log_phase("LLM SEED GENERATION")
        log("Skipped: LITELLM_API_KEY not set", "WARN")
        log("Set LITELLM_API_KEY and LITELLM_API_BASE for intelligent seeds")

    # Phase 4: Fuzzing
    log_phase("FUZZING")
    fork_jobs = count_cpus(CPUSET_CPUS)

    log(f"Initial corpus size: {len(list(CORPUS_DIR.iterdir()))} files")

    # Try clusterfuzz runner first, fallback to direct libfuzzer
    crashes = []
    try:
        crashes = run_fuzzer_with_clusterfuzz(harness_name, args.timeout)
    except FileNotFoundError:
        log("ClusterFuzz runner not available, using direct libfuzzer", "WARN")
        crashes = run_libfuzzer(harness_name, args.timeout, fork_jobs)
    except Exception as e:
        log(f"ClusterFuzz failed: {e}, trying direct libfuzzer", "WARN")
        crashes = run_libfuzzer(harness_name, args.timeout, fork_jobs)

    # Fallback if no crashes found
    if not crashes and args.timeout > 60:
        log("No crashes from ClusterFuzz, trying direct libfuzzer...", "INFO")
        crashes = run_libfuzzer(harness_name, min(args.timeout, 300), fork_jobs)

    # Summary
    print_summary(crashes, start_time)


if __name__ == "__main__":
    main()

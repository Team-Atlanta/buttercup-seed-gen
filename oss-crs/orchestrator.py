#!/usr/bin/env python3
"""OSS-CRS Orchestrator - Populates Redis from disk artifacts.

This one-shot script reads the pre-built artifacts from the OSS-CRS builder phase
and registers builds in Redis so that vanilla buttercup services
(fuzzer-bot, coverage-bot, seed-gen) can pick up tasks.

Expected directory structure (created by compile_target):
    /artifacts/task/                   # Task root directory
    /artifacts/task/task_meta.json     # TaskMeta file
    /artifacts/task/src/               # Source code snapshot
    /artifacts/task/fuzz-tooling/      # OSS-Fuzz build structure
    /artifacts/task/fuzz-tooling/build/out/{project}/  # Build outputs

Run Phase Architecture:
    +-------------------+
    |   orchestrator    |  reads /artifacts/task, populates Redis
    +-------------------+
            |
            v
    +-------------------+
    |      Redis        |
    +-------------------+
            ^
            |
    +-------+-------+-------+
    |       |       |       |
 fuzzer  coverage  seed-gen  (vanilla buttercup services)
   bot      bot
"""

import logging
import os
import sys
from pathlib import Path

from redis import Redis

from buttercup.common.clusterfuzz_utils import get_fuzz_targets
from buttercup.common.datastructures.msg_pb2 import BuildOutput, BuildType, WeightedHarness
from buttercup.common.maps import BuildMap, HarnessWeights
from buttercup.common.task_meta import TaskMeta

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("oss-crs-orchestrator")


def find_build_directory(task_dir: Path, project_name: str) -> Path | None:
    """Find the build output directory for fuzz targets.

    Checks multiple locations to handle different directory structures:
    1. task/fuzz-tooling/oss-fuzz/build/out/{project}/  (ChallengeTask compatible)
    2. task/fuzz-tooling/build/out/{project}/  (legacy structure)
    3. task/fuzz-tooling/build/out/  (flat outputs)
    """
    # ChallengeTask compatible structure (oss-fuzz subdirectory)
    build_dir = task_dir / "fuzz-tooling" / "oss-fuzz" / "build" / "out" / project_name
    if build_dir.exists() and build_dir.is_dir():
        logger.info(f"Found build directory at {build_dir}")
        return build_dir

    # Legacy structure without oss-fuzz subdirectory
    build_dir = task_dir / "fuzz-tooling" / "build" / "out" / project_name
    if build_dir.exists() and build_dir.is_dir():
        logger.info(f"Found build directory at {build_dir}")
        return build_dir

    # Check if fuzz targets exist directly in build/out/
    for base in ["fuzz-tooling/oss-fuzz/build/out", "fuzz-tooling/build/out"]:
        build_out = task_dir / base
        if build_out.exists():
            # Look for executable files (fuzz targets) directly
            has_executables = any(
                f.is_file() and os.access(f, os.X_OK) and not f.name.startswith('.')
                for f in build_out.iterdir()
            )
            if has_executables:
                logger.info(f"Found fuzz targets directly in {build_out}")
                return build_out

    return None


def main() -> int:
    redis_url = os.environ.get("REDIS_URL", "redis://localhost:6379")
    task_dir = Path(os.environ.get("TASK_DIR", "/artifacts/task"))
    coverage_dir = Path(os.environ.get("COVERAGE_DIR", "/artifacts/coverage"))
    # Filter to specific harness - check both HARNESS_NAME and OSS_CRS_TARGET_HARNESS
    harness_filter = os.environ.get("HARNESS_NAME") or os.environ.get("OSS_CRS_TARGET_HARNESS", "")

    logger.info(f"Connecting to Redis at {redis_url}")
    redis = Redis.from_url(redis_url)

    # Test Redis connection
    try:
        redis.ping()
        logger.info("Redis connection successful")
    except Exception as e:
        logger.error(f"Failed to connect to Redis: {e}")
        return 1

    # Verify task directory structure
    task_meta_path = task_dir / "task_meta.json"
    if not task_meta_path.exists():
        logger.error(f"task_meta.json not found at {task_meta_path}")
        logger.error("Did you run compile_target first?")
        return 1

    # Load task metadata
    task_meta = TaskMeta.load(task_dir)
    task_id = task_meta.task_id
    package_name = task_meta.project_name

    logger.info(f"Task ID: {task_id}")
    logger.info(f"Package name: {package_name}")

    build_map = BuildMap(redis)
    harness_weights = HarnessWeights(redis)

    registered_targets = 0

    # Find the build directory directly (don't use ChallengeTask)
    build_dir = find_build_directory(task_dir, package_name)
    logger.info(f"Build directory: {build_dir}")

    # Register ASan/Fuzzer build
    if build_dir and build_dir.exists() and any(build_dir.iterdir()):
        logger.info(f"Registering FUZZER build from {task_dir}")
        fuzzer_build = BuildOutput(
            build_type=BuildType.FUZZER,
            task_dir=str(task_dir),  # Task root directory
            task_id=task_id,
            engine="libfuzzer",
            sanitizer="address",
        )
        build_map.add_build(fuzzer_build)
        logger.info("FUZZER build registered")

        # Create WeightedHarness for each fuzz target
        targets = get_fuzz_targets(str(build_dir))

        # Filter to specific harness if HARNESS_NAME is set
        if harness_filter:
            targets = [t for t in targets if os.path.basename(t) == harness_filter]
            if not targets:
                logger.warning(f"Harness filter '{harness_filter}' matched no targets")
            else:
                logger.info(f"Filtering to harness: {harness_filter}")

        for tgt in targets:
            harness_name = os.path.basename(tgt)
            harness = WeightedHarness(
                weight=1.0,
                harness_name=harness_name,
                package_name=package_name,
                task_id=task_id,
            )
            harness_weights.push_harness(harness)
            logger.info(f"Registered harness: {harness_name}")
            registered_targets += 1
    else:
        logger.warning(f"No build artifacts found at {build_dir}")

    # Register coverage build if available
    # Coverage can be in a separate task-coverage directory or flat in /artifacts/coverage
    coverage_task_dir = Path("/artifacts/task-coverage")
    if coverage_task_dir.exists() and (coverage_task_dir / "task_meta.json").exists():
        # Standalone coverage build with full task structure
        logger.info(f"Registering COVERAGE build from {coverage_task_dir}")
        coverage_build = BuildOutput(
            build_type=BuildType.COVERAGE,
            task_dir=str(coverage_task_dir),
            task_id=task_id,
            engine="libfuzzer",
            sanitizer="coverage",
        )
        build_map.add_build(coverage_build)
        logger.info("COVERAGE build registered (standalone task)")
    elif coverage_dir.exists() and any(coverage_dir.iterdir()):
        # Flat coverage directory
        logger.info(f"Coverage artifacts found at {coverage_dir}")
        coverage_build = BuildOutput(
            build_type=BuildType.COVERAGE,
            task_dir=str(coverage_dir),
            task_id=task_id,
            engine="libfuzzer",
            sanitizer="coverage",
        )
        build_map.add_build(coverage_build)
        logger.info("COVERAGE build registered (flat directory)")

    logger.info(f"Orchestrator complete: registered {registered_targets} harnesses in Redis")

    # Stay running to prevent docker-compose --abort-on-container-exit from
    # stopping all services. Wait for SIGTERM/SIGINT to exit gracefully.
    import signal
    import time

    running = True

    def signal_handler(signum, _frame):
        nonlocal running
        logger.info(f"Received signal {signum}, shutting down...")
        running = False

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    logger.info("Orchestrator staying alive (waiting for shutdown signal)...")
    while running:
        time.sleep(1)

    logger.info("Orchestrator exiting")
    return 0


if __name__ == "__main__":
    sys.exit(main())

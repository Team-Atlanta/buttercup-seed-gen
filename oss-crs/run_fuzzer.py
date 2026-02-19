#!/usr/bin/env python3
"""Main entry point for Buttercup OSS-CRS-2 fuzzer.

Thin interface that uses buttercup packages for ClusterFuzz fuzzing.
"""

import logging
import shutil
import sys
import time
from pathlib import Path

# Import from buttercup packages
from buttercup.common.types import FuzzConfiguration
from buttercup.fuzzer_runner.runner import Runner, Conf

# Import local interface modules
from src.config import Config
from src.crash_collector import CrashCollector

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("buttercup")

FUZZ_ITERATION_SECONDS = 60


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: run_fuzzer.py <harness_name>", file=sys.stderr)
        return 1

    harness_name = sys.argv[1]
    config = Config.from_env()

    logger.info(f"Starting Buttercup CRS for harness: {harness_name}")
    logger.info(f"  Fuzz time: {config.fuzz_time}s, Engine: {config.fuzzing_engine}")

    config.corpus_dir.mkdir(parents=True, exist_ok=True)
    config.povs_dir.mkdir(parents=True, exist_ok=True)

    # Find harness binary
    harness_path = config.out_dir / harness_name
    if not harness_path.exists():
        for suffix in ["", "_fuzzer"]:
            candidate = config.out_dir / f"{harness_name}{suffix}"
            if candidate.exists():
                harness_path = candidate
                break

    if not harness_path.exists():
        logger.error(f"Harness not found: {harness_path}")
        return 1

    # Import seeds from shared directory
    seed_share_dir = Path("/seed_share_dir")
    if seed_share_dir.exists():
        for f in seed_share_dir.iterdir():
            if f.is_file():
                shutil.copy2(f, config.corpus_dir / f.name)

    # Initialize
    crash_collector = CrashCollector(config.povs_dir)
    fuzz_config = FuzzConfiguration(
        corpus_dir=str(config.corpus_dir),
        target_path=str(harness_path),
        engine=config.fuzzing_engine,
        sanitizer=config.sanitizer,
    )

    # Continuous fuzzing loop
    start_time = time.time()
    iteration = 0

    while time.time() - start_time < config.fuzz_time:
        iteration += 1
        remaining = config.fuzz_time - (time.time() - start_time)
        iter_time = min(FUZZ_ITERATION_SECONDS, int(remaining) + 1)

        runner = Runner(Conf(timeout=iter_time))
        try:
            result = runner.run_fuzzer(fuzz_config)
            for crash in result.crashes:
                if crash.stacktrace:
                    if crash_collector.add_crash(crash.stacktrace, crash.input_path):
                        logger.info(f"New crash: {crash.input_path}")
                else:
                    crash_collector.save_pov(crash.input_path)
        except Exception as e:
            logger.error(f"Iteration {iteration} failed: {e}")

    logger.info(f"Done. POVs: {crash_collector.pov_count()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

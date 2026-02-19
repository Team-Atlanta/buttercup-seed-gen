#!/usr/bin/env python3
"""POV Submitter for OSS-CRS-2.

Consumes validated crashes from TRACED_VULNERABILITIES queue and saves them
to POVS_DIR for submission via libCRS.
"""

import hashlib
import logging
import os
import shutil
import sys
import time
from pathlib import Path

from redis import Redis

from buttercup.common.datastructures.msg_pb2 import TracedCrash
from buttercup.common.queues import QueueFactory, QueueNames, ReliableQueue
from buttercup.common.stack_parsing import get_crash_token

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("pov-submitter")

# Consumer group name for POV submitter
POV_SUBMITTER_GROUP = "pov_submitter_group"


class POVSubmitter:
    """Consumes validated crashes and saves them as POVs."""

    def __init__(self, redis: Redis, povs_dir: Path, wdir: Path, sleep_seconds: int = 5):
        self.redis = redis
        self.povs_dir = povs_dir
        self.wdir = wdir
        self.sleep_seconds = sleep_seconds
        self.povs_dir.mkdir(parents=True, exist_ok=True)

        # Create queue with custom group (not in QueueFactory defaults)
        self.queue: ReliableQueue[TracedCrash] = ReliableQueue(
            redis=redis,
            queue_name=QueueNames.TRACED_VULNERABILITIES.value,
            msg_builder=TracedCrash,
            group_name=POV_SUBMITTER_GROUP,
            task_timeout_ms=10 * 60 * 1000,  # 10 minutes
        )

        # Track seen crash tokens to avoid duplicates
        self.seen_tokens: set[str] = set()

    def _get_crash_token_hash(self, stacktrace: str) -> str:
        """Get a short hash of the crash token for deduplication."""
        token = get_crash_token(stacktrace)
        return hashlib.sha256(token.encode()).hexdigest()[:16]

    def _save_pov(self, crash_input_path: str, token_hash: str) -> str | None:
        """Save a crash input as a POV file."""
        # The crash_input_path might be a remote path, try to find it locally
        src = Path(crash_input_path)

        # If it's not absolute, try relative to wdir
        if not src.is_absolute():
            src = self.wdir / crash_input_path

        # Try to find the file
        if not src.exists():
            # Try stripping leading / and looking in wdir
            relative_path = crash_input_path.lstrip("/")
            src = self.wdir / relative_path

        if not src.exists():
            logger.warning(f"Crash input not found: {crash_input_path} (tried {src})")
            return None

        # Create POV filename
        dst = self.povs_dir / f"pov_{token_hash}"

        # Don't overwrite existing POVs
        if dst.exists():
            logger.debug(f"POV already exists: {dst}")
            return str(dst)

        try:
            shutil.copy2(src, dst)
            logger.info(f"Saved POV: {src} -> {dst}")
            return str(dst)
        except Exception as e:
            logger.error(f"Failed to save POV: {e}")
            return None

    def serve_item(self) -> bool:
        """Process one item from the queue. Returns True if work was done."""
        item = self.queue.pop()
        if item is None:
            return False

        traced_crash: TracedCrash = item.deserialized
        crash = traced_crash.crash

        logger.info(
            f"Received traced crash for {crash.harness_name} | {crash.target.task_id}"
        )

        # Get crash token for deduplication
        stacktrace = traced_crash.tracer_stacktrace or crash.stacktrace
        token_hash = self._get_crash_token_hash(stacktrace)

        if token_hash in self.seen_tokens:
            logger.info(f"Duplicate crash token {token_hash}, skipping")
            self.queue.ack_item(item.item_id)
            return True

        # Save the POV
        pov_path = self._save_pov(crash.crash_input_path, token_hash)
        if pov_path:
            self.seen_tokens.add(token_hash)
            logger.info(f"POV saved: {pov_path} (token: {token_hash})")
        else:
            logger.warning(f"Failed to save POV for token {token_hash}")

        # Acknowledge the item
        self.queue.ack_item(item.item_id)
        return True

    def run(self) -> None:
        """Main loop."""
        logger.info(f"Starting POV submitter (povs_dir: {self.povs_dir})")
        while True:
            try:
                did_work = self.serve_item()
                if not did_work:
                    time.sleep(self.sleep_seconds)
            except KeyboardInterrupt:
                logger.info("Shutting down...")
                break
            except Exception as e:
                logger.exception(f"Error processing item: {e}")
                time.sleep(self.sleep_seconds)


def main() -> None:
    redis_url = os.environ.get("REDIS_URL", "redis://127.0.0.1:6379")
    povs_dir = Path(os.environ.get("POVS_DIR", "/artifacts/povs"))
    wdir = Path(os.environ.get("WDIR", "/artifacts"))
    sleep_seconds = int(os.environ.get("SLEEP_SECONDS", "5"))

    logger.info(f"Connecting to Redis: {redis_url}")
    redis = Redis.from_url(redis_url)

    # Wait for Redis
    for i in range(60):
        try:
            redis.ping()
            logger.info("Redis is available")
            break
        except Exception:
            if i == 59:
                logger.error("Redis not available after 60 seconds")
                sys.exit(1)
            time.sleep(1)

    submitter = POVSubmitter(redis, povs_dir, wdir, sleep_seconds)
    submitter.run()


if __name__ == "__main__":
    main()

"""Redis connection utilities with startup retry logic."""

from __future__ import annotations

import logging
import time

from redis import ConnectionError as RedisConnectionError
from redis import Redis

logger = logging.getLogger(__name__)

DEFAULT_MAX_RETRIES = 60
DEFAULT_RETRY_INTERVAL = 1.0


def wait_for_redis(
    redis_url: str,
    *,
    max_retries: int = DEFAULT_MAX_RETRIES,
    retry_interval: float = DEFAULT_RETRY_INTERVAL,
) -> Redis:
    """Connect to Redis with retry logic for startup race conditions.

    Retries connection attempts up to ``max_retries`` times, sleeping
    ``retry_interval`` seconds between attempts. This mirrors the shell-level
    wait loop used by the orchestrator entrypoint.
    """
    for attempt in range(1, max_retries + 1):
        try:
            conn = Redis.from_url(redis_url)
            conn.ping()
            logger.info("Connected to Redis at %s", redis_url)
            return conn
        except (RedisConnectionError, OSError) as exc:
            if attempt == max_retries:
                logger.error(
                    "Failed to connect to Redis at %s after %d attempts",
                    redis_url,
                    max_retries,
                )
                raise
            logger.warning(
                "Waiting for Redis at %s (attempt %d/%d): %s",
                redis_url,
                attempt,
                max_retries,
                exc,
            )
            time.sleep(retry_interval)

    # Unreachable, but keeps mypy happy
    raise RuntimeError("Unexpected exit from retry loop")

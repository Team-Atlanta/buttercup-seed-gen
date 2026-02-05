"""Redis-based crash deduplication set.

Separated from stack_parsing.py to avoid importing Redis for pure parsing functions.
"""

from bson.json_util import CANONICAL_JSON_OPTIONS, dumps
from redis import Redis

from buttercup.common.clusterfuzz_parser import CrashInfo
from buttercup.common.sets import RedisSet
from buttercup.common.stack_parsing import (
    get_crash_data_from_crash_info,
    get_inst_key,
    parse_stacktrace,
)


class CrashSet:
    """Redis-backed set for crash deduplication."""

    def __init__(self, redis: Redis):
        self.redis = redis
        self.set_name = "crash_set"
        self.set = RedisSet(redis, self.set_name)

    def _get_final_line_number(self, crash_info: CrashInfo) -> int:
        """Gets the line number of the final stack frame in the stacktrace."""
        if crash_info.frames and crash_info.frames[0] and crash_info.frames[0][0]:
            if crash_info.frames[0][0].fileline:
                return int(crash_info.frames[0][0].fileline)

        return 0

    # Returns True if the crash was already in the set
    def add(self, project: str, harness_name: str, task_id: str, sanitizer: str, stacktrace: str) -> bool:
        crash_info = parse_stacktrace(stacktrace)
        crash_data = get_crash_data_from_crash_info(crash_info)
        inst_key = get_inst_key(stacktrace)
        line_number = self._get_final_line_number(crash_info)

        # NOTE: Storing "exact" crash data and allowing "similar" crashes to migrate to the tracer-bot/orchestrator for
        # deduplication.
        key = dumps(
            [project, harness_name, task_id, sanitizer, crash_data, inst_key, line_number],
            json_options=CANONICAL_JSON_OPTIONS,
        )
        return self.set.add(key)

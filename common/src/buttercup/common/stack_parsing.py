"""Stack parsing utilities for crash deduplication.

Pure functions that don't require Redis or other external services.
"""

import logging
import re

from buttercup.common.clusterfuzz_parser import CrashInfo, StackParser

logger = logging.getLogger(__name__)


def parse_stacktrace(stacktrace: str, symbolized: bool = False) -> CrashInfo:
    """Parse a stacktrace into structured crash info."""
    # Strip ANSI escape codes from stacktrace as parse_stacktrace doesn't like them
    ansi_escape = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
    stacktrace = ansi_escape.sub("", stacktrace)
    parser = StackParser(symbolized=symbolized, detect_ooms_and_hangs=True, detect_v8_runtime_errors=False)
    prs = parser.parse(stacktrace)
    return prs


def get_crash_data_from_crash_info(crash_info: CrashInfo) -> str:
    """Extract crash state string from crash info."""
    return crash_info.crash_state


def get_crash_data(stacktrace: str, symbolized: bool = False) -> str:
    """Extract crash state from stacktrace."""
    prs = parse_stacktrace(stacktrace, symbolized)
    logger.info(f"Crash data: {prs.crash_state}")
    return get_crash_data_from_crash_info(prs)


def get_inst_key(stacktrace: str) -> str:
    """Extract instrumented fragment identifiers from stacktrace."""
    # vendored code from afc-finals/example-crs-architecture
    inst_pattern = re.compile(pattern=r"Instrumented\s(?P<fragment>[A-Za-z0-9\.]*)\s")
    matches = inst_pattern.findall(stacktrace)
    return "\n".join(sorted(matches)) if matches else ""


def get_crash_token(stacktrace: str) -> str:
    """Get a deduplication token for a crash.

    Combines crash state and instrumented fragments.
    """
    return get_crash_data(stacktrace) + get_inst_key(stacktrace)

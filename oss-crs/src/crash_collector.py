"""File-based crash collector for OSS-CRS-2.

Replaces Redis-based CrashSet with a simple JSON file for deduplication.
"""

import hashlib
import json
import logging
import shutil
from pathlib import Path
from typing import Set

from buttercup.common.stack_parsing import get_crash_token

logger = logging.getLogger(__name__)


class CrashCollector:
    """Collects and deduplicates crashes using file-based storage."""

    def __init__(self, povs_dir: Path):
        self.povs_dir = povs_dir
        self.povs_dir.mkdir(parents=True, exist_ok=True)
        self.seen_file = povs_dir / ".seen_crashes.json"
        self.seen_tokens: Set[str] = self._load_seen()

    def _load_seen(self) -> Set[str]:
        """Load previously seen crash tokens."""
        if self.seen_file.exists():
            try:
                with open(self.seen_file) as f:
                    tokens = set(json.load(f))
                    logger.info(f"Loaded {len(tokens)} seen crash tokens")
                    return tokens
            except Exception as e:
                logger.warning(f"Failed to load seen crashes: {e}")
        return set()

    def _save_seen(self) -> None:
        """Save seen crash tokens."""
        try:
            with open(self.seen_file, "w") as f:
                json.dump(list(self.seen_tokens), f)
        except Exception as e:
            logger.warning(f"Failed to save seen crashes: {e}")

    def add_crash(self, stacktrace: str, input_path: str) -> bool:
        """Add a crash if it's new. Returns True if the crash was new."""
        token = get_crash_token(stacktrace)
        token_hash = hashlib.sha256(token.encode()).hexdigest()[:16]

        if token_hash in self.seen_tokens:
            return False

        self.seen_tokens.add(token_hash)
        self._save_seen()

        # Save the POV
        self.save_pov(input_path, token_hash)
        logger.info(f"New crash added: {token_hash}")
        return True

    def save_pov(self, input_path: str, name_hint: str = "") -> str:
        """Save a crash input as a POV."""
        src = Path(input_path)
        if not src.exists():
            logger.warning(f"Crash input not found: {input_path}")
            return ""

        if name_hint:
            dst = self.povs_dir / f"pov_{name_hint}"
        else:
            # Generate name from content hash
            content_hash = hashlib.sha256(src.read_bytes()).hexdigest()[:16]
            dst = self.povs_dir / f"pov_{content_hash}"

        shutil.copy2(src, dst)
        logger.info(f"Saved POV: {input_path} -> {dst}")
        return str(dst)

    def pov_count(self) -> int:
        """Count POV files."""
        return len([f for f in self.povs_dir.iterdir() if f.name.startswith("pov_")])

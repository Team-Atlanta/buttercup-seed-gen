"""Configuration from environment variables for OSS-CRS-2."""

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Config:
    """Runtime configuration from environment variables."""

    fuzz_time: int
    fuzzing_engine: str
    sanitizer: str
    out_dir: Path
    corpus_dir: Path
    povs_dir: Path

    @classmethod
    def from_env(cls) -> "Config":
        artifacts_dir = Path(os.getenv("ARTIFACTS_DIR", "/artifacts"))
        return cls(
            fuzz_time=int(os.getenv("FUZZ_TIME", "3600")),
            fuzzing_engine=os.getenv("FUZZING_ENGINE", "libfuzzer"),
            sanitizer=os.getenv("SANITIZER", "address"),
            out_dir=Path(os.getenv("OUT", "/out")),
            corpus_dir=artifacts_dir / "corpus",
            povs_dir=artifacts_dir / "povs",
        )

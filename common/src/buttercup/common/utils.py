import errno
import logging
import os
import shutil
import stat
import threading
import time
from collections.abc import Callable
from os import PathLike
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

# Global variables for periodic reaper
_reaper_thread = None
_reaper_stop_event = None


def _fix_execute_permissions(src: Path, dst: Path) -> None:
    """Ensure executable files in dst have the same execute permissions as src.

    This is needed because shutil.copytree may not preserve execute bits correctly
    on some filesystems (e.g., tmpfs) or cross-filesystem copies.
    """
    if src.is_file():
        src_mode = src.stat().st_mode
        if src_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH):
            # Source is executable, ensure dst is too
            dst_mode = dst.stat().st_mode
            new_mode = dst_mode | (src_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
            if new_mode != dst_mode:
                os.chmod(dst, new_mode)
    elif src.is_dir():
        for src_child in src.iterdir():
            dst_child = dst / src_child.name
            if dst_child.exists():
                _fix_execute_permissions(src_child, dst_child)


def copyanything(src: PathLike, dst: PathLike, **kwargs: Any) -> None:
    """Copy a file or directory to a destination.
    This function will:
    - Copy directories recursively
    - Copy single files
    - Handle existing destinations
    - Preserve execute permissions (even on cross-filesystem copies)
    """
    src, dst = Path(src), Path(dst)
    try:
        shutil.copytree(src, dst, dirs_exist_ok=True, ignore_dangling_symlinks=True, **kwargs)
        # Fix execute permissions that may be lost in cross-filesystem copies
        _fix_execute_permissions(src, dst)
    except shutil.Error:
        logger.exception(f"Some errors occurred while copying {src} to {dst}, continuing anyway...")
    except OSError as exc:  # python >2.5
        if exc.errno in (errno.ENOTDIR, errno.EINVAL):
            shutil.copy(src, dst)
        else:
            raise


def get_diffs(path: Path | None) -> list[Path]:
    """Get all diff files in the given path."""
    if path is None:
        return []
    logger.info(f"Getting diffs from {path}")
    diff_files = list(path.rglob("*.patch")) + list(path.rglob("*.diff"))
    if not diff_files:
        # If no .patch or .diff files found, try any file
        diff_files = list(path.rglob("*"))

    return sorted(diff_files)


def signal_alive_health_check() -> None:
    """Signal that the process is alive by writing the current time to a temporary file."""
    tmp_file = "/tmp/health_check_alive.tmp"
    with open(tmp_file, "w") as f:
        f.write(str(int(time.time())))
    shutil.move(tmp_file, "/tmp/health_check_alive")


def serve_loop(func: Callable[[], bool], sleep_time: float = 1.0, report_time: float = 60.0) -> None:
    """Serve a function in a loop."""
    if sleep_time < 0:
        raise ValueError("sleep_time must be greater than 0")

    if report_time < 0:
        raise ValueError("report_time must be greater than 0")

    did_work = False
    start_time = time.time()

    while True:
        signal_alive_health_check()
        if time.time() - start_time > report_time:
            logger.info("Sleeping, waiting for inputs")
            start_time = time.time()

        did_work = func()
        if not did_work:
            time.sleep(sleep_time)


def setup_periodic_zombie_reaper(interval_seconds: int = 5) -> None:
    """Set up a background thread that periodically reaps zombie processes."""

    def periodic_reaper() -> None:
        """Background thread function that periodically reaps zombies."""
        logger.info(f"Started periodic zombie reaper (interval: {interval_seconds}s)")

        while True:
            time.sleep(interval_seconds)
            reaped_count = 0
            try:
                # Reap all available zombie processes
                while True:
                    try:
                        pid, status = os.waitpid(-1, os.WNOHANG)
                        if pid == 0:
                            break  # No more zombie processes
                        reaped_count += 1
                        logger.debug(f"Periodic reaper: reaped zombie PID {pid}")
                    except OSError:
                        # No more child processes to reap
                        break

                if reaped_count > 0:
                    logger.info(f"Periodic reaper: cleaned up {reaped_count} zombie processes")

            except Exception as e:
                logger.error(f"Error in periodic zombie reaper: {e}")

    # Start the daemon thread and forget about it
    thread = threading.Thread(target=periodic_reaper, daemon=True, name="ZombieReaper")
    thread.start()
    logger.info("Periodic zombie reaper started")

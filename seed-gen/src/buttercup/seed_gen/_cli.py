"""The `seed-gen` entrypoint."""

import logging
import os
import shutil
import tempfile
from pathlib import Path

from buttercup.common.challenge_task import ChallengeTask
from buttercup.common.logger import setup_package_logger
from buttercup.common.project_yaml import ProjectYaml
from buttercup.common.telemetry import init_telemetry
from buttercup.program_model.codequery import CodeQueryPersistent
from pydantic_settings import get_subcommand
from redis import Redis

import buttercup.seed_gen.cli_load_dotenv  # noqa: F401
from buttercup.seed_gen.config import ProcessCommand, Settings
from buttercup.seed_gen.seed_explore import SeedExploreTask
from buttercup.seed_gen.seed_gen_bot import SeedGenBot
from buttercup.seed_gen.seed_init import SeedInitTask
from buttercup.seed_gen.task import TaskName

logger = logging.getLogger(__name__)


def command_server(settings: Settings) -> None:
    """Seed-gen worker server"""
    if settings.server is None:
        raise ValueError("Server command not provided")

    os.makedirs(settings.wdir, exist_ok=True)
    if settings.server.corpus_root:
        os.makedirs(settings.server.corpus_root, exist_ok=True)
    init_telemetry("seed-gen")
    redis = Redis.from_url(settings.server.redis_url)
    seed_gen_bot = SeedGenBot(
        redis,
        settings.server.sleep_time,
        settings.wdir,
        max_corpus_seed_size=settings.server.max_corpus_seed_size,
        corpus_root=str(settings.server.corpus_root) if settings.server.corpus_root else None,
    )
    seed_gen_bot.run()


def command_process(settings: Settings) -> None:
    """Process a single seed generation task"""
    command = get_subcommand(settings)
    if not isinstance(command, ProcessCommand):
        return

    command_outdir = command.output_dir

    init_telemetry("seed-gen")
    ro_challenge_task = ChallengeTask(read_only_task_dir=command.challenge_task_dir)
    with (
        tempfile.TemporaryDirectory(dir=settings.wdir, prefix="seedgen-") as temp_dir_str,
        ro_challenge_task.get_rw_copy(work_dir=Path(temp_dir_str)) as challenge_task,
    ):
        temp_dir = Path(temp_dir_str)
        out_dir = temp_dir / "out"
        out_dir.mkdir()
        current_dir = temp_dir / "seedgen-current"
        current_dir.mkdir()
        codequery = CodeQueryPersistent(challenge_task, work_dir=Path(settings.wdir))
        project_yaml = ProjectYaml(challenge_task, command.package_name)

        if command.task_type == TaskName.SEED_INIT.value:
            task = SeedInitTask(
                command.package_name,
                command.harness_name,
                challenge_task,
                codequery,
                project_yaml,
                None,
            )
            task.do_task(out_dir)
        elif command.task_type == TaskName.SEED_EXPLORE.value:
            if not command.target_function or not command.target_function_paths:
                raise ValueError(
                    "target_function and target_function_paths required for seed-explore",
                )
            task = SeedExploreTask(
                command.package_name,
                command.harness_name,
                challenge_task,
                codequery,
                project_yaml,
                None,
            )
            task.do_task(command.target_function, command.target_function_paths, out_dir)
        else:
            raise ValueError(f"Unknown task type: {command.task_type}")

        shutil.copytree(out_dir, command_outdir)


def main() -> None:
    settings = Settings()  # type: ignore[call-arg]
    setup_package_logger(
        "seed-gen",
        __name__,
        settings.log_level.upper(),
        settings.log_max_line_length,
    )
    command = get_subcommand(settings)
    if isinstance(command, ProcessCommand):
        command_process(settings)
    else:
        command_server(settings)

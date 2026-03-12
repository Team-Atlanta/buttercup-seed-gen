import logging
import os
import random
import subprocess
import tempfile
from pathlib import Path

from buttercup.common.challenge_task import ChallengeTask
from buttercup.common.corpus import Corpus
from buttercup.common.datastructures.msg_pb2 import BuildOutput, BuildType, WeightedHarness
from buttercup.common.default_task_loop import TaskLoop
from buttercup.common.project_yaml import ProjectYaml
from buttercup.program_model.codequery import CodeQueryPersistent
from redis import Redis

from buttercup.seed_gen.function_selector import FunctionSelector
from buttercup.seed_gen.seed_explore import SeedExploreTask
from buttercup.seed_gen.seed_init import SeedInitTask
from buttercup.seed_gen.task import TaskName
from buttercup.seed_gen.task_counter import TaskCounter

logger = logging.getLogger(__name__)


class SeedGenBot(TaskLoop):
    TASK_SEED_INIT_PROB_FULL = 0.05
    TASK_SEED_EXPLORE_PROB_FULL = 0.95

    TASK_SEED_INIT_PROB_DELTA = 0.05
    TASK_SEED_EXPLORE_PROB_DELTA = 0.95

    MIN_SEED_INIT_RUNS = 3

    def __init__(
        self,
        redis: Redis,
        timer_seconds: int,
        wdir: Path,
        max_corpus_seed_size: int,
        corpus_root: str | None = None,
    ):
        self.wdir = wdir
        self.corpus_root = corpus_root
        self.redis = redis
        self.task_counter = TaskCounter(redis)
        self.max_corpus_seed_size = max_corpus_seed_size
        super().__init__(redis, timer_seconds)

    def required_builds(self) -> list[BuildType]:
        return [BuildType.FUZZER]

    def sample_task(self, task: WeightedHarness, is_delta: bool) -> str:
        """Sample a task to run

        Prioritizes seed-init if it hasn't been run enough times.

        Args:
            task: The WeightedHarness task to sample for
            is_delta: Whether the challenge is in delta mode

        Returns:
            The selected task name

        """
        # Check if seed-init has been run enough times
        seed_init_count = self.task_counter.get_count(
            task.harness_name,
            task.package_name,
            task.task_id,
            TaskName.SEED_INIT.value,
        )

        if seed_init_count < self.MIN_SEED_INIT_RUNS:
            logger.info(f"seed-init has only been run {seed_init_count} times, forcing task")
            return TaskName.SEED_INIT.value

        # Use probability distribution for task selection
        if is_delta:
            task_distribution = [
                (TaskName.SEED_INIT.value, self.TASK_SEED_INIT_PROB_DELTA),
                (TaskName.SEED_EXPLORE.value, self.TASK_SEED_EXPLORE_PROB_DELTA),
            ]
        else:
            task_distribution = [
                (TaskName.SEED_INIT.value, self.TASK_SEED_INIT_PROB_FULL),
                (TaskName.SEED_EXPLORE.value, self.TASK_SEED_EXPLORE_PROB_FULL),
            ]

        tasks, weights = zip(*task_distribution, strict=False)
        result = random.choices(tasks, weights=weights, k=1)
        return str(result[0]) if result else ""

    def run_task(
        self,
        task: WeightedHarness,
        builds: dict[BuildType, list[BuildOutput]],
    ) -> None:
        build_dir = Path(builds[BuildType.FUZZER][0].task_dir)
        ro_challenge_task = ChallengeTask(read_only_task_dir=build_dir)
        project_yaml = ProjectYaml(ro_challenge_task, task.package_name)
        task_id = ro_challenge_task.task_meta.task_id

        # Ensure the task-specific work directory exists
        (self.wdir / task_id).mkdir(parents=True, exist_ok=True)

        with (
            tempfile.TemporaryDirectory(dir=self.wdir / task_id, prefix="seedgen-") as temp_dir_str,
            ro_challenge_task.get_rw_copy(work_dir=Path(temp_dir_str)) as challenge_task,
        ):
            logger.info(
                f"Running seed-gen for {task.harness_name} | {task.package_name} | {task.task_id}",
            )
            temp_dir = Path(temp_dir_str)
            logger.debug(f"Temp dir: {temp_dir}")
            out_dir = temp_dir / "seedgen-out"
            out_dir.mkdir()
            current_dir = temp_dir / "seedgen-current"
            current_dir.mkdir()

            logger.info("Initializing codequery")
            try:
                codequery = CodeQueryPersistent(challenge_task, work_dir=self.wdir)
            except Exception as e:
                logger.exception(f"Failed to initialize codequery: {e}.")
                return

            # Use corpus_root if provided, otherwise fall back to wdir
            # When corpus_root is set, use OSS-CRS directory structure for libCRS compatibility
            corpus_base = self.corpus_root if self.corpus_root else self.wdir.as_posix()
            oss_crs_mode = self.corpus_root is not None
            corp = Corpus(
                corpus_base,
                task.task_id,
                task.harness_name,
                copy_corpus_max_size=self.max_corpus_seed_size,
                oss_crs_mode=oss_crs_mode,
            )
            override_task = os.getenv("BUTTERCUP_SEED_GEN_TEST_TASK")
            if override_task:
                logger.info("Only testing task: %s", override_task)
            is_delta = challenge_task.is_delta_mode()
            task_choice = override_task if override_task else self.sample_task(task, is_delta)

            logger.info(f"Running seed-gen task: {task_choice}")

            # Increment the counter for this task run
            self.task_counter.increment(
                task.harness_name,
                task.package_name,
                task.task_id,
                task_choice,
            )

            if task_choice == TaskName.SEED_INIT.value:
                seed_init = SeedInitTask(
                    task.package_name,
                    task.harness_name,
                    challenge_task,
                    codequery,
                    project_yaml,
                    self.redis,
                )
                seed_init.do_task(out_dir)
            elif task_choice == TaskName.SEED_EXPLORE.value:
                seed_explore = SeedExploreTask(
                    task.package_name,
                    task.harness_name,
                    challenge_task,
                    codequery,
                    project_yaml,
                    self.redis,
                )

                function_selector = FunctionSelector(self.redis)
                selected_function = function_selector.sample_function(task)

                if selected_function is None:
                    logger.error("No function selected from coverage data, canceling seed-explore")
                    return

                function_name = selected_function.function_name
                function_paths = [Path(path_str) for path_str in selected_function.function_paths]

                seed_explore.do_task(function_name, function_paths, out_dir)
            else:
                raise ValueError(f"Unexpected task: {task_choice}")

            copied_files = corp.copy_corpus(str(out_dir))
            logger.info("Copied %d files to corpus %s", len(copied_files), corp.corpus_dir)

            # In OSS-CRS mode, submit files via libCRS
            if oss_crs_mode and copied_files:
                for seed_file in copied_files:
                    try:
                        result = subprocess.run(
                            ["libCRS", "submit", "seed", seed_file],
                            capture_output=True,
                            text=True,
                            timeout=30,
                        )
                        if result.returncode != 0:
                            logger.warning("libCRS submit failed for %s: %s", seed_file, result.stderr)
                    except FileNotFoundError:
                        logger.debug("libCRS not available, skipping submit")
                        break
                    except subprocess.TimeoutExpired:
                        logger.warning("libCRS submit timed out for %s", seed_file)
                logger.info("Submitted %d seeds via libCRS", len(copied_files))

            logger.info(
                f"Seed-gen finished for {task.harness_name} | {task.package_name} | {task.task_id}",
            )

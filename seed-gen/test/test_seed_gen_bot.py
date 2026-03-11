"""Tests for seed_gen_bot task sampling"""

import pytest
from buttercup.common.datastructures.msg_pb2 import WeightedHarness
from buttercup.seed_gen.seed_gen_bot import SeedGenBot
from buttercup.seed_gen.task import TaskName
from unittest.mock import MagicMock, Mock


@pytest.fixture
def redis_mock():
    """Mock Redis instance"""
    return MagicMock()


@pytest.fixture
def seed_gen_bot(redis_mock, tmp_path):
    """Create SeedGenBot instance"""
    return SeedGenBot(
        redis=redis_mock,
        timer_seconds=60,
        wdir=tmp_path,
        max_corpus_seed_size=1024,
    )


@pytest.fixture
def weighted_harness():
    """Create test WeightedHarness"""
    harness = WeightedHarness()
    harness.harness_name = "test_harness"
    harness.package_name = "test_package"
    harness.task_id = "test_task_id"
    return harness


class TestSampleTask:
    """Test task sampling returns only seed-init or seed-explore"""

    def test_sample_task_never_returns_vuln_discovery(self, seed_gen_bot, weighted_harness):
        """sample_task() should never return vuln-discovery"""
        # Mock task counter to return high counts (past minimum requirements)
        seed_gen_bot.task_counter.get_count = Mock(return_value=10)

        # Sample many times to test probability distribution
        results = []
        for _ in range(100):
            result = seed_gen_bot.sample_task(weighted_harness, is_delta=True)
            results.append(result)

        # Assert vuln-discovery is never returned
        assert "vuln-discovery" not in results

        # Assert only valid task types are returned
        for result in results:
            assert result in [TaskName.SEED_INIT.value, TaskName.SEED_EXPLORE.value]

    def test_probability_constants_sum_to_one_delta(self, seed_gen_bot):
        """Delta mode probability constants should sum to 1.0"""
        prob_sum = (
            seed_gen_bot.TASK_SEED_INIT_PROB_DELTA
            + seed_gen_bot.TASK_SEED_EXPLORE_PROB_DELTA
        )
        assert prob_sum == 1.0, f"Delta probabilities sum to {prob_sum}, expected 1.0"

    def test_probability_constants_sum_to_one_full(self, seed_gen_bot):
        """Full mode probability constants should sum to 1.0"""
        prob_sum = (
            seed_gen_bot.TASK_SEED_INIT_PROB_FULL
            + seed_gen_bot.TASK_SEED_EXPLORE_PROB_FULL
        )
        assert prob_sum == 1.0, f"Full probabilities sum to {prob_sum}, expected 1.0"

    def test_no_min_vuln_discovery_constant(self, seed_gen_bot):
        """MIN_VULN_DISCOVERY_RUNS constant should not exist"""
        assert not hasattr(seed_gen_bot, 'MIN_VULN_DISCOVERY_RUNS')

    def test_forced_seed_init_still_works(self, seed_gen_bot, weighted_harness):
        """Forced seed-init logic should still work"""
        # Mock task counter to return 0 for seed-init
        seed_gen_bot.task_counter.get_count = Mock(return_value=0)

        result = seed_gen_bot.sample_task(weighted_harness, is_delta=True)

        # Should force seed-init when count is below minimum
        assert result == TaskName.SEED_INIT.value

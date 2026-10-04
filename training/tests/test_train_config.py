"""The phase config that train.py writes into BVS_TRAIN_CONFIG, and the handshake config."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from bvs_training import handshake, train


def phase(**over) -> dict:
    base = {"name": "PX", "steps": 1, "mix": {"cpu_easy": 0.5, "cpu_normal": 0.5}}
    base.update(over)
    return base


def test_sd_start_indices_spread_over_the_rows() -> None:
    assert train.sd_start_indices(0, 8) == []
    assert train.sd_start_indices(1, 8) == [4]
    assert train.sd_start_indices(2, 8) == [2, 6]
    assert train.sd_start_indices(8, 8) == list(range(8))
    assert train.sd_start_indices(20, 8) == list(range(8))


def test_no_sd_start_share_means_regulation_rows_only() -> None:
    rows = train.build_rows(phase(), {"rows": 8}, 1, [])
    assert len(rows) == 8
    assert all("start" not in row for row in rows)


def test_sd_start_share_marks_that_many_rows() -> None:
    rows = train.build_rows(phase(sd_start=0.25), {"rows": 8}, 1, [])
    starts = [index for index, row in enumerate(rows) if row.get("start") == "sudden_death"]
    assert len(starts) == 2
    assert starts == train.sd_start_indices(2, 8)


def test_the_match_block_has_defaults_and_overrides() -> None:
    assert train.match_block({}) == {"sudden_death": True, "sd_safety_cap": 60.0}
    assert train.match_block({"sudden_death": False, "sd_safety_cap": 30}) == {"sudden_death": False, "sd_safety_cap": 30.0}


def test_the_phase_config_targets_schema_4_and_carries_the_match_and_kits_blocks(tmp_path: Path) -> None:
    path = train.write_phase_config(
        tmp_path, phase(sd_start=0.125), {"rows": 8}, {"pickup": 0.07}, 5, [], {"sd_safety_cap": 45.0}, {"mode": "random", "seed": 9}
    )
    config = json.loads(path.read_text())
    assert config["schema_version"] == 4
    assert config["kits"] == {"mode": "random", "seed": 9}
    assert config["match"] == {"sudden_death": True, "sd_safety_cap": 45.0}
    assert config["reward"] == {"pickup": 0.07}
    assert config["episode_log"] is True
    assert sum(1 for row in config["rows"] if row.get("start") == "sudden_death") == 1
    assert {row["opponent"] for row in config["rows"]} == {"cpu_easy", "cpu_normal"}


def test_the_kits_block_defaults_to_random_with_the_run_seed() -> None:
    assert train.kits_block({}, 5) == {"mode": "random", "seed": 5}
    assert train.kits_block({"mode": "character"}, 5) == {"mode": "character", "seed": 5}
    assert train.kits_block({"seed": 2}, 5) == {"mode": "random", "seed": 2}


def test_an_unknown_kits_mode_is_refused() -> None:
    with pytest.raises(SystemExit, match="chaos"):
        train.kits_block({"mode": "chaos"}, 1)


def test_the_default_config_phases_and_match_block() -> None:
    config = train.load_config(train.DEFAULT_CONFIG)
    assert config["match"] == {"sudden_death": True, "sd_safety_cap": 60.0}
    shares = {p["name"]: p.get("sd_start", 0.0) for p in config["phase"]}
    assert shares == {"P1": 0.0, "P2": 0.125, "P3": 0.25}
    reward = config["reward"]
    assert reward["pickup"] == 0.05 and reward["food_hit"] == 0.15
    assert reward["shield_break_dealt"] == 0.4 and reward["shield_break_taken"] == -0.4
    assert reward["shield_hold"] == -0.003 and reward["shield_hold_threshold"] == 1.5 and reward["pickup_cap"] == 20
    assert reward["combo_hit"] == 0.02 and reward["combo_hit_cap"] == 4 and reward["combo_episode_cap"] == 1.0
    assert reward["shield_raise"] == -0.002
    assert config["kits"] == {"mode": "random"}


def test_the_handshake_config_asks_for_schema_4_random_kits_and_a_sudden_death_row() -> None:
    config = handshake.handshake_config()
    assert config["schema_version"] == 4
    assert config["kits"]["mode"] == "random"
    assert any(row.get("start") == "sudden_death" for row in config["rows"])
    assert config["match"]["sd_safety_cap"] > 0


def test_the_handshake_can_target_older_schemas() -> None:
    assert handshake.handshake_config(3)["schema_version"] == 3
    assert handshake.handshake_config(2)["schema_version"] == 2


def test_the_handshake_help_exits_zero() -> None:
    with pytest.raises(SystemExit) as raised:
        handshake.main(["--help"])
    assert raised.value.code == 0

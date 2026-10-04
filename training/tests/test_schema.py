"""The Python mirror of the bvs-schema constants and the committed schema fixtures."""

from __future__ import annotations

import json

import pytest

from bvs_training import golden, schema


def test_three_schemas_are_registered_and_training_targets_v4() -> None:
    assert sorted(schema.SCHEMAS) == [2, 3, 4]
    assert schema.TRAIN_VERSION == 4
    assert schema.SCHEMA_VERSION == 4
    assert schema.OBS_DIM == 149
    assert schema.SCHEMAS[3].obs_dim == 136
    assert schema.SCHEMAS[2].obs_dim == 102


def test_schema_tags_and_fixture_paths() -> None:
    assert schema.SCHEMAS[4].tag == "bvs-schema-4"
    assert schema.SCHEMAS[3].tag == "bvs-schema-3"
    assert schema.SCHEMAS[2].tag == "bvs-schema-2"
    assert schema.SCHEMA_TAG == "bvs-schema-4"
    assert schema.SCHEMAS[4].layout_fixture.name == "v4_layout.json"
    assert schema.SCHEMAS[4].obs_fixture.name == "v4_obs_golden.json"
    assert schema.SCHEMAS[3].layout_fixture.name == "v3_layout.json"
    assert schema.SCHEMAS[3].obs_fixture.name == "v3_obs_golden.json"
    assert schema.LAYOUT_FIXTURE == schema.SCHEMAS[4].layout_fixture


def test_action_layout_is_shared_by_every_schema() -> None:
    assert schema.ACTION_NVEC == [3, 3, 2, 5, 2, 2, 2, 2]
    assert schema.LOGITS == 21
    assert schema.ACTION_REPEAT == 4
    assert [branch["name"] for branch in schema.sidecar_branches()][:2] == ["a0_move", "a1_vertical"]


@pytest.mark.parametrize("version", [2, 3, 4])
def test_layout_fixture_matches_obs_dim(version: int) -> None:
    names = schema.layout_names(version)
    assert len(names) == schema.SCHEMAS[version].obs_dim
    assert len(set(names)) == len(names)
    schema.check_layout_fixture(version)


def test_v3_layout_has_the_combat_depth_fields_in_order() -> None:
    names = schema.layout_names(3)
    assert names[23] == "self_shield"
    assert names[43 + 23] == "opp_shield"
    assert names[120] == "bomb0_present"
    assert names[-4:] == ["timer_left", "sudden_death", "sudden_death_phase", "sudden_death_elapsed"]


def test_v3_obs_fixture_matches_obs_dim() -> None:
    schema.check_obs_fixture(3)
    golden_file = json.loads(schema.SCHEMAS[3].obs_fixture.read_text())
    assert len(golden_file["cases"]) >= 8
    assert {case["my_index"] for case in golden_file["cases"]} == {0, 1}


def test_v4_layout_appends_the_kit_chain_hitstun_and_combo_fields() -> None:
    names = schema.layout_names(4)
    assert names[:136] == schema.layout_names(3)
    assert names[136:140] == ["self_kit_0", "self_kit_1", "self_kit_2", "self_kit_3"]
    assert names[140:144] == ["opp_kit_0", "opp_kit_1", "opp_kit_2", "opp_kit_3"]
    assert names[144:] == ["self_chain_step", "self_link_open", "opp_hitstun_left", "self_combo_dealt", "self_combo_taken"]


def test_v4_obs_fixture_matches_obs_dim_and_covers_both_views() -> None:
    schema.check_obs_fixture(4)
    golden_file = json.loads(schema.SCHEMAS[4].obs_fixture.read_text())
    assert len(golden_file["cases"]) >= 12
    assert {case["my_index"] for case in golden_file["cases"]} == {0, 1}


def test_check_env_accepts_the_v4_shapes_and_rejects_older_shapes() -> None:
    schema.check_env((149,), schema.ACTION_NVEC)
    with pytest.raises(AssertionError, match="obs shape"):
        schema.check_env((136,), schema.ACTION_NVEC)
    with pytest.raises(AssertionError, match="nvec"):
        schema.check_env((149,), [3, 3, 2, 5, 2, 2, 2, 3])


def test_check_env_can_target_schema_3() -> None:
    schema.check_env((136,), schema.ACTION_NVEC, version=3)
    with pytest.raises(AssertionError):
        schema.check_env((149,), schema.ACTION_NVEC, version=3)


def test_check_env_can_target_schema_2() -> None:
    schema.check_env((102,), schema.ACTION_NVEC, version=2)
    with pytest.raises(AssertionError):
        schema.check_env((136,), schema.ACTION_NVEC, version=2)


@pytest.mark.parametrize("version", [3, 4])
def test_the_committed_fixtures_agree_with_the_mirror(version: int) -> None:
    assert golden.check_schema_fixtures(version) == []


def test_a_changed_appended_v4_name_is_reported(monkeypatch: pytest.MonkeyPatch) -> None:
    original = schema.layout_names
    names = list(original(4))
    names[146], names[147] = names[147], names[146]
    monkeypatch.setattr(schema, "layout_names", lambda version: names if version == 4 else original(version))
    assert any("appended schema 4 names" in problem for problem in golden.check_schema_fixtures(4))


def test_a_short_layout_is_reported(monkeypatch: pytest.MonkeyPatch) -> None:
    names = schema.layout_names(3)
    monkeypatch.setattr(schema, "layout_names", lambda version: names[:-1])
    assert any("135 names" in problem for problem in golden.check_schema_fixtures(3))


def test_a_misordered_fighter_block_is_reported(monkeypatch: pytest.MonkeyPatch) -> None:
    names = list(schema.layout_names(3))
    names[43 + 5], names[43 + 6] = names[43 + 6], names[43 + 5]
    monkeypatch.setattr(schema, "layout_names", lambda version: names)
    assert any("fighter blocks differ" in problem for problem in golden.check_schema_fixtures(3))


def test_a_moved_shared_block_is_reported(monkeypatch: pytest.MonkeyPatch) -> None:
    names = list(schema.layout_names(3))
    names[120], names[126] = names[126], names[120]
    monkeypatch.setattr(schema, "layout_names", lambda version: names)
    problems = golden.check_schema_fixtures(3)
    assert any("layout[120]" in problem for problem in problems)

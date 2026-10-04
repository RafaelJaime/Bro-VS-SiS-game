"""The sidecar writer and the ONNX export for the training schema (4)."""

from __future__ import annotations

import json
from pathlib import Path

import onnx

from bvs_training import export, golden, schema, sidecar


def test_build_sidecar_declares_schema_4() -> None:
    side = sidecar.build_sidecar("test", commit="abc")
    assert side["schema_version"] == 4
    assert side["obs_dim"] == 149
    assert side["action_repeat"] == 4
    assert side["format"] == "bvs-model/1"
    assert [branch["size"] for branch in side["action_branches"]] == schema.ACTION_NVEC
    assert sidecar.validate(side) == ""


def test_an_older_sidecar_is_not_valid_for_schema_4() -> None:
    side = sidecar.build_sidecar("test", commit="abc")
    side["schema_version"] = 3
    side["obs_dim"] = 136
    assert "schema_version 3 != 4" in sidecar.validate(side)
    assert sidecar.validate(side, version=3) == ""
    side["schema_version"] = 2
    side["obs_dim"] = 102
    assert "schema_version 2 != 4" in sidecar.validate(side)
    assert sidecar.validate(side, version=2) == ""


def test_a_wrong_obs_dim_is_named() -> None:
    side = sidecar.build_sidecar("test", commit="abc")
    side["obs_dim"] = 102
    assert sidecar.validate(side) == "obs_dim 102 != 149"


def test_a_missing_key_is_named() -> None:
    side = sidecar.build_sidecar("test", commit="abc")
    del side["trained_on_commit"]
    assert "trained_on_commit" in sidecar.validate(side)


def test_the_committed_v3_fixture_sidecar_validates() -> None:
    path = schema.REPO_ROOT / "tests" / "fixtures" / "onnx" / "random_policy_v3.bvs.json"
    assert sidecar.validate(json.loads(path.read_text()), version=3) == ""


def test_random_policy_exports_149_inputs_and_21_logits(tmp_path: Path) -> None:
    out = export.export_policy(export.build_policy(0), tmp_path / "model.onnx", label="pytest")
    model = onnx.load(str(out))
    assert [d.dim_value for d in model.graph.input[0].type.tensor_type.shape.dim] == [1, 149]
    assert [d.dim_value for d in model.graph.output[0].type.tensor_type.shape.dim][-1] == 21
    written = json.loads((tmp_path / "bvs.json").read_text())
    assert written["schema_version"] == 4
    assert written["obs_dim"] == 149
    assert sidecar.validate(written) == ""


def test_golden_vectors_are_built_for_the_149_wide_model(tmp_path: Path) -> None:
    out = export.export_policy(export.build_policy(0), tmp_path / "model.onnx", label="pytest")
    built = golden.build_golden(out, None, "model.onnx")
    assert built["obs_dim"] == 149
    assert built["branches"] == schema.ACTION_NVEC
    assert len(built["cases"]) == golden.RANDOM_CASES
    assert all(len(case["input"]) == 149 and len(case["expected"]) == 21 for case in built["cases"])


def test_recorded_observations_of_the_old_width_are_refused(tmp_path: Path) -> None:
    dump = tmp_path / "obs.json"
    dump.write_text(json.dumps({"observations": [[0.0] * 136]}))
    try:
        golden.load_recorded(dump)
    except AssertionError as err:
        assert "shape" in str(err)
    else:
        raise AssertionError("a 136-wide observation must be refused")

"""The upload preparation stages files and prints commands; it never uploads."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from bvs_training import prepare_upload, sidecar


def _source(tmp_path: Path, replay: bool) -> Path:
    source = tmp_path / "src"
    source.mkdir()
    (source / "model.onnx").write_bytes(b"onnx-bytes")
    (source / "bvs.json").write_text(json.dumps(sidecar.build_sidecar("test", commit="abc")))
    if replay:
        (source / "replay.mp4").write_bytes(b"mp4-bytes")
    return source


def test_tags_name_schema_4() -> None:
    assert prepare_upload.TAGS == ("BVS", "bvs-schema-4", "reinforcement-learning")


def test_model_card_front_matter_names_schema_4() -> None:
    card = prepare_upload.render_card("owner/name", "mit", {"label": "x", "trained_on_commit": "abc"})
    assert "  - bvs-schema-4" in card
    assert "bvs-schema-3" not in card.replace("`bvs-schema-3` vector", "")
    assert "[1, 149]" in card


@pytest.mark.parametrize("replay", [True, False])
def test_stage_includes_replay_only_when_present(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, replay: bool) -> None:
    monkeypatch.setattr(prepare_upload, "STAGE_ROOT", tmp_path / "stage")
    target = prepare_upload.stage("owner/name", "mit", _source(tmp_path, replay), allow_unbundled=True)
    assert (target / "replay.mp4").exists() is replay
    assert (target / "model.onnx").read_bytes() == b"onnx-bytes"
    assert (target / "README.md").exists()


def test_refuses_without_confirmation() -> None:
    assert prepare_upload.main(["--repo", "owner/name", "--license", "mit"]) == 2

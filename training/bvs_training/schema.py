"""bvs-schema-2 constants, mirrored from `game/ai/schema/bvs_schema_v2.gd`.

GDScript is the source of truth: Python never builds observations. These values
are only used to fail fast when Godot's `env_info` disagrees, and to write the
`bvs.json` sidecar. The layout fixture is read-only here.
"""

from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
LAYOUT_FIXTURE = REPO_ROOT / "tests" / "fixtures" / "schema" / "v2_layout.json"

SCHEMA_VERSION = 2
OBS_DIM = 102
ACTION_REPEAT = 4
BRANCHES: list[tuple[str, int]] = [
    ("a0_move", 3),
    ("a1_vertical", 3),
    ("a2_jump", 2),
    ("a3_attack", 5),
    ("a4_special", 2),
    ("a5_throw", 2),
    ("a6_block", 2),
    ("a7_dash", 2),
]
ACTION_NVEC: list[int] = [size for _, size in BRANCHES]
LOGITS = sum(ACTION_NVEC)


def sidecar_branches() -> list[dict]:
    return [{"name": name, "size": size} for name, size in BRANCHES]


def check_layout_fixture() -> None:
    """Assert the frozen field-name list matches OBS_DIM (read-only)."""
    names = json.loads(LAYOUT_FIXTURE.read_text())
    assert len(names) == OBS_DIM, f"layout fixture has {len(names)} fields, expected {OBS_DIM}"
    assert len(set(names)) == len(names), "layout fixture has duplicate field names"


def check_env(obs_shape: tuple[int, ...], nvec: list[int]) -> None:
    """Fail fast when Godot reports a different observation or action layout."""
    assert tuple(obs_shape) == (OBS_DIM,), f"Godot obs shape {obs_shape} != ({OBS_DIM},)"
    assert list(nvec) == ACTION_NVEC, f"Godot action nvec {list(nvec)} != {ACTION_NVEC}"


check_layout_fixture()

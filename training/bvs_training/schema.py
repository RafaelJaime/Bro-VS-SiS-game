"""bvs-schema constants, mirrored from `game/ai/schema/bvs_schema_v2.gd`, `bvs_schema_v3.gd` and `bvs_schema_v4.gd`.

GDScript is the source of truth: Python never builds observations. These values
are only used to fail fast when Godot's `env_info` disagrees, and to write the
`bvs.json` sidecar. The layout and golden fixtures are read-only here.

Schemas 2, 3 and 4 are registered (`SCHEMAS`); training, export and the sidecar target
`TRAIN_VERSION` (4, the character-kits schema: schema 3 plus 13 kit, chain, hitstun and
combo floats). The playable version of the game (`BvsSchema.CURRENT_VERSION`, still 3
until the gated schema 4 model is bundled) is a separate switch that only moves when a
retrained model passes every acceptance gate, so schemas 2 and 3 stay describable here.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_DIR = REPO_ROOT / "tests" / "fixtures" / "schema"

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


@dataclass(frozen=True)
class SchemaSpec:
    """The part of a bvs-schema that Python needs: its version and observation width."""

    version: int
    obs_dim: int

    @property
    def tag(self) -> str:
        """The Hugging Face model tag of this schema."""
        return f"bvs-schema-{self.version}"

    @property
    def layout_fixture(self) -> Path:
        return FIXTURE_DIR / f"v{self.version}_layout.json"

    @property
    def obs_fixture(self) -> Path:
        return FIXTURE_DIR / f"v{self.version}_obs_golden.json"


SCHEMAS: dict[int, SchemaSpec] = {
    2: SchemaSpec(version=2, obs_dim=102),
    3: SchemaSpec(version=3, obs_dim=136),
    4: SchemaSpec(version=4, obs_dim=149),
}

# The schema training, export and the sidecar target.
TRAIN_VERSION = 4
SCHEMA_VERSION = TRAIN_VERSION
OBS_DIM = SCHEMAS[TRAIN_VERSION].obs_dim
SCHEMA_TAG = SCHEMAS[TRAIN_VERSION].tag
LAYOUT_FIXTURE = SCHEMAS[TRAIN_VERSION].layout_fixture


def sidecar_branches() -> list[dict]:
    return [{"name": name, "size": size} for name, size in BRANCHES]


def layout_names(version: int) -> list[str]:
    """The field names of a schema, from its committed layout fixture (read-only)."""
    return json.loads(SCHEMAS[version].layout_fixture.read_text())


def check_layout_fixture(version: int = TRAIN_VERSION) -> None:
    """Assert the committed field-name list matches the schema's obs_dim (read-only)."""
    spec = SCHEMAS[version]
    names = layout_names(version)
    assert len(names) == spec.obs_dim, f"v{version} layout fixture has {len(names)} fields, expected {spec.obs_dim}"
    assert len(set(names)) == len(names), f"v{version} layout fixture has duplicate field names"


def check_obs_fixture(version: int = TRAIN_VERSION) -> None:
    """Assert every recorded golden observation of a schema has the schema's width (read-only)."""
    spec = SCHEMAS[version]
    golden = json.loads(spec.obs_fixture.read_text())
    assert golden["cases"], f"v{version} observation fixture holds no cases"
    for case in golden["cases"]:
        assert len(case["expected"]) == spec.obs_dim, (
            f"v{version} fixture case '{case.get('name')}' has {len(case['expected'])} values, expected {spec.obs_dim}"
        )
        assert case["my_index"] in (0, 1), f"v{version} fixture case '{case.get('name')}' has a bad my_index"


def check_env(obs_shape: tuple[int, ...], nvec: list[int], version: int = TRAIN_VERSION) -> None:
    """Fail fast when Godot reports a different observation or action layout."""
    obs_dim = SCHEMAS[version].obs_dim
    assert tuple(obs_shape) == (obs_dim,), f"Godot obs shape {obs_shape} != ({obs_dim},)"
    assert list(nvec) == ACTION_NVEC, f"Godot action nvec {list(nvec)} != {ACTION_NVEC}"


for _version in SCHEMAS:
    check_layout_fixture(_version)

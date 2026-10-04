"""`bvs.json` sidecar writer and validator (format `bvs-model/1`).

The validation mirrors `BvsSchema.validate_sidecar` in GDScript: schema_version,
obs_dim, action_branches (names and sizes, in order) and action_repeat must match
`bvs_training.schema` (the training schema, 4, unless a version is passed). The Hub
tag of a schema is `schema.SCHEMA_TAG` (`bvs-schema-4`).
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

from bvs_training import schema

FORMAT = "bvs-model/1"
ONNX_OPSET = 17


def git_commit() -> str:
    """HEAD of the repository, or "unknown" when git is unavailable."""
    try:
        out = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=schema.REPO_ROOT, capture_output=True, text=True, check=True
        )
        return out.stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def build_sidecar(
    label: str,
    difficulty_hint: str = "easy",
    eval_block: dict | None = None,
    onnx_file: str = "model.onnx",
    commit: str | None = None,
) -> dict:
    sidecar = {
        "format": FORMAT,
        "schema_version": schema.SCHEMA_VERSION,
        "obs_dim": schema.OBS_DIM,
        "action_branches": schema.sidecar_branches(),
        "action_repeat": schema.ACTION_REPEAT,
        "onnx": {"file": onnx_file, "input": "obs", "output": "logits", "opset": ONNX_OPSET},
        "trained_on_commit": commit if commit is not None else git_commit(),
        "label": label,
        "difficulty_hint": difficulty_hint,
    }
    if eval_block:
        sidecar["eval"] = eval_block
    problem = validate(sidecar)
    assert not problem, problem
    return sidecar


def validate(sidecar: dict, version: int = schema.TRAIN_VERSION) -> str:
    """"" when valid for schema `version` (default: the training schema), otherwise a short reason."""
    spec = schema.SCHEMAS[version]
    for key in ("schema_version", "obs_dim", "action_branches", "action_repeat", "trained_on_commit"):
        if key not in sidecar:
            return f"bvs.json is missing '{key}'"
    if sidecar["schema_version"] != spec.version:
        return f"schema_version {sidecar['schema_version']} != {spec.version}"
    if sidecar["obs_dim"] != spec.obs_dim:
        return f"obs_dim {sidecar['obs_dim']} != {spec.obs_dim}"
    if sidecar["action_branches"] != schema.sidecar_branches():
        return "action_branches do not match the schema"
    if sidecar["action_repeat"] != schema.ACTION_REPEAT:
        return f"action_repeat {sidecar['action_repeat']} != {schema.ACTION_REPEAT}"
    return ""


def write_sidecar(path: Path, sidecar: dict) -> None:
    problem = validate(sidecar)
    if problem:
        raise ValueError(problem)
    path.write_text(json.dumps(sidecar, indent=2, sort_keys=False) + "\n")


def sidecar_path_for(model_path: Path) -> Path:
    """`model.onnx` pairs with `bvs.json`; any other name with `<stem>.bvs.json`."""
    if model_path.name == "model.onnx":
        return model_path.with_name("bvs.json")
    return model_path.with_suffix(".bvs.json")


def eval_block_from_report(report_json: Path) -> dict:
    """The `eval` block of bvs.json from an `evaluate.py` JSON report."""
    reports = json.loads(report_json.read_text())["reports"]
    return {
        f"vs_cpu_{level}": {"matches": r["matches"], "win_rate": round(r["win_rate"], 4)}
        for level, r in reports.items()
    }


def main(argv: list[str] | None = None) -> int:
    """Rewrite `<model-dir>/bvs.json`, optionally with the eval block of a report."""
    import argparse

    parser = argparse.ArgumentParser(description=main.__doc__)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--label", default="BVS default")
    parser.add_argument("--difficulty-hint", default="easy")
    parser.add_argument("--eval-report", type=Path, help="evaluate.py JSON report to embed")
    args = parser.parse_args(argv)
    block = eval_block_from_report(args.eval_report) if args.eval_report else None
    side = build_sidecar(args.label, args.difficulty_hint, block)
    write_sidecar(args.model_dir / "bvs.json", side)
    print(f"wrote {args.model_dir / 'bvs.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Golden vectors for the GDScript ONNX interpreter (design D12).

    uv run python -m bvs_training.golden --check-ops
    uv run python -m bvs_training.golden --model ../game/ai/models/bvs_default/model.onnx \
        --obs-dump out/obs_dump.json --out ../tests/fixtures/onnx/bvs_default_golden.json

`--check-ops` regenerates the per-op fixtures (via `gen_op_fixtures`) and fails when
git sees any difference. `--model` runs onnxruntime on 32 seeded random observations
plus up to 32 recorded ones (`BVS_EVAL_OBS_DUMP`) and writes a deterministic JSON.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort

from bvs_training import gen_op_fixtures, schema

TOLERANCE = 1e-4
RANDOM_CASES = 32
RECORDED_CASES = 32
OBS_RANGE = 2.0  # inside the [-5, 5] clip range of the schema


def sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def argmax_per_branch(logits: np.ndarray) -> list[int]:
    """Argmax of each branch slice of the 21 logits; ties go to the lowest index."""
    result, start = [], 0
    for size in schema.ACTION_NVEC:
        result.append(int(np.argmax(logits[start : start + size])))
        start += size
    return result


def load_recorded(dump: Path | None) -> list[np.ndarray]:
    if dump is None or not dump.exists():
        return []
    payload = json.loads(dump.read_text())
    rows = payload["observations"] if isinstance(payload, dict) else payload
    observations = [np.asarray(row, dtype=np.float32) for row in rows]
    for obs in observations:
        assert obs.shape == (schema.OBS_DIM,), f"recorded observation has shape {obs.shape}"
    # Even spacing keeps the sample reproducible and spread over the whole match.
    if len(observations) > RECORDED_CASES:
        picks = np.linspace(0, len(observations) - 1, RECORDED_CASES).round().astype(int)
        observations = [observations[i] for i in picks]
    return observations


def build_golden(model_path: Path, dump: Path | None, repo_relative: str, seed: int = 7) -> dict:
    options = ort.SessionOptions()
    options.log_severity_level = 3
    session = ort.InferenceSession(model_path.read_bytes(), options, providers=["CPUExecutionProvider"])
    input_name = session.get_inputs()[0].name
    output_name = session.get_outputs()[0].name
    rng = np.random.default_rng(seed)
    observations = [
        ("random", rng.uniform(-OBS_RANGE, OBS_RANGE, size=schema.OBS_DIM).astype(np.float32))
        for _ in range(RANDOM_CASES)
    ] + [("recorded", obs) for obs in load_recorded(dump)]
    cases = []
    for source, obs in observations:
        logits = session.run([output_name], {input_name: obs.reshape(1, -1)})[0].reshape(-1)
        assert logits.shape == (schema.LOGITS,), logits.shape
        cases.append(
            {
                "source": source,
                "input": [float(v) for v in obs],
                "expected": [float(v) for v in logits],
                "argmax": argmax_per_branch(logits),
            }
        )
    return {
        "model": repo_relative,
        "sha256": sha256_of(model_path),
        "tolerance": TOLERANCE,
        "obs_dim": schema.OBS_DIM,
        "branches": schema.ACTION_NVEC,
        "cases": cases,
    }


def check_ops() -> int:
    gen_op_fixtures.generate()
    ops_dir = gen_op_fixtures.OUT_DIR
    status = subprocess.run(
        ["git", "status", "--porcelain", "--", str(ops_dir)],
        cwd=schema.REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    if status.strip():
        print("op fixtures differ from git:\n" + status, file=sys.stderr)
        return 1
    print("op fixtures regenerate with no diff")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check-ops", action="store_true", help="regenerate op fixtures and require no git diff")
    parser.add_argument("--model", type=Path, help="model.onnx to write goldens for")
    parser.add_argument("--obs-dump", type=Path, help="BVS_EVAL_OBS_DUMP JSON with recorded observations")
    parser.add_argument("--out", type=Path, help="golden JSON path")
    args = parser.parse_args(argv)

    if args.check_ops:
        return check_ops()
    if not args.model or not args.out:
        parser.error("pass --check-ops, or --model and --out")
    model = args.model.resolve()
    try:
        relative = str(model.relative_to(schema.REPO_ROOT))
    except ValueError:
        relative = str(model)
    golden = build_golden(model, args.obs_dump, relative)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(golden, sort_keys=True, indent=1) + "\n")
    print(f"wrote {args.out}: {len(golden['cases'])} cases, sha256 {golden['sha256'][:12]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

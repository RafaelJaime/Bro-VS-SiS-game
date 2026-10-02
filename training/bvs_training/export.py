"""Export the deterministic logits head of a PPO policy to ONNX (design D8).

    uv run python -m bvs_training.export --self-test
    uv run python -m bvs_training.export --random-init --out ../tests/fixtures/onnx/random_policy.onnx
    uv run python -m bvs_training.export --checkpoint out/run/final.zip --out out/bvs_default/model.onnx

Only whitelisted ops may appear; the file is written after the audit, the checker
and the onnxruntime-vs-torch check all pass.
"""

from __future__ import annotations

import argparse
import io
import sys
import tempfile
import warnings
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
import torch

from bvs_training import schema, sidecar
from bvs_training.onnx_ops import audit

# dynamo=False is pinned on purpose (design D8); the legacy exporter warns about it.
warnings.filterwarnings("ignore", message=".*legacy TorchScript-based ONNX export.*", category=DeprecationWarning)

OPSET = 17
PARITY_TOL = 1e-5
PARITY_CASES = 256


class ExportError(Exception):
    pass


class PolicyLogits(torch.nn.Module):
    """obs [1, 102] -> logits [1, 21]: policy trunk plus the action head."""

    def __init__(self, policy) -> None:
        super().__init__()
        self.pi = policy.mlp_extractor.policy_net
        self.head = policy.action_net

    def forward(self, obs: torch.Tensor) -> torch.Tensor:
        return self.head(self.pi(obs))


def build_policy(seed: int = 0):
    """A random-weight PPO policy with the shipped architecture (no environment needed)."""
    import gymnasium as gym
    from stable_baselines3.common.policies import MultiInputActorCriticPolicy

    obs_space = gym.spaces.Dict({"obs": gym.spaces.Box(-1.0, 1.0, (schema.OBS_DIM,), np.float32)})
    act_space = gym.spaces.MultiDiscrete(schema.ACTION_NVEC)
    torch.manual_seed(seed)
    return MultiInputActorCriticPolicy(
        obs_space,
        act_space,
        lambda _: 3e-4,
        net_arch=dict(pi=[64, 64], vf=[64, 64]),
        activation_fn=torch.nn.Tanh,
    )


def export_bytes(policy) -> bytes:
    """Export, audit, check and verify against torch; return the model bytes."""
    # The live layers are used as they are: a trained policy holds graph tensors that
    # deepcopy rejects. Training mode is restored afterwards.
    was_training = policy.training
    policy.set_training_mode(False)
    try:
        return _export_module(PolicyLogits(policy))
    finally:
        policy.set_training_mode(was_training)


def _export_module(module: torch.nn.Module) -> bytes:
    dummy = torch.zeros(1, schema.OBS_DIM, dtype=torch.float32)
    buffer = io.BytesIO()
    torch.onnx.export(
        module,
        (dummy,),
        buffer,
        opset_version=OPSET,
        dynamo=False,
        input_names=["obs"],
        output_names=["logits"],
        do_constant_folding=True,
    )
    data = buffer.getvalue()
    model = onnx.load_from_string(data)
    onnx.checker.check_model(model)
    problems = audit(model)
    if problems:
        raise ExportError("; ".join(problems))
    dims = [d.dim_value for d in model.graph.input[0].type.tensor_type.shape.dim]
    if dims != [1, schema.OBS_DIM]:
        raise ExportError(f"input shape {dims} != [1, {schema.OBS_DIM}]")
    out_dims = [d.dim_value for d in model.graph.output[0].type.tensor_type.shape.dim]
    if out_dims[-1] != schema.LOGITS:
        raise ExportError(f"output width {out_dims[-1]} != {schema.LOGITS}")
    check_parity(module, data)
    return data


def check_parity(module: torch.nn.Module, data: bytes) -> float:
    """Max abs difference between onnxruntime and torch on 256 random observations."""
    session = ort.InferenceSession(data, providers=["CPUExecutionProvider"])
    rng = np.random.default_rng(0)
    worst = 0.0
    for _ in range(PARITY_CASES):
        obs = rng.uniform(-1.5, 1.5, size=(1, schema.OBS_DIM)).astype(np.float32)
        with torch.no_grad():
            expected = module(torch.from_numpy(obs)).numpy()
        got = session.run(["logits"], {"obs": obs})[0]
        worst = max(worst, float(np.abs(expected - got).max()))
    if worst > PARITY_TOL:
        raise ExportError(f"onnxruntime differs from torch by {worst:.2e} (> {PARITY_TOL:.0e})")
    return worst


def export_policy(
    policy,
    out: Path,
    label: str = "BVS default",
    difficulty_hint: str = "easy",
    eval_block: dict | None = None,
    write_sidecar: bool = True,
) -> Path:
    data = export_bytes(policy)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    if write_sidecar:
        side = sidecar.build_sidecar(label, difficulty_hint, eval_block, onnx_file=out.name)
        sidecar.write_sidecar(sidecar.sidecar_path_for(out), side)
    return out


def load_checkpoint_policy(path: Path):
    from stable_baselines3 import PPO

    return PPO.load(str(path), device="cpu").policy


def self_test() -> None:
    policy = build_policy()
    with tempfile.TemporaryDirectory() as tmp:
        out = export_policy(policy, Path(tmp) / "model.onnx", label="self-test")
        assert out.stat().st_size > 0
        assert (Path(tmp) / "bvs.json").exists()
        model = onnx.load(str(out))
        ops = sorted({n.op_type for n in model.graph.node})
        print(f"self-test export ok: ops={ops} bytes={out.stat().st_size}")
    # An unsupported op must fail and write nothing.
    class WithGather(torch.nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.lin = torch.nn.Linear(schema.OBS_DIM, schema.LOGITS)

        def forward(self, obs: torch.Tensor) -> torch.Tensor:
            return self.lin(obs)[:, torch.tensor([0, 1, 2])]  # Gather

    buffer = io.BytesIO()
    torch.onnx.export(
        WithGather(), (torch.zeros(1, schema.OBS_DIM),), buffer, opset_version=OPSET, dynamo=False,
        input_names=["obs"], output_names=["logits"],
    )
    problems = audit(onnx.load_from_string(buffer.getvalue()))
    assert any("Gather" in p or "Slice" in p or "Shape" in p for p in problems), problems
    print(f"self-test unsupported-op audit ok: {problems[0]}")
    print("EXPORT SELF-TEST PASSED")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true", help="export a random-init policy to a temp dir and audit it")
    parser.add_argument("--random-init", action="store_true", help="export a random-weight policy (fixtures)")
    parser.add_argument("--seed", type=int, default=0, help="seed of the random-init weights")
    parser.add_argument("--checkpoint", type=Path, help="SB3 PPO .zip checkpoint")
    parser.add_argument("--out", type=Path, help="output model.onnx path")
    parser.add_argument("--label", default="BVS default")
    parser.add_argument("--difficulty-hint", default="easy")
    args = parser.parse_args(argv)

    if args.self_test:
        self_test()
        return 0
    if not args.out:
        parser.error("--out is required")
    if args.random_init == bool(args.checkpoint):
        parser.error("pass exactly one of --random-init or --checkpoint")
    policy = build_policy(args.seed) if args.random_init else load_checkpoint_policy(args.checkpoint)
    try:
        out = export_policy(policy, args.out, args.label, args.difficulty_hint)
    except ExportError as err:
        print(f"export failed: {err}", file=sys.stderr)
        return 1
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Phased PPO training against the headless BVS training scene (design D11).

    uv run python -m bvs_training.train --phase P1 --steps 4096 --seed 1      # smoke run
    uv run python -m bvs_training.train --config configs/default.toml          # full curriculum

Per phase it writes a BVS_TRAIN_CONFIG JSON (rows and reward overrides), opens a
fresh Godot env, trains, checkpoints, and closes the env. Stop early with
`touch training/out/STOP`; the run also ends at the time box.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import sys
import time
import tomllib
from pathlib import Path

import torch
from godot_rl.wrappers.stable_baselines_wrapper import StableBaselinesGodotEnv
from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import BaseCallback
from stable_baselines3.common.utils import set_random_seed
from stable_baselines3.common.vec_env import VecMonitor

from bvs_training import schema
from bvs_training.export import ExportError, export_policy
from bvs_training.handshake import launcher_arg

TRAINING_DIR = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = TRAINING_DIR / "configs" / "default.toml"
DEFAULT_OUT = TRAINING_DIR / "out"
CPU_KINDS = ("cpu_easy", "cpu_normal", "cpu_hard")


def load_config(path: Path) -> dict:
    with path.open("rb") as handle:
        return tomllib.load(handle)


def allocate_rows(mix: dict[str, float], rows: int) -> list[str]:
    """Integer row counts for a share mix (largest remainder), as a flat opponent list."""
    total = sum(mix.values())
    assert total > 0, "phase mix is empty"
    exact = {kind: share / total * rows for kind, share in mix.items()}
    counts = {kind: int(value) for kind, value in exact.items()}
    leftover = rows - sum(counts.values())
    for kind in sorted(exact, key=lambda k: exact[k] - counts[k], reverse=True)[:leftover]:
        counts[kind] += 1
    result: list[str] = []
    for kind, count in counts.items():
        result.extend([kind] * count)
    return result


def build_rows(phase: dict, run: dict, seed: int, snapshots: list[Path]) -> list[dict]:
    mix = dict(phase["mix"])
    if "snapshot" in mix and not (run.get("snapshot_opponents", False) and snapshots):
        share = mix.pop("snapshot")
        mix["cpu_normal"] = mix.get("cpu_normal", 0.0) + share
        print(f"WARNING: snapshot opponents unavailable; {share:.0%} of {phase['name']} goes to cpu_normal")
    kinds = allocate_rows(mix, int(run.get("rows", 8)))
    rng = random.Random(seed)
    rows = []
    for index, kind in enumerate(kinds):
        spec: dict = {"opponent": kind, "seed": seed * 1000 + index}
        if kind == "snapshot":
            spec["model"] = str(rng.choice(snapshots))
        rows.append(spec)
    return rows


def write_phase_config(out_dir: Path, phase: dict, run: dict, reward: dict, seed: int, snapshots: list[Path]) -> Path:
    config = {"rows": build_rows(phase, run, seed, snapshots), "reward": reward, "episode_log": True}
    path = out_dir / f"train_config_{phase['name']}.json"
    path.write_text(json.dumps(config, indent=2))
    return path


class BvsCallback(BaseCallback):
    """Checkpoints, snapshot export, stop file and time box."""

    def __init__(self, out_dir: Path, every: int, deadline: float | None, stop_file: Path, snapshots: list[Path]):
        super().__init__()
        self.out_dir = out_dir
        self.every = max(1, every)
        self.deadline = deadline
        self.stop_file = stop_file
        self.snapshots = snapshots
        self.next_checkpoint = self.every
        self.started = time.time()
        self.start_steps = 0
        self.stopped_by = ""

    def _on_training_start(self) -> None:
        self.started = time.time()
        self.start_steps = self.num_timesteps
        self.next_checkpoint = (self.num_timesteps // self.every + 1) * self.every

    def save_checkpoint(self, tag: str) -> Path:
        ckpt_dir = self.out_dir / "checkpoints"
        ckpt_dir.mkdir(parents=True, exist_ok=True)
        path = ckpt_dir / f"step_{tag}.zip"
        self.model.save(str(path))
        try:
            snap = export_policy(
                self.model.policy, self.out_dir / "snapshots" / f"step_{tag}.onnx", write_sidecar=False
            )
            self.snapshots.append(snap.resolve())
        except ExportError as err:
            print(f"WARNING: snapshot export failed at {tag}: {err}")
        print(f"checkpoint {path}")
        return path

    def _on_step(self) -> bool:
        if self.num_timesteps >= self.next_checkpoint:
            self.save_checkpoint(str(self.num_timesteps))
            self.next_checkpoint += self.every
        return not self.stopped_by

    def _on_rollout_end(self) -> None:
        elapsed = max(time.time() - self.started, 1e-6)
        rate = (self.num_timesteps - self.start_steps) / elapsed
        print(f"THROUGHPUT agent_steps={self.num_timesteps} agent_steps_per_s={rate:.0f}")
        if self.stop_file.exists():
            self.stopped_by = "stop file"
        elif self.deadline is not None and time.time() > self.deadline:
            self.stopped_by = "time box"


def make_env(config_path: Path, run: dict, seed: int, n_parallel: int, speedup: int) -> VecMonitor:
    os.environ["BVS_TRAIN_CONFIG"] = str(config_path)
    env = StableBaselinesGodotEnv(
        env_path=launcher_arg(),
        n_parallel=n_parallel,
        seed=seed,
        action_repeat=schema.ACTION_REPEAT,
        speedup=speedup,
    )
    schema.check_env(env.observation_space["obs"].shape, env.action_space.nvec.tolist())
    return VecMonitor(env)


def make_model(env: VecMonitor, ppo: dict, seed: int) -> PPO:
    return PPO(
        "MultiInputPolicy",
        env,
        n_steps=int(ppo["n_steps"]),
        batch_size=int(ppo["batch_size"]),
        n_epochs=int(ppo["n_epochs"]),
        learning_rate=float(ppo["learning_rate"]),
        gamma=float(ppo["gamma"]),
        gae_lambda=float(ppo["gae_lambda"]),
        ent_coef=float(ppo["ent_coef"]),
        clip_range=float(ppo["clip_range"]),
        policy_kwargs=dict(
            net_arch=dict(pi=list(ppo["net_arch_pi"]), vf=list(ppo["net_arch_vf"])),
            activation_fn=torch.nn.Tanh,
        ),
        seed=None,  # PPO(seed=...) calls env.seed(), which godot-rl does not implement
        verbose=1,
        device="cpu",
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--phase", default="all", help="phase name (P1, P2, P3) or 'all'")
    parser.add_argument("--steps", type=int, help="override the steps of every selected phase (smoke runs)")
    parser.add_argument("--seed", type=int, help="override run.seed")
    parser.add_argument("--n-parallel", type=int, help="override run.n_parallel")
    parser.add_argument("--speedup", type=int, help="override run.speedup")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--resume", type=Path, help="continue from an SB3 .zip checkpoint")
    parser.add_argument("--checkpoint-every", type=int, help="override run.checkpoint_every")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    run, ppo, reward = config["run"], config["ppo"], config.get("reward", {})
    phases = [p for p in config["phase"] if args.phase in ("all", p["name"])]
    if not phases:
        parser.error(f"no phase named {args.phase}")
    seed = args.seed if args.seed is not None else int(run["seed"])
    n_parallel = args.n_parallel or int(run["n_parallel"])
    speedup = args.speedup or int(run["speedup"])
    every = args.checkpoint_every or int(run["checkpoint_every"])

    out_dir = args.out
    out_dir.mkdir(parents=True, exist_ok=True)
    stop_file = out_dir / "STOP"
    stop_file.unlink(missing_ok=True)
    started = time.time()
    deadline = started + float(run["time_box_hours"]) * 3600
    set_random_seed(seed)  # python, numpy and torch; Godot gets --env_seed from make_env

    snapshots: list[Path] = []
    model: PPO | None = None
    last_checkpoint: Path | None = None
    for phase in phases:
        if time.time() > deadline or stop_file.exists():
            print(f"stopping before {phase['name']}: time box or stop file")
            break
        steps = args.steps if args.steps is not None else int(phase["steps"])
        config_path = write_phase_config(out_dir, phase, run, reward, seed, snapshots)
        print(f"=== phase {phase['name']}: {steps} steps, config {config_path}")
        env = make_env(config_path, run, seed, n_parallel, speedup)
        try:
            if model is None:
                model = PPO.load(str(args.resume), env=env, device="cpu") if args.resume else make_model(env, ppo, seed)
            else:
                model.set_env(env)
            callback = BvsCallback(out_dir, every, deadline, stop_file, snapshots)
            phase_started = time.time()
            before = model.num_timesteps
            model.learn(steps, callback=callback, reset_num_timesteps=False, tb_log_name=phase["name"])
            gained = model.num_timesteps - before
            wall = max(time.time() - phase_started, 1e-6)
            print(f"PHASE_DONE {phase['name']} agent_steps={gained} wall_s={wall:.1f} agent_steps_per_s={gained / wall:.0f}")
            last_checkpoint = callback.save_checkpoint(f"{phase['name']}_final")
            if callback.stopped_by:
                print(f"stopped by {callback.stopped_by}")
                break
        finally:
            env.close()

    if model is None or last_checkpoint is None:
        print("nothing trained", file=sys.stderr)
        return 1
    model.save(str(out_dir / "final.zip"))
    print(f"final model {out_dir / 'final.zip'}; checkpoints under {out_dir / 'checkpoints'}")
    print(f"TRAIN DONE in {time.time() - started:.0f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

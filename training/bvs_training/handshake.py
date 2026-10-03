"""Handshake spike: godot-rl <-> addon protocol 0.7 on the BVS training scene.

    cd training && uv run python -m bvs_training.handshake
"""

from __future__ import annotations

import os
import time
from pathlib import Path

import numpy as np
from godot_rl.wrappers.stable_baselines_wrapper import StableBaselinesGodotEnv

from bvs_training import schema

LAUNCHER = Path(__file__).resolve().parents[1] / "bin" / "bvs-godot"


def launcher_arg() -> str:
    """godot-rl on macOS rewrites X to X.app/Contents/MacOS/X and splits on spaces,
    so pass a relative path (no dotted or spaced directories)."""
    return os.path.relpath(LAUNCHER)


def main() -> int:
    env = StableBaselinesGodotEnv(
        env_path=launcher_arg(), n_parallel=1, action_repeat=schema.ACTION_REPEAT, speedup=8
    )
    try:
        print("observation_space", env.observation_space)
        print("action_space", env.action_space)
        assert env.action_space.__class__.__name__ == "MultiDiscrete", env.action_space
        schema.check_env(env.observation_space["obs"].shape, env.action_space.nvec.tolist())
        print("num_envs", env.num_envs)

        obs = env.reset()
        assert obs["obs"].shape == (env.num_envs, schema.OBS_DIM), obs["obs"].shape
        rng = np.random.default_rng(0)
        dones = 0
        steps = 0
        start = time.time()
        # One match is 99 s of game time = ~1500 decisions at action_repeat 4.
        for steps in range(1, 2500):
            actions = np.stack([env.action_space.sample() for _ in range(env.num_envs)])
            env.step_async(actions)
            obs, rewards, term, _info = env.step_wait()
            if term.any():
                dones += int(term.sum())
                break
        elapsed = time.time() - start
        print(f"steps={steps} dones={dones} elapsed={elapsed:.1f}s")
        assert dones > 0, "no done within one match"
        print("HANDSHAKE OK")
    finally:
        env.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

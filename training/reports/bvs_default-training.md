# Training notes: bvs_default

Machine: Apple M5 (10 cores, 24 GB), Godot 4.7.2 headless, godot-rl 0.8.2, stable-baselines3 2.3.2, torch 2.14.1 (CPU). Seed 1. Time-box start 2026-10-03 00:00 (CEST); the whole S5 run took under 1 hour of the 8 h box. Curriculum and hyperparameters are `configs/default.toml` unchanged (reward overrides empty, defaults of `game/ai/training/reward_config.gd`); the only flag changed was `--n-parallel 8` (8 Godot processes of 8 rows, 6.8k to 7.8k agent steps per second measured, config default stays 4).

## Runs

| Run | Phases | Agent steps | Wall time | Config changes | Result (40 or 20 matches, sides alternating) |
|-----|--------|-------------|-----------|----------------|----------------------------------------------|
| run1 | P1 only (100% CPU Easy) | 3.01M | 455 s | none | 20 matches each: Easy 20 W 0 L, Normal 20 W 0 L, all KO wins, 0 timeouts |
| run2 (shipped) | P1 (CPU Easy) then P2 (50/50 Easy/Normal) then P3 (30% Normal, 20% Easy, 20% self-play, 30% frozen snapshots) | 3.01M + 3.01M + 4.01M = 10.04M | 444 s + 440 s + 512 s (P3 resumed after a fix, below) | none to the recipe | P2 checkpoint 20 matches: Easy 20 W, Normal 20 W; P3 final 40 matches: Easy 40 W, Normal 40 W, Hard 40 W (all KO wins) |

run2 P3 failed to start on the first attempt: SB3 `set_env` refuses a changed number of environments, and self-play rows add agents (both sides learn: 64 envs in P1 and P2, 80 in P3). `train.py` now reloads the model through `PPO.load(..., env=env)` in that case and `--resume` seeds the snapshot pool from `out/snapshots`. P3 was then started with `--phase P3 --resume out/run2/checkpoints/step_P2_final.zip` (same optimizer state and step counter, 24 snapshots from P1 and P2 in the pool, 2 of 8 rows per process playing a snapshot). No reward or curriculum adjustment was needed: no run degenerated, so no further runs were made.

## Quality gate (shipped model, `bvs_default-eval.md`)

Gate vs CPU Easy: at least 0.60 over at least 20 matches. Result: 1.00 over 40, every win a KO (0 timeout wins), 0 stocks lost against any level. Behavior over the 40 matches versus Easy: approach ratio 0.29 (mean fighter gap 217 px), recovery succeeded in 6 of 8 off-stage events (Normal 11 of 12, Hard 9 of 10), idle share 0.03, mean match 18.7 s, action entropy between 0.70 and 1.51 bits on every branch (no branch collapsed to one action; `a3_attack` leans on indices 0, 1 and 4 and never uses 2 and 3). Self-KO share is 0.00 (no stock was lost at all).

Interpreter checks: parity with onnxruntime max abs error 1.4e-6 with exact argmax on 64 golden cases (32 seeded, 32 recorded in matches); 355 us per inference headless.

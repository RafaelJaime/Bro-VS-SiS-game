# Training notes: bvs_default (schema 3, combat depth)

Machine: Apple M5 (10 cores, 24 GB), Godot 4.7.2 headless, godot-rl 0.8.2, stable-baselines3 2.3.2, torch 2.14.1 (CPU). Seed 1. Trained on commit `7bf9e3a` (`bvs-schema-3`).

## Runs

| Run | Phases | Agent steps | Wall time | Config changes | Gates |
|-----|--------|-------------|-----------|----------------|-------|
| sanity | P1, P2, P3 with `--steps 100000` each, `--n-parallel 4` | 0.3M | 133 s | none | 1033 `BVS_EPISODE` lines with the new terms; SD-start rows present in the P2 config; no `SCRIPT ERROR` (only the usual headless "resources still in use at exit" lines) |
| r1 (shipped) | P1 (CPU Easy), P2 (Easy/Normal, `sd_start` 0.125), P3 (Normal, Easy, self-play, snapshots, `sd_start` 0.25) | 10.04M | 2817 s | none to `configs/default.toml` (flags: `--n-parallel 8`, `--seed 1`) | all pass, first run |

No reward or curriculum iteration was needed: the first full run passed every gate, so no second run was made.

## Gates (shipped model)

- Parity: 64 golden cases (32 random, 32 recorded), max abs error 1e-6, exact argmax, validates against `bvs-schema-3`.
- Evaluation (`bvs_default-eval.md`, 40 matches per level): Easy 40 W, Normal 40 W, Hard 38 W 2 L, all KO wins; self-KO share 0.06 versus Easy, idle share 0.08 to 0.10, recovery success 0.72 to 0.76, action entropy 0.37 to 1.95 bits on every branch.
- Harness (`bvs_default-harness.md`, seed 1, 20 matches per matchup): mean forced sudden death 6.7 s (limit 45), pickups per fighter-minute 1.73 in model-vs-model (limit above 1), blocked share 0.57 (limit 0.70), KO win rate versus Easy 1.00 (floor 0.60).

## Notes

- The model-vs-model regulation matches are long (mean 97 s, KO results 16 of 20; mean sudden death 5.4 s, longest 12.5 s) because both sides shield often (248 shield breaks over 20 matches). Matches that reach a tie end in sudden death within seconds.
- Against a passive human the policy moves and attacks but also holds the shield long enough to break it (observed in `policy_select`); the training opponents are never passive.
- `train.py` now resolves `--out` to an absolute path: Godot reads `BVS_TRAIN_CONFIG` from its own working directory, so a relative `--out` made every row fail.

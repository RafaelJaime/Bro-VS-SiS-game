# BVS default

The bundled fighter of Bro vs Sis: a `bvs-schema-3` policy trained with PPO
(stable-baselines3) and exported to ONNX. It is the "AI: BVS default" entry in
character select and works offline on desktop and web.

## Contract (`bvs-schema-3`)

- MLP only (136 -> 64 -> 64 -> 21, Tanh; ops `Gemm`, `Tanh`). The game runs it with its
  own GDScript interpreter, no onnxruntime.
- Input `obs`: `[1, 136]` float32, built by the game from the match snapshot
  (`game/ai/schema/bvs_schema_v3.gd`): both fighters' shield meter, dizzy and air dodge, food
  tags, the nearest sudden-death bombs and the sudden-death phase.
- Output `logits`: `[1, 21]`, eight discrete branches `[3, 3, 2, 5, 2, 2, 2, 2]`
  (`a0_move`, `a1_vertical`, `a2_jump`, `a3_attack`, `a4_special`, `a5_throw`,
  `a6_block`, `a7_dash`). One decision every 4 physics frames, argmax per branch.

## Training

Curriculum of three PPO phases (about 10M agent steps, 8 Godot processes, 64 to 80
parallel agents, about 47 minutes on an Apple M5): P1 versus CPU Easy, P2 versus a
50/50 Easy and Normal mix (an eighth of the rows start every episode in sudden death),
P3 versus a mix of CPU Normal, CPU Easy, self-play and frozen snapshots of its own
earlier checkpoints (a quarter of the rows start in sudden death). Reward: damage
dealt and taken, KO and stock terms, win and loss, a small time cost, an off-stage
penalty, a potential-based approach term, and the combat-depth terms (food picked up,
food landed on the opponent, shield broken or lost, a long shield hold). The recipe,
exact configuration and per-run notes are in `training/` (`configs/default.toml`,
`reports/bvs_default-training.md`).

## Evaluation

Full matches in the game with the shipped interpreter, sides alternating, 40 matches
per level (`training/reports/bvs_default-eval.md`):

| Opponent | Win rate | KO wins | Timeout wins | Stocks lost (mean) |
|----------|----------|---------|--------------|--------------------|
| CPU Easy | 1.00 | 40 | 0 | 0.42 |
| CPU Normal | 1.00 | 40 | 0 | 0.70 |
| CPU Hard | 0.95 | 38 | 0 | 1.00 |

Combat-depth acceptance harness (`training/reports/bvs_default-harness.md`, 20 matches
per matchup): forced sudden death model versus model ends in 6.7 s on average (gate 45 s),
1.73 food pickups per fighter-minute in the toughest matchup (gate above 1.0), blocked
share 0.57 (gate at most 0.70), 100% KO wins versus CPU Easy.

It wins by knockout (about 38 seconds a match), uses food, shield and air dodge, gets
back on stage after being sent off (recovery succeeds in about three of four off-stage
events) and mixes its moves instead of repeating one. It is strong against the scripted
CPUs; it was not trained against humans, and it shields a lot (about a third of its
decisions raise the shield), so it can break its own shield against a passive opponent.

## Files

- `model.onnx`: the policy (logits head only, opset 17).
- `bvs.json`: the sidecar (`bvs-model/1`): schema version, observation size, action
  branches, `action_repeat`, provenance and the evaluation block.
- Golden parity vectors: `tests/fixtures/onnx/bvs_default_golden.json` (checked by
  `tests/smoke/onnx_golden.gd`).

The game loads these from `res://` with no network. The `export_presets.cfg`
`include_filter` keeps them in the exported package.

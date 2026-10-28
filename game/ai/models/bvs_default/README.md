# BVS default

The bundled fighter of Bro vs Sis: a `bvs-schema-4` policy trained with PPO
(stable-baselines3) and exported to ONNX. It is the "AI: BVS default" entry in
character select and works offline on desktop and web.

Promoted under the character-kits-combos Resolved Decision (b): the retrain time box
(4 full runs) was exhausted with one acceptance gate still failing (`kit_win_share`
0.88 in model-vs-model, band 0.4-0.6; the CPU Hard mirror of the same kit data stayed
in band at 0.47). Every other gate passes; see `training/reports/bvs_default-harness.md`.

## Contract (`bvs-schema-4`)

- MLP only (149 -> 64 -> 64 -> 21, Tanh; ops `Gemm`, `Tanh`). The game runs it with its
  own GDScript interpreter, no onnxruntime.
- Input `obs`: `[1, 149]` float32, built by the game from the match snapshot
  (`game/ai/schema/bvs_schema_v4.gd`): both fighters' shield meter, dizzy and air dodge, food
  tags, the nearest sudden-death bombs, the sudden-death phase, plus the fighter kits, the
  jab chain step and link window, the opponent's hitstun and the combo dealt and taken.
  Indices 0-135 are the `bvs-schema-3` vector byte for byte.
- Output `logits`: `[1, 21]`, eight discrete branches `[3, 3, 2, 5, 2, 2, 2, 2]`
  (`a0_move`, `a1_vertical`, `a2_jump`, `a3_attack`, `a4_special`, `a5_throw`,
  `a6_block`, `a7_dash`). One decision every 4 physics frames, argmax per branch.

## Fighter kits

Both Rafael (`kit_id` 0) and Matilde (`kit_id` 1) are played on both sides during
training (random per episode and per side, mirrors included), so one policy plays
both kits and both match-ups.

## Training

S6 of `openspec/changes/character-kits-combos`: one retrain covering the shield-spam
fix (`odd/tasks/shield-spam.md` T4) and the kits. R0 sanity, then R1 the full
`default.toml` curriculum (10M agent steps, 8 Godot processes, about 52 minutes on an
Apple M5), then R2-R4 one lever group per run (kit data, reward weights) within the
time box. Reward: damage dealt and taken, KO and stock terms, win and loss, a small
time cost, an off-stage penalty, a potential-based approach term, the combat-depth
terms (food picked up, food landed on the opponent, shield broken or lost, a long
shield hold) and the character-kits terms (a capped combo-hit bonus, a shield-raise
cost). The recipe, exact configuration and the run-by-run record are in `training/`
(`configs/default.toml`, `reports/bvs_default-training.md`).

## Evaluation

Full matches in the game with the shipped interpreter, sides alternating, 20 matches
per level (`training/reports/bvs_default-eval.md`):

| Opponent | Win rate | KO wins | Timeout wins | Stocks lost (mean) |
|----------|----------|---------|--------------|--------------------|
| CPU Easy | 1.00 | 20 | 0 | 0.00 |
| CPU Normal | 1.00 | 20 | 0 | 0.10 |
| CPU Hard | 1.00 | 20 | 0 | 0.15 |

Acceptance harness (`training/reports/bvs_default-harness.md`, seed 1, kits `rm`, 172
matches): forced sudden death model versus model ends in 2.5 s on average (gate 45 s),
6.64 food pickups per fighter-minute in the toughest matchup (gate above 1.0), blocked
share 0.23 (gate at most 0.70), 100% KO wins versus CPU Easy, shield raises and shield
taps within gate, combo length and Hurt duration within gate, combo damage balanced
within 20% between kits. The one FAIL is `kit_win_share` (Rafael wins 0.88 of
model-vs-model, band 0.4-0.6; promoted under Resolved Decision (b), see above).

It wins by knockout, uses food, shield and air dodge, and mixes its moves instead of
repeating one. It is strong against the scripted CPUs; it was not trained against
humans. mvm's Rafael win-share moved across the S6 runs while the CPU Hard mirror of
the same kit data stayed in band, read as self-play policy variance rather than a
stable kit-data imbalance (see `bvs_default-training.md`).

## Files

- `model.onnx`: the policy (logits head only, opset 17).
- `bvs.json`: the sidecar (`bvs-model/1`): schema version, observation size, action
  branches, `action_repeat`, provenance and the evaluation block.
- Golden parity vectors: `tests/fixtures/onnx/bvs_default_golden.json` (checked by
  `tests/smoke/onnx_golden.gd`).

The game loads these from `res://` with no network. The `export_presets.cfg`
`include_filter` keeps them in the exported package.

## License

MIT, same as the rest of the project (see the repository [LICENSE](../../../../LICENSE)). The published Hugging Face twin [RafaelJaime/BVS-default](https://huggingface.co/RafaelJaime/BVS-default) is also MIT.

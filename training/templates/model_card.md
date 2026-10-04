---
license: $license
library_name: stable-baselines3
tags:
  - BVS
  - bvs-schema-4
  - reinforcement-learning
  - onnx
model-index:
  - name: $repo_name
    results:
$results_yaml
---

# $label

A fighter policy for Bro vs Sis, trained with PPO (stable-baselines3) and exported to ONNX.

## Contract (`bvs-schema-4`)

- MLP only: the graph may use `Gemm`, `MatMul`, `Add`, `Mul`, `Relu`, `Tanh`, `Sigmoid`, `Clip`, `Identity`, `Flatten`, `Reshape`, `Squeeze`, `Unsqueeze`, `Concat` and `Constant`. The game runs it with its own GDScript interpreter (no onnxruntime), so other ops are rejected.
- Input `obs`: `[1, 149]` float32, built by the game from the match snapshot (own and opponent state including shield meter, dizzy and air dodge, food and projectile slots, the two nearest sudden-death bombs, match timer and sudden-death phase, plus the fighter kits, the jab chain step and link window, the opponent hitstun and the combo dealt and taken). Indices 0-135 are the `bvs-schema-3` vector.
- Output `logits`: `[1, 21]`, the concatenated logits of eight discrete branches `[3, 3, 2, 5, 2, 2, 2, 2]` (`a0_move`, `a1_vertical`, `a2_jump`, `a3_attack`, `a4_special`, `a5_throw`, `a6_block`, `a7_dash`). The game takes the argmax of each branch, one decision every 4 physics frames. While holding food, `a5_throw` is exclusive (a punch and a throw never fire together), and in the air `a6_block` is the air dodge.
- `bvs.json` declares the schema version, observation size, action layout and `action_repeat`; a model whose sidecar does not match is refused with a visible reason.

## Evaluation

Played in the game with the same interpreter players use, full matches versus the scripted CPU, sides alternating.

$results_table

## Files

- `model.onnx`: the policy (logits head only, opset 17).
- `bvs.json`: the schema sidecar (trained on commit `$commit`).

## License

$license

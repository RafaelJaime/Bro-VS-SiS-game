---
license: $license
library_name: stable-baselines3
tags:
  - BVS
  - bvs-schema-2
  - reinforcement-learning
  - onnx
model-index:
  - name: $repo_name
    results:
$results_yaml
---

# $label

A fighter policy for Bro vs Sis, trained with PPO (stable-baselines3) and exported to ONNX.

## Contract (`bvs-schema-2`)

- MLP only: the graph may use `Gemm`, `MatMul`, `Add`, `Mul`, `Relu`, `Tanh`, `Sigmoid`, `Clip`, `Identity`, `Flatten`, `Reshape`, `Squeeze`, `Unsqueeze`, `Concat` and `Constant`. The game runs it with its own GDScript interpreter (no onnxruntime), so other ops are rejected.
- Input `obs`: `[1, 102]` float32, built by the game from the match snapshot.
- Output `logits`: `[1, 21]`, the concatenated logits of eight discrete branches `[3, 3, 2, 5, 2, 2, 2, 2]` (`a0_move`, `a1_vertical`, `a2_jump`, `a3_attack`, `a4_special`, `a5_throw`, `a6_block`, `a7_dash`). The game takes the argmax of each branch, one decision every 4 physics frames.
- `bvs.json` declares the schema version, observation size, action layout and `action_repeat`; a model whose sidecar does not match is refused with a visible reason.

## Evaluation

Played in the game with the same interpreter players use, full matches versus the scripted CPU, sides alternating.

$results_table

## Files

- `model.onnx`: the policy (logits head only, opset 17).
- `bvs.json`: the schema sidecar (trained on commit `$commit`).

## License

$license

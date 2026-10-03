# Evaluation: bvs_default

Played in Godot with the shipped GDScript ONNX interpreter, full matches versus the scripted CPU, sides alternating.

| Level | Matches | Win rate | Wins | Losses | Draws | Stocks taken (mean) | Stocks lost (mean) |
|-------|---------|----------|------|--------|-------|---------------------|--------------------|
| easy | 40 | 1.00 | 40 | 0 | 0 | 3.00 | 0.00 |
| normal | 40 | 1.00 | 40 | 0 | 0 | 3.00 | 0.00 |
| hard | 40 | 1.00 | 40 | 0 | 0 | 3.00 | 0.00 |

## Behavior indicators

| Level | Approach ratio | Attacks thrown | Recoveries | Self-KO share of stocks lost | Idle share | Mean match (s) |
|-------|----------------|----------------|------------|------------------------------|------------|----------------|
| easy | 0.29 | 6346 | 6 | 0.00 | 0.03 | 18.7 |
| normal | 0.36 | 6890 | 11 | 0.00 | 0.03 | 19.4 |
| hard | 0.43 | 7461 | 9 | 0.00 | 0.03 | 20.0 |

## Play quality

| Level | KO wins | Timeout wins | KO losses | Timeout losses | Off-stage events | Recovery success | Specials | Mean gap (px) |
|-------|---------|--------------|-----------|----------------|------------------|------------------|----------|---------------|
| easy | 40 | 0 | 0 | 0 | 8 | 0.75 | 2752 | 217 |
| normal | 40 | 0 | 0 | 0 | 12 | 0.92 | 2530 | 204 |
| hard | 40 | 0 | 0 | 0 | 10 | 0.90 | 2310 | 189 |

## Action distribution vs easy (share of decisions per branch index, entropy in bits)

| Branch | Shares | Entropy |
|--------|--------|---------|
| a0_move | 0.20, 0.53, 0.27 | 1.45 |
| a1_vertical | 0.19, 0.40, 0.41 | 1.51 |
| a2_jump | 0.74, 0.26 | 0.83 |
| a3_attack | 0.52, 0.32, 0.00, 0.00, 0.16 | 1.48 |
| a4_special | 0.75, 0.25 | 0.80 |
| a5_throw | 0.68, 0.32 | 0.90 |
| a6_block | 0.49, 0.51 | 1.00 |
| a7_dash | 0.81, 0.19 | 0.70 |

## Action distribution vs normal (share of decisions per branch index, entropy in bits)

| Branch | Shares | Entropy |
|--------|--------|---------|
| a0_move | 0.19, 0.54, 0.27 | 1.45 |
| a1_vertical | 0.21, 0.38, 0.41 | 1.53 |
| a2_jump | 0.75, 0.25 | 0.81 |
| a3_attack | 0.48, 0.31, 0.00, 0.00, 0.21 | 1.53 |
| a4_special | 0.78, 0.22 | 0.76 |
| a5_throw | 0.69, 0.31 | 0.89 |
| a6_block | 0.49, 0.51 | 1.00 |
| a7_dash | 0.78, 0.22 | 0.76 |

## Action distribution vs hard (share of decisions per branch index, entropy in bits)

| Branch | Shares | Entropy |
|--------|--------|---------|
| a0_move | 0.17, 0.57, 0.26 | 1.40 |
| a1_vertical | 0.22, 0.36, 0.42 | 1.54 |
| a2_jump | 0.79, 0.21 | 0.75 |
| a3_attack | 0.45, 0.31, 0.00, 0.00, 0.24 | 1.56 |
| a4_special | 0.81, 0.19 | 0.71 |
| a5_throw | 0.69, 0.31 | 0.89 |
| a6_block | 0.51, 0.49 | 1.00 |
| a7_dash | 0.82, 0.18 | 0.67 |

Gate: win rate versus CPU Easy at least 0.60 over at least 20 matches: **PASS** (1.00 over 40).

## Publication

Published (public, MIT) at https://huggingface.co/RafaelJaime/BVS-default, commit `8229490c7c1b5925b8353a80ae0295eda25fa589`, tags `BVS`, `bvs-schema-2`, `reinforcement-learning`. Verified read-only via `GET /api/models?author=RafaelJaime&filter=BVS`.

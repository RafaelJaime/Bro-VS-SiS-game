# Evaluation: bvs_default

Played in Godot with the shipped GDScript ONNX interpreter, full matches versus the scripted CPU, sides alternating.

| Level | Matches | Win rate | Wins | Losses | Draws | Stocks taken (mean) | Stocks lost (mean) |
|-------|---------|----------|------|--------|-------|---------------------|--------------------|
| easy | 40 | 1.00 | 40 | 0 | 0 | 3.00 | 0.42 |
| normal | 40 | 1.00 | 40 | 0 | 0 | 3.00 | 0.70 |
| hard | 40 | 0.95 | 38 | 2 | 0 | 2.95 | 1.00 |

## Behavior indicators

| Level | Approach ratio | Attacks thrown | Recoveries | Self-KO share of stocks lost | Idle share | Mean match (s) |
|-------|----------------|----------------|------------|------------------------------|------------|----------------|
| easy | 0.20 | 16599 | 53 | 0.06 | 0.08 | 37.7 |
| normal | 0.26 | 18678 | 80 | 0.00 | 0.09 | 42.6 |
| hard | 0.32 | 22243 | 99 | 0.00 | 0.10 | 50.1 |

## Play quality

| Level | KO wins | Timeout wins | KO losses | Timeout losses | Off-stage events | Recovery success | Specials | Mean gap (px) |
|-------|---------|--------------|-----------|----------------|------------------|------------------|----------|---------------|
| easy | 40 | 0 | 0 | 0 | 70 | 0.76 | 7035 | 261 |
| normal | 40 | 0 | 0 | 0 | 108 | 0.74 | 8546 | 251 |
| hard | 38 | 0 | 2 | 0 | 138 | 0.72 | 10162 | 240 |

## Combat depth

| Level | SD matches | Mean SD (s) | Max SD (s) | Pickups / fighter-min | Throws / fighter-min | Blocked share | Shield breaks | Damage: punch | ledge | food | bomb |
|-------|------------|-------------|------------|-----------------------|----------------------|---------------|---------------|---------------|-------|------|------|
| easy | 0 | 0.0 | 0.0 | 6.28 | 5.05 | 0.15 | 18 | 6674 | 0 | 2308 | 0 |
| normal | 0 | 0.0 | 0.0 | 7.23 | 6.39 | 0.26 | 38 | 8399 | 90 | 2652 | 0 |
| hard | 0 | 0.0 | 0.0 | 6.74 | 6.10 | 0.32 | 44 | 10088 | 58 | 3010 | 0 |

## Action distribution vs easy (share of decisions per branch index, entropy in bits)

| Branch | Shares | Entropy |
|--------|--------|---------|
| a0_move | 0.27, 0.43, 0.30 | 1.55 |
| a1_vertical | 0.43, 0.47, 0.11 | 1.38 |
| a2_jump | 0.92, 0.08 | 0.41 |
| a3_attack | 0.36, 0.02, 0.15, 0.11, 0.36 | 1.93 |
| a4_special | 0.69, 0.31 | 0.89 |
| a5_throw | 0.74, 0.26 | 0.82 |
| a6_block | 0.66, 0.34 | 0.93 |
| a7_dash | 0.66, 0.34 | 0.92 |

## Action distribution vs normal (share of decisions per branch index, entropy in bits)

| Branch | Shares | Entropy |
|--------|--------|---------|
| a0_move | 0.27, 0.45, 0.28 | 1.54 |
| a1_vertical | 0.43, 0.47, 0.10 | 1.36 |
| a2_jump | 0.91, 0.09 | 0.45 |
| a3_attack | 0.37, 0.02, 0.17, 0.11, 0.33 | 1.95 |
| a4_special | 0.67, 0.33 | 0.92 |
| a5_throw | 0.70, 0.30 | 0.89 |
| a6_block | 0.65, 0.35 | 0.94 |
| a7_dash | 0.66, 0.34 | 0.92 |

## Action distribution vs hard (share of decisions per branch index, entropy in bits)

| Branch | Shares | Entropy |
|--------|--------|---------|
| a0_move | 0.25, 0.45, 0.30 | 1.54 |
| a1_vertical | 0.47, 0.41, 0.12 | 1.41 |
| a2_jump | 0.91, 0.09 | 0.44 |
| a3_attack | 0.37, 0.02, 0.16, 0.12, 0.34 | 1.96 |
| a4_special | 0.66, 0.34 | 0.92 |
| a5_throw | 0.69, 0.31 | 0.89 |
| a6_block | 0.63, 0.37 | 0.95 |
| a7_dash | 0.65, 0.35 | 0.93 |

Gate: win rate versus CPU Easy at least 0.60 over at least 20 matches: **PASS** (1.00 over 40).

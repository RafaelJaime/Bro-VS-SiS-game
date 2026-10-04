# Evaluation: bvs_default

Played in Godot with the shipped GDScript ONNX interpreter, full matches versus the scripted CPU, sides alternating.

Promoted under Resolved Decision (b) with `kit_win_share` FAIL (see `bvs_default-harness.md` and
`bvs_default-training.md` for the gate detail and the time-box runs); this evaluation's own gate
(KO win rate versus CPU Easy) passes.

| Level | Matches | Win rate | Wins | Losses | Draws | Stocks taken (mean) | Stocks lost (mean) |
|-------|---------|----------|------|--------|-------|---------------------|--------------------|
| easy | 20 | 1.00 | 20 | 0 | 0 | 3.00 | 0.00 |
| normal | 20 | 1.00 | 20 | 0 | 0 | 3.00 | 0.10 |
| hard | 20 | 1.00 | 20 | 0 | 0 | 3.00 | 0.15 |

## Behavior indicators

| Level | Approach ratio | Attacks thrown | Recoveries | Self-KO share of stocks lost | Idle share | Mean match (s) |
|-------|----------------|----------------|------------|------------------------------|------------|----------------|
| easy | 0.29 | 6303 | 2 | 0.00 | 0.00 | 21.9 |
| normal | 0.31 | 6595 | 6 | 0.00 | 0.00 | 23.5 |
| hard | 0.39 | 7507 | 15 | 0.00 | 0.00 | 27.5 |

## Play quality

| Level | KO wins | Timeout wins | KO losses | Timeout losses | Off-stage events | Recovery success | Specials | Mean gap (px) |
|-------|---------|--------------|-----------|----------------|------------------|------------------|----------|---------------|
| easy | 20 | 0 | 0 | 0 | 2 | 1.00 | 3829 | 214 |
| normal | 20 | 0 | 0 | 0 | 8 | 0.75 | 3957 | 220 |
| hard | 20 | 0 | 0 | 0 | 18 | 0.83 | 4582 | 206 |

## Combat depth

| Level | SD matches | Mean SD (s) | Max SD (s) | Pickups / fighter-min | Throws / fighter-min | Blocked share | Shield breaks | Damage: punch | ledge | food | bomb |
|-------|------------|-------------|------------|-----------------------|----------------------|---------------|---------------|---------------|-------|------|------|
| easy | 0 | 0.0 | 0.0 | 5.55 | 4.79 | 0.01 | 0 | 2632 | 0 | 270 | 0 |
| normal | 0 | 0.0 | 0.0 | 6.44 | 6.06 | 0.10 | 0 | 3139 | 100 | 618 | 0 |
| hard | 0 | 0.0 | 0.0 | 7.09 | 6.65 | 0.22 | 1 | 3813 | 60 | 806 | 0 |

## Kits and combos

| Level | Kits | Shield raises / fighter-min | Max combo | 2+ hit combos | Combo histogram (1..6, 7+) | Longest Hurt (s) | Combo damage: Rafael | Matilde |
|-------|------|-----------------------------|-----------|---------------|----------------------------|------------------|----------------------|---------|
| easy | rm | 1.16 | 2 | 4 | 330 / 4 / 0 / 0 / 0 / 0 / 0 | 0.85 | 0.0 | 20.0 |
| normal | rm | 5.10 | 3 | 29 | 391 / 19 / 10 / 0 / 0 / 0 / 0 | 0.85 | 14.5 | 10.5 |
| hard | rm | 8.01 | 4 | 68 | 375 / 37 / 25 / 6 / 0 / 0 / 0 | 1.03 | 11.9 | 11.5 |

### Model results by kit played

| Level | Kit | Matches | Wins | Losses | Draws |
|-------|-----|---------|------|--------|-------|
| easy | matilde | 10 | 10 | 0 | 0 |
| easy | rafael | 10 | 10 | 0 | 0 |
| normal | matilde | 10 | 10 | 0 | 0 |
| normal | rafael | 10 | 10 | 0 | 0 |
| hard | matilde | 10 | 10 | 0 | 0 |
| hard | rafael | 10 | 10 | 0 | 0 |

## Action distribution vs easy (share of decisions per branch index, entropy in bits)

| Branch | Shares | Entropy |
|--------|--------|---------|
| a0_move | 0.24, 0.47, 0.29 | 1.52 |
| a1_vertical | 0.16, 0.79, 0.06 | 0.92 |
| a2_jump | 0.61, 0.39 | 0.97 |
| a3_attack | 0.05, 0.30, 0.00, 0.24, 0.41 | 1.77 |
| a4_special | 0.42, 0.58 | 0.98 |
| a5_throw | 0.44, 0.56 | 0.99 |
| a6_block | 0.50, 0.50 | 1.00 |
| a7_dash | 0.74, 0.26 | 0.83 |

## Action distribution vs normal (share of decisions per branch index, entropy in bits)

| Branch | Shares | Entropy |
|--------|--------|---------|
| a0_move | 0.19, 0.44, 0.36 | 1.51 |
| a1_vertical | 0.14, 0.82, 0.04 | 0.81 |
| a2_jump | 0.59, 0.41 | 0.98 |
| a3_attack | 0.08, 0.24, 0.00, 0.25, 0.43 | 1.85 |
| a4_special | 0.44, 0.56 | 0.99 |
| a5_throw | 0.41, 0.59 | 0.98 |
| a6_block | 0.48, 0.52 | 1.00 |
| a7_dash | 0.72, 0.28 | 0.85 |

## Action distribution vs hard (share of decisions per branch index, entropy in bits)

| Branch | Shares | Entropy |
|--------|--------|---------|
| a0_move | 0.19, 0.45, 0.36 | 1.50 |
| a1_vertical | 0.13, 0.83, 0.04 | 0.78 |
| a2_jump | 0.53, 0.47 | 1.00 |
| a3_attack | 0.10, 0.20, 0.01, 0.25, 0.45 | 1.85 |
| a4_special | 0.44, 0.56 | 0.99 |
| a5_throw | 0.45, 0.55 | 0.99 |
| a6_block | 0.49, 0.51 | 1.00 |
| a7_dash | 0.62, 0.38 | 0.96 |

Gate: win rate versus CPU Easy at least 0.60 over at least 20 matches: **PASS** (1.00 over 20).

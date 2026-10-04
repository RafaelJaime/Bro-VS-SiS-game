# Acceptance harness: bvs_r1

Seed 1, kits `rm`, played in Godot with the shipped GDScript interpreter (172 matches).

## Gates

| Gate | Verdict | Measured | Threshold | Detail |
|------|---------|----------|-----------|--------|
| sudden_death_length | PASS | 2.73 | 45 | mean sudden death 2.7 s (limit 45 s) |
| pickups | FAIL | 0.00 | 1 | lowest 0.00 per fighter-minute in mvm (must exceed 1) |
| blocked_share | PASS | 0.22 | 0.7 | highest 0.22 in m_vs_cpu_hard (limit 0.7) |
| ko_win_rate_easy | PASS | 1.00 | 0.6 | 1.00 KO wins over 24 matches (floor 0.6) |
| shield_raises | PASS | 6.98 | 15.75 | highest 6.98 raises per fighter-minute in m_vs_cpu_hard (limit 15.75) |
| shield_tap_share | PASS | 0.14 | 0.5 | highest 0.14 of shield holds under 15 ticks in m_vs_cpu_easy (limit 0.5) |
| max_combo | PASS | 4.00 | 6 | longest combo 4 hits in regulation/cpu_hard_vs_cpu_hard (limit 6) |
| max_hurt_seconds | FAIL | 1.52 | 1.5 | longest continuous Hurt 1.52 s in regulation/m_vs_cpu_hard (limit 1.5 s) |
| multi_hit_combos | PASS | 129.00 | 5 | fewest 2+ hit combos 129 in mvm (floor 5) |
| kit_win_share | FAIL | 0.05 | 0.4 | Rafael wins 0.05 in mvm (band 0.4-0.6; mvm 0.05, cpu_hard_vs_cpu_hard 0.25) |
| combo_damage_gap | PASS | 0.04 | 0.2 | mean multi-hit combo damage differs by 4.41% between kits (limit 20%) |
| min_matches | PASS | 20.00 | 24 | every matchup has at least the required matches |

## Regulation matches

| Matchup | Matches | KO results | KO win rate | Mean match (s) | Mean SD (s) | Max SD (s) | Pickups / fighter-min | Throws / fighter-min | Blocked share | Shield breaks | Damage punch | food | bomb |
|---------|---------|------------|-------------|----------------|-------------|------------|-----------------------|----------------------|---------------|---------------|--------------|------|------|
| mvm | 40 | 40 | 0.45 | 41.6 | 0.0 | 0.0 | 0.00 | 0.00 | 0.00 | 0 | 16281 | 0 | 0 |
| cpu_hard_vs_cpu_hard | 40 | 40 | 0.60 | 67.3 | 0.0 | 0.0 | 9.48 | 9.14 | 0.31 | 6 | 10827 | 6769 | 0 |
| m_vs_cpu_easy | 24 | 24 | 1.00 | 21.2 | 0.0 | 0.0 | 4.13 | 3.07 | 0.02 | 0 | 3487 | 576 | 0 |
| m_vs_cpu_hard | 24 | 24 | 1.00 | 29.7 | 0.0 | 0.0 | 3.53 | 3.11 | 0.22 | 0 | 4858 | 837 | 0 |
| cpu_normal_vs_cpu_normal | 24 | 24 | 0.42 | 74.0 | 0.0 | 0.0 | 10.19 | 9.86 | 0.16 | 1 | 6216 | 5573 | 0 |

## Forced sudden death

| Matchup | Matches | KO results | KO win rate | Mean match (s) | Mean SD (s) | Max SD (s) | Pickups / fighter-min | Throws / fighter-min | Blocked share | Shield breaks | Damage punch | food | bomb |
|---------|---------|------------|-------------|----------------|-------------|------------|-----------------------|----------------------|---------------|---------------|--------------|------|------|
| mvm | 20 | 20 | 0.50 | 2.8 | 2.7 | 2.7 | 0.00 | 0.00 | 0.00 | 0 | 180 | 0 | 0 |

## Combos, shields and kits: regulation

| Matchup | Shield raises / fighter-min | Shield tap share | Max combo | 2+ hit combos | Combo histogram (1..6, 7+) | Longest Hurt (s) | Hurt runs over 90 ticks | Rafael win share | Fighter1 win share | Combo damage Rafael | Matilde |
|---------|-----------------------------|------------------|-----------|---------------|----------------------------|------------------|--------------------------|------------------|--------------------|---------------------|---------|
| mvm | 0.00 | 0.00 | 3 | 129 | 1328 / 127 / 2 / 0 / 0 / 0 / 0 | 1.33 | 0 | 0.05 | 0.50 | 0.0 | 18.1 |
| cpu_hard_vs_cpu_hard | 10.53 | 0.24 | 4 | 440 | 1933 / 216 / 213 / 11 / 0 / 0 / 0 | 1.42 | 0 | 0.25 | 0.65 | 11.1 | 9.9 |
| m_vs_cpu_easy | 1.30 | 0.14 | 2 | 17 | 407 / 17 / 0 / 0 / 0 / 0 / 0 | 0.87 | 0 | 0.50 | 0.50 | 0.0 | 18.0 |
| m_vs_cpu_hard | 6.98 | 0.10 | 4 | 88 | 446 / 56 / 30 / 2 / 0 / 0 / 0 | 1.52 | 1 | 0.50 | 0.50 | 11.8 | 11.6 |
| cpu_normal_vs_cpu_normal | 8.95 | 0.38 | 4 | 153 | 1807 / 128 / 23 / 2 / 0 / 0 / 0 | 1.13 | 0 | 0.50 | 0.58 | 16.0 | 6.9 |

## Combos, shields and kits: forced sudden death

| Matchup | Shield raises / fighter-min | Shield tap share | Max combo | 2+ hit combos | Combo histogram (1..6, 7+) | Longest Hurt (s) | Hurt runs over 90 ticks | Rafael win share | Fighter1 win share | Combo damage Rafael | Matilde |
|---------|-----------------------------|------------------|-----------|---------------|----------------------------|------------------|--------------------------|------------------|--------------------|---------------------|---------|
| mvm | 0.00 | 0.00 | 1 | 0 | 20 / 0 / 0 / 0 / 0 / 0 / 0 | 0.32 | 0 | 0.00 | 0.50 | 0.0 | 0.0 |

Overall: **FAIL**

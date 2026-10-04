# Acceptance harness: bvs_r2

Seed 1, kits `rm`, played in Godot with the shipped GDScript interpreter (172 matches).

## Gates

| Gate | Verdict | Measured | Threshold | Detail |
|------|---------|----------|-----------|--------|
| sudden_death_length | PASS | 2.73 | 45 | mean sudden death 2.7 s (limit 45 s) |
| pickups | FAIL | 0.00 | 1 | lowest 0.00 per fighter-minute in mvm (must exceed 1) |
| blocked_share | PASS | 0.22 | 0.7 | highest 0.22 in m_vs_cpu_hard (limit 0.7) |
| ko_win_rate_easy | PASS | 1.00 | 0.6 | 1.00 KO wins over 24 matches (floor 0.6) |
| shield_raises | PASS | 7.39 | 14.66 | highest 7.39 raises per fighter-minute in m_vs_cpu_hard (limit 14.66) |
| shield_tap_share | PASS | 0.23 | 0.5 | highest 0.23 of shield holds under 15 ticks in m_vs_cpu_easy (limit 0.5) |
| max_combo | PASS | 5.00 | 6 | longest combo 5 hits in regulation/cpu_hard_vs_cpu_hard (limit 6) |
| max_hurt_seconds | PASS | 1.37 | 1.5 | longest continuous Hurt 1.37 s in regulation/m_vs_cpu_hard (limit 1.5 s) |
| multi_hit_combos | PASS | 156.00 | 5 | fewest 2+ hit combos 156 in mvm (floor 5) |
| kit_win_share | FAIL | 0.10 | 0.4 | Rafael wins 0.10 in mvm (band 0.4-0.6; mvm 0.10, cpu_hard_vs_cpu_hard 0.42) |
| combo_damage_gap | PASS | 0.01 | 0.2 | mean multi-hit combo damage differs by 0.88% between kits (limit 20%) |
| min_matches | PASS | 20.00 | 24 | every matchup has at least the required matches |

## Regulation matches

| Matchup | Matches | KO results | KO win rate | Mean match (s) | Mean SD (s) | Max SD (s) | Pickups / fighter-min | Throws / fighter-min | Blocked share | Shield breaks | Damage punch | food | bomb |
|---------|---------|------------|-------------|----------------|-------------|------------|-----------------------|----------------------|---------------|---------------|--------------|------|------|
| mvm | 40 | 40 | 0.50 | 48.6 | 0.0 | 0.0 | 0.00 | 0.00 | 0.00 | 0 | 20125 | 0 | 0 |
| cpu_hard_vs_cpu_hard | 40 | 40 | 0.53 | 65.6 | 0.0 | 0.0 | 9.89 | 9.57 | 0.30 | 14 | 11208 | 6848 | 0 |
| m_vs_cpu_easy | 24 | 24 | 1.00 | 22.1 | 0.0 | 0.0 | 4.46 | 3.05 | 0.02 | 0 | 3701 | 558 | 0 |
| m_vs_cpu_hard | 24 | 24 | 1.00 | 27.9 | 0.0 | 0.0 | 3.54 | 3.00 | 0.22 | 0 | 4848 | 714 | 0 |
| cpu_normal_vs_cpu_normal | 24 | 24 | 0.46 | 76.5 | 0.0 | 0.0 | 10.24 | 9.91 | 0.13 | 0 | 6817 | 5489 | 0 |

## Forced sudden death

| Matchup | Matches | KO results | KO win rate | Mean match (s) | Mean SD (s) | Max SD (s) | Pickups / fighter-min | Throws / fighter-min | Blocked share | Shield breaks | Damage punch | food | bomb |
|---------|---------|------------|-------------|----------------|-------------|------------|-----------------------|----------------------|---------------|---------------|--------------|------|------|
| mvm | 20 | 20 | 0.50 | 2.8 | 2.7 | 2.8 | 0.00 | 0.00 | 0.00 | 0 | 180 | 0 | 0 |

## Combos, shields and kits: regulation

| Matchup | Shield raises / fighter-min | Shield tap share | Max combo | 2+ hit combos | Combo histogram (1..6, 7+) | Longest Hurt (s) | Hurt runs over 90 ticks | Rafael win share | Fighter1 win share | Combo damage Rafael | Matilde |
|---------|-----------------------------|------------------|-----------|---------------|----------------------------|------------------|--------------------------|------------------|--------------------|---------------------|---------|
| mvm | 0.00 | 0.00 | 3 | 156 | 1637 / 152 / 4 / 0 / 0 / 0 / 0 | 1.33 | 0 | 0.10 | 0.55 | 23.0 | 18.2 |
| cpu_hard_vs_cpu_hard | 9.78 | 0.23 | 5 | 557 | 1725 / 338 / 205 / 11 / 3 / 0 / 0 | 1.35 | 0 | 0.42 | 0.82 | 11.1 | 9.8 |
| m_vs_cpu_easy | 1.47 | 0.23 | 2 | 7 | 467 / 7 / 0 / 0 / 0 / 0 / 0 | 0.83 | 0 | 0.50 | 0.50 | 0.0 | 18.0 |
| m_vs_cpu_hard | 7.39 | 0.15 | 4 | 94 | 432 / 61 / 29 / 4 / 0 / 0 / 0 | 1.37 | 0 | 0.50 | 0.50 | 11.4 | 11.0 |
| cpu_normal_vs_cpu_normal | 8.43 | 0.43 | 4 | 202 | 1892 / 154 / 43 / 5 / 0 / 0 / 0 | 1.37 | 0 | 0.46 | 0.71 | 11.4 | 7.6 |

## Combos, shields and kits: forced sudden death

| Matchup | Shield raises / fighter-min | Shield tap share | Max combo | 2+ hit combos | Combo histogram (1..6, 7+) | Longest Hurt (s) | Hurt runs over 90 ticks | Rafael win share | Fighter1 win share | Combo damage Rafael | Matilde |
|---------|-----------------------------|------------------|-----------|---------------|----------------------------|------------------|--------------------------|------------------|--------------------|---------------------|---------|
| mvm | 0.00 | 0.00 | 1 | 0 | 20 / 0 / 0 / 0 / 0 / 0 / 0 | 0.37 | 0 | 0.00 | 0.50 | 0.0 | 0.0 |

Overall: **FAIL**

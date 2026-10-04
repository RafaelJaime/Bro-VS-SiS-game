# Acceptance harness: bvs_r3

Seed 1, kits `rm`, played in Godot with the shipped GDScript interpreter (172 matches).

## Gates

| Gate | Verdict | Measured | Threshold | Detail |
|------|---------|----------|-----------|--------|
| sudden_death_length | PASS | 2.62 | 45 | mean sudden death 2.6 s (limit 45 s) |
| pickups | PASS | 8.14 | 1 | lowest 8.14 per fighter-minute in m_vs_cpu_easy (must exceed 1) |
| blocked_share | PASS | 0.24 | 0.7 | highest 0.24 in m_vs_cpu_hard (limit 0.7) |
| ko_win_rate_easy | PASS | 1.00 | 0.6 | 1.00 KO wins over 24 matches (floor 0.6) |
| shield_raises | PASS | 6.90 | 14.66 | highest 6.90 raises per fighter-minute in m_vs_cpu_hard (limit 14.66) |
| shield_tap_share | FAIL | 1.00 | 0.5 | highest 1.00 of shield holds under 15 ticks in mvm (limit 0.5) |
| max_combo | PASS | 5.00 | 6 | longest combo 5 hits in regulation/cpu_hard_vs_cpu_hard (limit 6) |
| max_hurt_seconds | PASS | 1.35 | 1.5 | longest continuous Hurt 1.35 s in regulation/cpu_normal_vs_cpu_normal (limit 1.5 s) |
| multi_hit_combos | PASS | 35.00 | 5 | fewest 2+ hit combos 35 in mvm (floor 5) |
| kit_win_share | FAIL | 0.78 | 0.4 | Rafael wins 0.78 in mvm (band 0.4-0.6; mvm 0.78, cpu_hard_vs_cpu_hard 0.47) |
| combo_damage_gap | PASS | 0.15 | 0.2 | mean multi-hit combo damage differs by 14.82% between kits (limit 20%) |
| min_matches | PASS | 20.00 | 24 | every matchup has at least the required matches |

## Regulation matches

| Matchup | Matches | KO results | KO win rate | Mean match (s) | Mean SD (s) | Max SD (s) | Pickups / fighter-min | Throws / fighter-min | Blocked share | Shield breaks | Damage punch | food | bomb |
|---------|---------|------------|-------------|----------------|-------------|------------|-----------------------|----------------------|---------------|---------------|--------------|------|------|
| mvm | 40 | 40 | 0.53 | 50.7 | 0.0 | 0.0 | 10.14 | 9.62 | 0.00 | 0 | 16080 | 3772 | 0 |
| cpu_hard_vs_cpu_hard | 40 | 40 | 0.47 | 60.5 | 3.9 | 3.9 | 9.65 | 9.37 | 0.31 | 7 | 9737 | 6353 | 0 |
| m_vs_cpu_easy | 24 | 24 | 1.00 | 27.8 | 0.0 | 0.0 | 8.14 | 7.37 | 0.03 | 0 | 3226 | 1155 | 0 |
| m_vs_cpu_hard | 24 | 24 | 0.96 | 38.6 | 0.0 | 0.0 | 9.43 | 9.00 | 0.24 | 3 | 5362 | 2060 | 0 |
| cpu_normal_vs_cpu_normal | 24 | 24 | 0.50 | 72.5 | 3.6 | 3.6 | 10.09 | 9.73 | 0.14 | 0 | 6379 | 4964 | 0 |

## Forced sudden death

| Matchup | Matches | KO results | KO win rate | Mean match (s) | Mean SD (s) | Max SD (s) | Pickups / fighter-min | Throws / fighter-min | Blocked share | Shield breaks | Damage punch | food | bomb |
|---------|---------|------------|-------------|----------------|-------------|------------|-----------------------|----------------------|---------------|---------------|--------------|------|------|
| mvm | 20 | 20 | 0.50 | 2.7 | 2.6 | 2.9 | 0.00 | 0.00 | 0.00 | 0 | 234 | 0 | 0 |

## Combos, shields and kits: regulation

| Matchup | Shield raises / fighter-min | Shield tap share | Max combo | 2+ hit combos | Combo histogram (1..6, 7+) | Longest Hurt (s) | Hurt runs over 90 ticks | Rafael win share | Fighter1 win share | Combo damage Rafael | Matilde |
|---------|-----------------------------|------------------|-----------|---------------|----------------------------|------------------|--------------------------|------------------|--------------------|---------------------|---------|
| mvm | 0.04 | 1.00 | 3 | 35 | 1764 / 34 / 1 / 0 / 0 / 0 / 0 | 1.23 | 0 | 0.78 | 0.57 | 24.1 | 21.6 |
| cpu_hard_vs_cpu_hard | 9.78 | 0.22 | 5 | 485 | 1548 / 249 / 225 / 10 / 1 / 0 / 0 | 1.28 | 0 | 0.47 | 0.93 | 10.8 | 10.2 |
| m_vs_cpu_easy | 1.12 | 0.20 | 2 | 4 | 459 / 4 / 0 / 0 / 0 / 0 / 0 | 0.78 | 0 | 0.50 | 0.50 | 0.0 | 23.5 |
| m_vs_cpu_hard | 6.90 | 0.14 | 4 | 82 | 621 / 53 / 28 / 1 / 0 / 0 / 0 | 1.00 | 0 | 0.54 | 0.54 | 11.4 | 9.8 |
| cpu_normal_vs_cpu_normal | 8.62 | 0.36 | 4 | 164 | 1793 / 117 / 40 / 7 / 0 / 0 / 0 | 1.35 | 0 | 0.75 | 0.58 | 15.6 | 7.9 |

## Combos, shields and kits: forced sudden death

| Matchup | Shield raises / fighter-min | Shield tap share | Max combo | 2+ hit combos | Combo histogram (1..6, 7+) | Longest Hurt (s) | Hurt runs over 90 ticks | Rafael win share | Fighter1 win share | Combo damage Rafael | Matilde |
|---------|-----------------------------|------------------|-----------|---------------|----------------------------|------------------|--------------------------|------------------|--------------------|---------------------|---------|
| mvm | 0.00 | 0.00 | 1 | 0 | 20 / 0 / 0 / 0 / 0 / 0 / 0 | 0.32 | 0 | 0.90 | 0.60 | 0.0 | 0.0 |

Overall: **FAIL**

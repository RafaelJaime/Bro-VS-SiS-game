# Acceptance harness: bvs_r4

Seed 1, kits `rm`, played in Godot with the shipped GDScript interpreter (172 matches).

## Gates

| Gate | Verdict | Measured | Threshold | Detail |
|------|---------|----------|-----------|--------|
| sudden_death_length | PASS | 2.54 | 45 | mean sudden death 2.5 s (limit 45 s) |
| pickups | PASS | 6.64 | 1 | lowest 6.64 per fighter-minute in m_vs_cpu_easy (must exceed 1) |
| blocked_share | PASS | 0.23 | 0.7 | highest 0.23 in m_vs_cpu_hard (limit 0.7) |
| ko_win_rate_easy | PASS | 1.00 | 0.6 | 1.00 KO wins over 24 matches (floor 0.6) |
| shield_raises | PASS | 8.06 | 14.66 | highest 8.06 raises per fighter-minute in m_vs_cpu_hard (limit 14.66) |
| shield_tap_share | PASS | 0.26 | 0.5 | highest 0.26 of shield holds under 15 ticks in m_vs_cpu_easy (limit 0.5) |
| max_combo | PASS | 5.00 | 6 | longest combo 5 hits in regulation/cpu_hard_vs_cpu_hard (limit 6) |
| max_hurt_seconds | PASS | 1.35 | 1.5 | longest continuous Hurt 1.35 s in regulation/cpu_normal_vs_cpu_normal (limit 1.5 s) |
| multi_hit_combos | PASS | 59.00 | 5 | fewest 2+ hit combos 59 in mvm (floor 5) |
| kit_win_share | FAIL | 0.88 | 0.4 | Rafael wins 0.88 in mvm (band 0.4-0.6; mvm 0.88, cpu_hard_vs_cpu_hard 0.47) |
| combo_damage_gap | PASS | 0.09 | 0.2 | mean multi-hit combo damage differs by 9.43% between kits (limit 20%) |
| min_matches | PASS | 20.00 | 24 | every matchup has at least the required matches |

## Regulation matches

| Matchup | Matches | KO results | KO win rate | Mean match (s) | Mean SD (s) | Max SD (s) | Pickups / fighter-min | Throws / fighter-min | Blocked share | Shield breaks | Damage punch | food | bomb |
|---------|---------|------------|-------------|----------------|-------------|------------|-----------------------|----------------------|---------------|---------------|--------------|------|------|
| mvm | 40 | 40 | 0.38 | 47.4 | 0.0 | 0.0 | 9.25 | 8.13 | 0.00 | 0 | 17741 | 1372 | 0 |
| cpu_hard_vs_cpu_hard | 40 | 40 | 0.47 | 60.5 | 3.9 | 3.9 | 9.65 | 9.37 | 0.31 | 7 | 9737 | 6353 | 0 |
| m_vs_cpu_easy | 24 | 24 | 1.00 | 21.8 | 0.0 | 0.0 | 6.64 | 5.84 | 0.02 | 0 | 3190 | 644 | 0 |
| m_vs_cpu_hard | 24 | 24 | 1.00 | 28.7 | 0.0 | 0.0 | 7.14 | 6.71 | 0.23 | 1 | 4753 | 921 | 0 |
| cpu_normal_vs_cpu_normal | 24 | 24 | 0.50 | 72.5 | 3.6 | 3.6 | 10.09 | 9.73 | 0.14 | 0 | 6379 | 4964 | 0 |

## Forced sudden death

| Matchup | Matches | KO results | KO win rate | Mean match (s) | Mean SD (s) | Max SD (s) | Pickups / fighter-min | Throws / fighter-min | Blocked share | Shield breaks | Damage punch | food | bomb |
|---------|---------|------------|-------------|----------------|-------------|------------|-----------------------|----------------------|---------------|---------------|--------------|------|------|
| mvm | 20 | 20 | 0.50 | 2.6 | 2.5 | 2.5 | 0.00 | 0.00 | 0.00 | 0 | 210 | 0 | 0 |

## Combos, shields and kits: regulation

| Matchup | Shield raises / fighter-min | Shield tap share | Max combo | 2+ hit combos | Combo histogram (1..6, 7+) | Longest Hurt (s) | Hurt runs over 90 ticks | Rafael win share | Fighter1 win share | Combo damage Rafael | Matilde |
|---------|-----------------------------|------------------|-----------|---------------|----------------------------|------------------|--------------------------|------------------|--------------------|---------------------|---------|
| mvm | 0.00 | 0.00 | 4 | 59 | 1681 / 58 / 0 / 1 / 0 / 0 / 0 | 1.00 | 0 | 0.88 | 0.53 | 24.2 | 19.8 |
| cpu_hard_vs_cpu_hard | 9.78 | 0.22 | 5 | 485 | 1548 / 249 / 225 / 10 / 1 / 0 / 0 | 1.28 | 0 | 0.47 | 0.93 | 10.8 | 10.2 |
| m_vs_cpu_easy | 1.09 | 0.26 | 3 | 11 | 407 / 10 / 1 / 0 / 0 / 0 / 0 | 0.87 | 0 | 0.50 | 0.50 | 25.0 | 21.6 |
| m_vs_cpu_hard | 8.06 | 0.10 | 4 | 83 | 468 / 43 / 30 / 10 / 0 / 0 / 0 | 1.03 | 0 | 0.50 | 0.50 | 12.1 | 12.1 |
| cpu_normal_vs_cpu_normal | 8.62 | 0.36 | 4 | 164 | 1793 / 117 / 40 / 7 / 0 / 0 / 0 | 1.35 | 0 | 0.75 | 0.58 | 15.6 | 7.9 |

## Combos, shields and kits: forced sudden death

| Matchup | Shield raises / fighter-min | Shield tap share | Max combo | 2+ hit combos | Combo histogram (1..6, 7+) | Longest Hurt (s) | Hurt runs over 90 ticks | Rafael win share | Fighter1 win share | Combo damage Rafael | Matilde |
|---------|-----------------------------|------------------|-----------|---------------|----------------------------|------------------|--------------------------|------------------|--------------------|---------------------|---------|
| mvm | 0.00 | 0.00 | 1 | 0 | 20 / 0 / 0 / 0 / 0 / 0 / 0 | 0.30 | 0 | 0.50 | 1.00 | 0.0 | 0.0 |

Overall: **FAIL**

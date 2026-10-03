# Combat-depth harness: bvs_default

Seed 1, 20 matches per matchup, played in Godot with the shipped GDScript interpreter.

## Gates

| Gate | Verdict | Measured | Threshold | Detail |
|------|---------|----------|-----------|--------|
| sudden_death_length | PASS | 6.65 | 45 | mean sudden death 6.7 s (limit 45 s) |
| pickups | PASS | 1.73 | 1 | lowest 1.73 per fighter-minute in mvm (must exceed 1) |
| blocked_share | PASS | 0.57 | 0.7 | highest 0.57 in mvm (limit 0.7) |
| ko_win_rate_easy | PASS | 1.00 | 0.6 | 1.00 KO wins over 20 matches (floor 0.6) |
| min_matches | PASS | 20.00 | 20 | every matchup has at least the required matches |

## Regulation matches

| Matchup | Matches | KO results | KO win rate | Mean match (s) | Mean SD (s) | Max SD (s) | Pickups / fighter-min | Throws / fighter-min | Blocked share | Shield breaks | Damage punch | food | bomb |
|---------|---------|------------|-------------|----------------|-------------|------------|-----------------------|----------------------|---------------|---------------|--------------|------|------|
| cpu_hard_vs_cpu_hard | 20 | 20 | 0.60 | 66.2 | 0.0 | 0.0 | 9.90 | 9.47 | 0.31 | 2 | 5434 | 3342 | 0 |
| m_vs_cpu_easy | 20 | 20 | 1.00 | 36.5 | 0.0 | 0.0 | 5.63 | 4.32 | 0.15 | 17 | 3404 | 718 | 0 |
| m_vs_cpu_normal | 20 | 20 | 1.00 | 39.0 | 0.0 | 0.0 | 6.39 | 5.89 | 0.27 | 13 | 3998 | 1146 | 0 |
| mvm | 20 | 16 | 0.40 | 97.0 | 5.4 | 12.5 | 1.73 | 1.14 | 0.57 | 248 | 8598 | 713 | 0 |

## Forced sudden death

| Matchup | Matches | KO results | KO win rate | Mean match (s) | Mean SD (s) | Max SD (s) | Pickups / fighter-min | Throws / fighter-min | Blocked share | Shield breaks | Damage punch | food | bomb |
|---------|---------|------------|-------------|----------------|-------------|------------|-----------------------|----------------------|---------------|---------------|--------------|------|------|
| cpu_hard_vs_cpu_hard | 20 | 20 | 0.50 | 3.3 | 3.3 | 3.6 | 0.00 | 0.00 | 0.43 | 0 | 190 | 0 | 0 |
| mvm | 20 | 20 | 0.55 | 6.7 | 6.7 | 11.1 | 3.80 | 3.58 | 0.09 | 0 | 162 | 188 | 0 |

Overall: **PASS**

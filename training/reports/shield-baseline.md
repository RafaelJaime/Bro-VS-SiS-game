# Shield-raise baseline (design D15)

Measured with the final gameplay and kits at seed 1, `BVS_HARNESS_KITS=rm`, before any retrain. Raises are `Fighter.shield_raises` deltas per fighter-minute of game time (MatchMetrics).

| Quantity | Value | Source |
|----------|-------|--------|
| R_cpu | 9.77 | `cpu_hard_vs_cpu_hard`, 40 matches (860 raises) |
| R_old (mvm) | 0.01 | bundled model (schema 3), 24 matches |
| R_old (m_vs_cpu_hard) | 5.83 | bundled model (schema 3), 24 matches |
| R_old | 5.83 | maximum of the model matchups |
| **T** | **14.66** | 0.5 * R_old is below R_cpu (the old model does not spam on the new rules): T = max(1.5 * R_cpu, R_cpu + 2.0) |

The gate `max_shield_raises_per_fighter_minute` in `training/configs/default.toml` is set to 14.66. It applies to the retrained model in `mvm` and `m_vs_cpu_hard`. It is not changed afterwards except by a re-measurement that a report explains (for example after a kit-data change: `uv run python -m bvs_training.harness --baseline`).

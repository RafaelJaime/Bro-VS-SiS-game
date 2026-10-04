# Training notes: bvs_default (schema 4, character kits and combos)

Machine: Apple M5 (10 cores, 24 GB), Godot 4.7.2 headless, godot-rl 0.8.2, stable-baselines3 2.3.2,
torch 2.14.1 (CPU). Seed 1, kits `rm` (random per side and episode, both kits on both sides).
Promoted candidate trained on commit `f7129e7` (`bvs-schema-4`).

## Resolved Decision (b)

The S6 time box (design D18: 4 full runs or 4 h of cumulative training wall time, whichever comes
first) was exhausted at R4 with one acceptance gate still failing: `kit_win_share` 0.88 in
model-vs-model (band 0.4-0.6; the CPU Hard mirror of the same kit data stayed in band at 0.47 from
R2 onward). Per the Resolved Decision, the user chose **(b)**: promote the best candidate (R4) with
the failed gate reported, rather than iterate further within the time box or (c) merge the
gameplay slices (S1-S4) on schema 3 and move the retrain to a follow-up. Every other gate passes;
see `bvs_default-harness.md` for the full gate table and `openspec/changes/character-kits-combos/tasks.md`
(6.1-6.4) for the run-by-run record.

## Runs

| Run | Lever(s) | Agent steps | Wall time | Gate result |
|-----|----------|--------------|-----------|--------------|
| R0 sanity | none (P1-P3 at 100k steps each, `--n-parallel 4`) | 0.3M | 22m42s (excluded from the box) | not gated: `BVS_EPISODE` carries `combo_hit`/`shield_raise`, both kit pairs observed, no `SCRIPT ERROR` |
| R1 | none (S5 code and data as committed) | 10.04M | 52m06s | FAIL: `pickups` 0.00 (mvm); `max_hurt_seconds` 1.52 (m_vs_cpu_hard); `kit_win_share` 0.05 (mvm; cpu_hard mirror 0.25) |
| R2 | kit data (commit `5fbcb84`) | 10.04M | 1h31m31s | FAIL: `pickups` 0.00; `kit_win_share` 0.10 (cpu_hard mirror 0.42, closer to band). `max_hurt_seconds` now PASSES (1.37) |
| R3 | kit data (`d6f20dc`) + reward `pickup` 0.12→0.35 / `pickup_cap` 20→8 (two lever groups in one run, a deviation from "one lever group per run" already committed before this apply session) | 10.04M | 26m13s | FAIL: `shield_tap_share` 1.00 (mvm; only ~3 shield-raise events in 40 mvm matches, small-sample); `kit_win_share` 0.78 (cpu_hard mirror 0.47, in band). `pickups` and `max_hurt_seconds` now PASS |
| R4 (promoted) | reward `shield_raise` −0.002 → −0.01 (5x; the only one of the three offered shield knobs that fires independently of hold duration) | 10.04M | 27m28s | FAIL only: `kit_win_share` 0.88 (cpu_hard mirror still in band at 0.47). `shield_tap_share` now PASSES (0.26). Every other gate PASSES |

Cumulative R1-R4 wall time: 3h17m18s, under the 4 h cap; the 4-full-run cap is reached by R4
regardless, so R4 is correctly the last run under either box condition.

## `kit_win_share` risk (read honestly, not resolved by R4)

Rafael's win share in mvm moved 0.05 → 0.10 → 0.78 → 0.88 across R1-R4, while the CPU Hard mirror
(same kit data, different opponent logic) stayed in band from R2 onward (0.25 → 0.42 → 0.47 →
0.47). Kit data was not touched again after R2/R3 (`d6f20dc`), yet mvm's share kept moving in R4
with only a reward-weight change; this is read as self-play policy variance (the single trained
policy, playing both kits against itself, develops an emergent asymmetric edge each retrain) rather
than a stable kit-data imbalance signal. No further kit-data tuning was attempted on this basis, per
the Resolved Decision's literal time box. A follow-up retrain could target this gate specifically
(for example more self-play steps, an explicit kit-win-share curriculum term, or re-running D15's
baseline after a kit-data change), but that is out of scope for this change.

## Gates (promoted candidate, R4)

- Parity: 64 golden cases (32 random, 32 recorded), validates against `bvs-schema-4` (149 inputs,
  21 logits); see `tests/fixtures/onnx/bvs_default_golden.json`.
- Evaluation (`bvs_default-eval.md`, 20 matches per level): Easy 20 W, Normal 20 W, Hard 20 W, all
  KO wins, self-KO share 0.00, idle share 0.00.
- Harness (`bvs_default-harness.md`, seed 1, kits `rm`, 172 matches): 11 of 12 gates PASS; the one
  FAIL is `kit_win_share` (0.88 in mvm, band 0.4-0.6), promoted under Resolved Decision (b).

## Notes

- `shield_raise` was the only one of the three offered reward knobs (`shield_raise`, `shield_hold`,
  `shield_hold_threshold`) that can discriminate a short shield tap from a non-event: `shield_hold`
  only applies past a 1.5 s / 90-tick threshold, far above the 15-tick / 0.25 s tap cutoff, and
  lowering `shield_hold_threshold` would also have punished legitimate longer holds in matchups
  that were already passing (for example `cpu_hard_vs_cpu_hard`'s 0.22 tap share). The R4 outcome
  matches that rationale: `shield_tap_share` now passes, with mvm's own raises dropping to 0.00.
- The mvm regulation matches run shorter than the old schema-3 model's (mean 47.4 s here versus
  97.0 s before): shield raises collapsed in mvm specifically (0.00 per fighter-minute, versus 9.78
  in the `cpu_hard_vs_cpu_hard` mirror), so fewer shield breaks interrupt the match.
- Wall times are `training/out/r{N}.log` birth→mtime (`stat -f %SB/%Sm`), not report timestamps.

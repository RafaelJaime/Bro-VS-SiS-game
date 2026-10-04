# Proposal: Character Kits and Combos (jab chains, frame data, combo safeguards, schema 4)

Mirror of Engram `sdd/character-kits-combos/proposal`. Builds on `explore.md` (Engram `sdd/character-kits-combos/explore`). Branch `fix/shield-spam`, which already carries the shield drop lag, minimum hold and raise cost, the air-punch momentum fix, the player-colored shield, the two-step Hugging Face picker and the loser face portrait (`odd/tasks/shield-spam.md` T1-T3). Task T4 of that document (shield-raise gate and retrain) is deferred into this change.

## Intent

Rafael and Matilde play the same, and no real combo exists.

- **No kits.** `game/player/fighter_profile.gd` is the kit seam, but no scene assigns a profile (`player.gd:146-147` uses `FighterProfile.new()`). The two characters differ only in `CharacterUI` (name, color, sprites).
- **No combos at any percent.** Measured headless at 60 fps, neutral punch at 0%: the hit lands on f6, victim hitstun ends on f25, but the attacker can only punch again on f43 (0.7 s cooldown from press) and the victim is invulnerable until f56. Spamming yields 3 hits in 240 ticks.
- **No per-attack frame data.** Hitstun is a single global formula (`hurt.gd:34-71`), every attack shares one cooldown and duration, and there is no attack input buffer. Punch and Hurt still use idle `Timer` nodes, while newer timers are tick-based (`CombatClock`), so link windows of a few frames would drift with hit-stop.
- **Combos without safeguards are infinite.** The prototype showed that cooldown ≤ hitstun gives 7 hits in 4 s at 0%, and with zero knockback an infinite stun-lock (15 hits in 4 s). Safeguards must ship together with combos.
- **The default model has no signal for any of this.** Schema 3 has no kit id, no hitstun left and no chain state. The bundled schema-3 model was also trained before the shield drop lag and raise cost, so it needs a retrain anyway.

Goal (user, Smash-style, Direction B): combos that come from mechanics (frame data, hitstun, knockback, jab chains), make the two characters play differently with one frame per animation, stay fair (no infinites), and are learned by a single retrained default model that also covers the shield fixes.

## Scope

### In Scope

**S1: Tick timers and attack buffer**
1. Punch and Hurt timers (duration, endlag, hitstun, post-hitstun invulnerability) move from `Timer` nodes to `CombatClock` ticks, independent of `Engine.time_scale`.
2. Attack input buffer (a few ticks, tunable) so a press during endlag or hit-stop fires on the first actionable tick. Each chain step needs its own press; holding never auto-chains.

**S2: Per-attack frame data and jab chains**
3. `AttackProfile` gains frame data: active frames, endlag, hitstun (or hitstun base and growth), link window, hit-stop scale. The global hitstun formula becomes the per-attack default.
4. Neutral jab chains: a press inside the link window advances to the next chain step. The finisher always launches. Lighter hit-stop for jab steps.

**S3: Combo tracking, safeguards and HUD counter**
5. Victim-side combo tracking (tick-based): the combo continues while hits land during hitstun and resets when hitstun expires without a new hit.
6. Anti-infinite safeguards: chain cap (finisher launches), hitstun decay from hit 4, hard cap at hit 6 (the 6th hit launches and the victim becomes invulnerable), knockback ×1.1 per combo hit, 1.5 s combo time cap, and the existing 0.5 s post-hitstun invulnerability kept.
7. "N HIT COMBO" counter on the attacker's HUD card: small, shows combo damage, fades after about 1 s, only for combos of 2+ hits. Existing assets and VFX only (`T_VFX_Glow_1`, `T_LeLuStar11` reusable).

**S4: Kits per character and CPU combos**
8. Two `FighterProfile` resources assigned by character (Rafael, Matilde), using the explore's initial table as tunable data:
   - Rafael (heavy, slow): run 270, victim knockback scale 0.9, jump/double -820/-720, 2-hit jab (4, finisher 8 launches), neutral single 10, heavy up launcher (9 dmg, endlag 0.55), strong side (13, kb 360,-90), down-air spike (11, kb 40,460), single air jab, tighter link slack.
   - Matilde (light, fast): run 340, victim knockback scale 1.1, jump/double -900/-780, 3-hit jab (2.5, 2.5, finisher 4), neutral single 6, combo up launcher (6 dmg, hitstun 0.55, endlag 0.30) into air follow-ups, side (8, kb 260,-90), down-air spike (7, kb 30,380), 2-hit air jab, longer recovery.
   - The Matilde up-launcher into air follow-up is prototyped first in S4 (riskiest piece) before the rest of the kit is tuned.
9. CPU: Easy uses single jabs only; Normal uses jab chains; Hard uses jab chains plus launcher follow-ups. Easy keeps its existing restrictions. The CPU uses the attack buffer to chain despite 0.12-0.40 s decision intervals.

**S5: Schema 4, training, metrics and harness**
10. `bvs-schema-4` = schema 3 plus kit and combo features (about 149 floats): self and opponent kit one-hot (4 + 4 slots, room for future kits), own chain step, link window open, opponent hitstun left, combo count dealt, hits taken in the current combo. The action layout `[3,3,2,5,2,2,2,2]` is unchanged. Schema 3 stays frozen and registered; `BVS_SCHEMA_VERSION` becomes 4; v4 golden fixtures are generated and v3 fixtures are kept.
11. Snapshot keys for the new features (chain step, link open, hitstun left, combo counts, kit id).
12. Training: kits randomized per side per episode, a small capped combo reward, sidecar and tags `bvs-schema-4`.
13. Harness and eval metrics: shield raises per fighter-minute (from shield-spam T4), combo length histogram and max combo, longest continuous Hurt per victim, win share by kit and side, combo damage by kit.

**S6: Retrain, gates and bundle**
14. One retrain covering both the shield fixes and the kits. Promotion only if all gates pass (see Success Criteria). Then golden parity, the replay `replay.mp4`, and the bundled model swap with `bvs.json`, fixtures and report.

**S7: Gated remote operations (after PR merge and explicit user confirmation, separately for each destination)**
15. Model repo `RafaelJaime/BVS-default` (model, `bvs.json`, model card, `replay.mp4`, tags `BVS`, `bvs-schema-4`).
16. Space `RafaelJaime/BroVSister` web build.

### Out of Scope
- Cancels, specials, grabs, parry, rolls, spot dodges (Direction C).
- New animations, art or audio. One frame per animation stays; combos come from mechanics only.
- Character-select UI changes beyond assigning the profile by the already-selected character.
- Charged smash for policies or the CPU (`attack_held` stays false for policies, as in schema 3).
- DI (directional influence) and SDI.
- Retraining community schema-3 models; they are listed as "Trained for an older version".
- New CI jobs, leaderboards or online play.

## Capabilities

### New Capabilities
- `attack-combos`: per-attack frame data (active frames, endlag, hitstun, link window, hit-stop scale), attack input buffer with one press per chain step, jab chains with launching finishers, victim-side combo tracking, anti-infinite safeguards (chain cap, hitstun decay from hit 4, hard cap 6, knockback growth per combo hit, 1.5 s time cap, post-hitstun invulnerability), lighter jab hit-stop, and the attacker HUD combo counter.
- `fighter-kits`: per-character `FighterProfile` resources assigned by character (movement, victim knockback scale, jumps, jab chain length, per-direction attack data, air jab, recovery), Rafael and Matilde initial values as tunable data, and the balance targets between kits.

### Modified Capabilities
- `combat-hits`: hitstun comes from the attack's frame data instead of one global formula; hits during hitstun land and extend a combo (subject to `attack-combos` safeguards) while the post-hitstun invulnerability is kept; Punch and Hurt timers are tick-based (extends "Timers independent of time scale"); hit-stop scales per attack and stays serialized.
- `smash-moves`: neutral punch becomes the kit's jab chain (single neutral hit where the kit says so); directional punches take their damage, knockback and frame data from the fighter's kit; the charged smash keeps its charge scaling on top of kit values.
- `fighter-movement`: run speed and jump/double-jump velocities come from the kit; the aerial attack set includes the kit's air jab (single or 2-hit) and down-air spike; Matilde's longer recovery.
- `fighter-shield`: record the already-implemented shield drop lag, minimum hold and raise cost (ODD `shield-spam` T1) so the spec matches the branch the retrain targets.
- `cpu-opponent`: Easy single jab, Normal jab chains, Hard chains plus launcher follow-ups; the CPU uses the attack buffer; difficulty ordering and Easy restrictions are preserved.
- `gameplay-state-snapshot`: new keys for kit id, chain step, link window open, hitstun left and combo counts; schema-4 required keys.
- `ai-schema`: schema 4 added as current (`BVS_SCHEMA_VERSION == 4`) with kit and combo features and the unchanged action layout; schema 3 stays frozen in the registry; v4 golden fixtures.
- `rl-training-pipeline`: kit randomization per side, capped combo reward, new eval and harness metrics, the added acceptance gates (shield raises, combo, balance), golden parity for schema 4, sidecar and tags `bvs-schema-4`, upload gate covering `replay.mp4` and the Space.
- `hub-model-distribution`: "Compatible" means schema 4; schema-3 models are listed as "Trained for an older version" and cannot be selected.

## Approach

1. **Timers first (S1).** Convert Punch and Hurt to `CombatClock` ticks behind the existing state API, and add a small buffered-attack field on the fighter consumed when the Punch state becomes actionable. The existing smoke suite must stay green before frame data changes, so S1 is a pure refactor plus the buffer.
2. **Frame data as data (S2).** Extend `AttackProfile` with frame-data fields whose defaults reproduce today's behavior, then add a chain table (ordered `AttackProfile` steps) consumed by `punch.gd`. Variant choice at press stays as today; a neutral press inside an open link window selects the next chain step.
3. **Combo state on the victim (S3).** `Hurt` owns combo count, combo start tick and combo damage; `Combat.resolve` reads them to apply hitstun decay, knockback growth, the hard cap and the time cap. The attacker HUD reads a combo signal from the victim. All values tunable in a resource.
4. **Kits as resources (S4).** `rafael_profile.tres` and `matilde_profile.tres` hold movement values plus per-direction attack and chain tables; the character selection assigns the profile instead of `FighterProfile.new()`. Prototype Matilde's up-launcher into air jab/air follow-up with a headless frame-advantage probe before tuning the rest; if it cannot connect, adjust launcher hitstun and knockback angle first (data only).
5. **CPU (S4).** Extend `CpuDifficulty` with chain and follow-up probabilities; `ScriptedController` queues presses into the buffer.
6. **Schema 4 alongside v3 (S5).** Copy the v3 module structure into `bvs_schema_v4.gd` and a v4 decoder (decode identical to v3), register version 4, keep v3 byte-identical. Training randomizes kits per row and adds a capped combo reward driven by combat signals, not observation reads. The harness gets the new metrics and gates.
7. **Retrain (S6).** Time-boxed runs (~25-60 min each) as in `combat-depth`; iterate reward weights and kit data only within the time box.
8. **Delivery.** One PR with `size:exception` and one logical commit (or a few) per slice. Uploads (S7) only after merge and explicit user confirmation, model repo and Space confirmed separately.

### Slices (authored-line forecast; generated fixtures, binaries and video excluded)

| # | Slice | Forecast |
|---|-------|----------|
| S1 | Tick-based Punch/Hurt timers, attack input buffer, smoke | ~250 |
| S2 | `AttackProfile` frame data, jab chains, jab hit-stop scale, smoke | ~350 |
| S3 | Victim combo tracking, safeguards, HUD combo counter, smoke | ~300 |
| S4 | Rafael/Matilde profiles and assignment, Matilde launcher prototype, CPU combos, smoke | ~380 |
| S5 | Schema 4 module/decoder/registry, snapshot keys, picker rule, kit randomization, combo reward, metrics and gates in harness/eval, v4 goldens, smoke | ~550 |
| S6 | Retrain, parity, harness gate run, `replay.mp4`, bundle swap, report | ~80 + binaries |
| S7 | Model card update; gated HF model upload and Space update | ~30 |

Total: about 1,940 authored lines, far above the 400-line budget. Delivery is a single PR with `size:exception` and logical commits (decided in preflight).

### Smoke-test plan (running Godot, the smoke suite and training is authorized for this change)
- **S1:** new `attack_buffer` and tick-timer checks (timers unchanged under hit-stop); regression of `hit_rules`, `combat`, `shield_spam`, `air_punch`, `match_flow`, `cpu_*`, `keyboard_playtest`, `match_e2e`.
- **S2:** frame-advantage probe per attack (expected advantage on hit for each jab step); a chain needs one press per step (hold does not chain); finisher launches.
- **S3:** infinite-probe (zero knockback, max mashing) ends by hit 6 and within 1.5 s; hitstun decay from hit 4; knockback growth; post-hitstun invulnerability kept; HUD counter appears at 2+ hits and fades.
- **S4:** kit assignment by character; Matilde up-launcher → air follow-up connects at low %; Rafael 2-hit and Matilde 3-hit jabs; jab chains whiff at high % (~70-90%); CPU difficulty ordering and Easy restrictions.
- **S5:** `schema_v4` (dimension, bounds, kit one-hot, decode parity with v3), v4 golden parity, frozen `schema_v3` and `schema_v2` checks unedited, `train_loads` with kit randomization, `hf_picker` (schema 3 shown as older version).
- **S6:** `policy_eval` and the committed harness over 100+ matches covering model vs model, model vs CPU and CPU vs CPU, both kits on both sides.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `game/player/StateMachine/PlayerStateMachine/States/punch.gd`, `hurt.gd` | Modified | Tick timers, buffer consumption, chain steps, combo state, safeguards |
| `game/combat/combat.gd`, `game/combat/attack_profile.gd`, `CombatClock` | Modified | Frame data, hitstun per attack, combo scaling, hit-stop scale |
| `game/player/fighter_profile.gd`, `game/player/player.gd` | Modified | Kit fields, profile assignment by character |
| `game/player/profiles/` (new `rafael_profile.tres`, `matilde_profile.tres`) | New | Kit data |
| `game/player/StateMachine/PlayerStateMachine/motion.gd` | Modified | Buffered attack input |
| `game/game.gd`, HUD card scene/script under `game/ui/` | Modified | Attacker combo counter |
| `game/player/controllers/scripted_controller.gd`, `cpu_difficulty.gd` + resources | Modified | Chains and launcher follow-ups per difficulty |
| `game/ai/schema/` (new `bvs_schema_v4.gd`, `bvs_action_decoder_v4.gd`), `bvs_schema.gd` | New/Modified | Schema 4 and registry |
| `scripts/hub_model.gd`, `scripts/model_manager.gd` | Modified | Version 4, compatibility rule |
| `scripts/AIController/`, `ai/training/reward_config.gd`, `reward_tracker.gd`, `train.tscn` | Modified | Kit randomization, combo reward |
| `training/bvs_training/` (export, golden, eval, harness), `training/README.md`, model card | Modified | Schema 4, metrics, gates, tags |
| `game/ai/models/bvs_default/`, `training/reports/` | Modified | Retrained model, report, replay |
| `tests/smoke/`, `tests/fixtures/` | New/Modified | New smoke tests, v4 fixtures |
| `odd/tasks/shield-spam.md` | Modified | T4 marked as moved into this change |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Matilde up-launcher → air follow-up does not connect | Med-High | Prototype first in S4 with a frame-advantage probe; tune launcher hitstun, angle and Matilde air speed as data; fall back to a jab-chain-only identity if still unreliable, reported before tuning the rest. |
| 2-4 frame links are fragile under buffer, hit-stop and timer interplay | Med | S1 tick timers land first; frame-advantage probes per attack are smoke tests; hit-stop excluded from link counting. |
| Infinites or touch-of-death combos slip through | Med | Safeguards ship in S3 before kits; infinite-probe smoke test; harness gates (max ≤ 6, no victim > 1.5 s in Hurt). |
| Kit imbalance (one character dominates) | Med-High | All values are data; harness gates on 40-60% win share and combo damage within 20%; keyboard playtest. |
| Single retrain regresses existing gates (sudden death, food, blocked share, KO vs Easy) or the shield-raise gate | Med | Kit randomization, capped combo reward, time-boxed weight iteration; keep the current bundled model if any gate fails (see Open Question 1). |
| Shield-raise gate threshold not yet defined (T4 never set a number) | Med | Design derives the threshold from measured baselines (CPU Hard and the current model) and records it before the retrain. |
| CPU cannot chain due to decision interval | Low-Med | Buffered presses; smoke test on chain rate per difficulty. |
| Schema-3 models drop out of the picker | Certain (accepted) | Listed as "Trained for an older version", as with schema 2. |
| v3 or v2 freeze accidentally altered | Low | Frozen checks stay unedited and green. |
| Remote ops executed without authorization | Low | S7 presents repo ids, files, tags, credential and results, then STOPs; no ambient auth probing. |

## Rollback Plan

- One logical commit (or a few) per slice, so slices revert cleanly in reverse order.
- Reverting S6 restores the schema-3 bundled model only if S5 is reverted too (a schema-4 runtime cannot bundle a schema-3 model as Compatible); reverting S5 and S6 together returns to schema 3 on top of the gameplay slices.
- Reverting S4 returns both characters to the default profile; S3 must not be reverted without S2 and S4 because chains without safeguards are infinite (revert S2-S4 together, or S1-S4).
- Balance problems are fixed through data (`.tres` profiles and safeguard resource), not reverts.
- Reverting the PR restores the `fix/shield-spam` base behavior.
- HF uploads are reversible by the user through the repo history; the Space can be redeployed from the previous build. No remote cleanup without separate authorization.

## Dependencies

- Godot 4.7.2 headless, the existing `training/` uv project, and an M5 for training (~25-60 min per run).
- The shield-spam work already on the branch (T1-T3); its T4 retrain is merged into S6.
- Existing assets only (`T_VFX_Glow_1`, `T_LeLuStar11`, current fonts and sprites).
- `hf` CLI authenticated by the user, needed only at the gated S7 step.

## Success Criteria

- [ ] **Combos exist.** Frame-advantage probes show each jab step links into the next at low %; 2+ hit combos occur in CPU Normal/Hard and model matches.
- [ ] **No infinites.** Max combo ≤ 6 over 100+ harness matches; no victim spends more than 1.5 s continuously in Hurt; the post-hitstun invulnerability is kept; jab chains whiff at high %.
- [ ] **Kits differ.** Rafael and Matilde use their profiles (movement, jab length, launchers, air jab, recovery) assigned by character; the Matilde up-launcher into an air follow-up connects at low %.
- [ ] **Each chain step needs its own press** (buffered); holding attack never auto-chains.
- [ ] **HUD.** "N HIT COMBO" with damage appears on the attacker's HUD for 2+ hits and fades after about 1 s.
- [ ] **CPU.** Easy single jab, Normal chains, Hard chains plus launcher follow-ups; difficulty ordering and Easy restrictions preserved.
- [ ] **Schema 4.** `BVS_SCHEMA_VERSION == 4`, v4 golden parity passes, frozen v3/v2 checks unedited and green, schema-3 models shown as "Trained for an older version".
- [ ] **Harness gates** with the retrained default (100+ matches, both kits, both sides): existing gates hold (sudden death ends, food usage, blocked share ≤ 70%, KO vs Easy ≥ 60% with non-trivial play); shield raises per fighter-minute under the threshold set in design; 2+ hit combos occur; max combo ≤ 6; no victim > 1.5 s in Hurt; Rafael win share 40-60% in CPU Hard mirror and model vs model; combo damage within 20% between kits.
- [ ] **Artifacts.** Retrained model, `bvs.json` (schema 4), fixtures, report and `replay.mp4` committed.
- [ ] **Remote (after merge and explicit confirmation).** `RafaelJaime/BVS-default` carries `bvs-schema-4` and shows as Compatible; the Space runs the new build.

## Open Questions (product decisions for the orchestrator)

1. **Gate failure after the time box.** The schema-4 runtime cannot keep the schema-3 model as a Compatible bundled default. If the retrain fails a gate after the time box, which applies? (a) Do not merge until the gates pass (more iterations, kits and model ship together). (b) Merge the gameplay and schema 4 with the best candidate model and report the failed gate. (c) Merge the gameplay slices (S1-S4) only, keep schema 3 and the current model, and move S5-S6 to a follow-up. Only S6 promotion and the merge decision depend on this; all other slices proceed.

## Resolved Decision (orchestrator, 2026-10-04)

**Gate failure at the time box → option (a) first.** Keep iterating (reward weights, curriculum, steps) within the time box and do not merge until every gate passes. Only if the time box is exhausted with a gate still failing, STOP and ask the user to choose between (b) merging the best candidate with the failed gate reported and (c) merging S1–S4 on schema 3 and moving S5–S6 to a follow-up.

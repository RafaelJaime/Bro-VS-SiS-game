# Proposal: Combat Depth (shield meter, food that matters, sudden-death bombs, schema 3)

Mirror of Engram `sdd/combat-depth/proposal`. Builds on `explore.md` (Engram `sdd/combat-depth/explore`). Branch `feat/combat-depth`.

## Intent

Matches are boring to play and to watch, and model-vs-model matches never end.

- **Block dominates.** `protect.gd` has no meter, cooldown or cost. A blocked hit deals 50% damage and 30% knockback. Model vs model: 99.7% of hits are blocked (3695/3706), and block uptime is 33-36%.
- **Food is ignored.** The models make 0 pickups and 0 throws in 144 fighter-minutes. There are four causes:
  1. The throw action is masked by `Motion.ACTION_PRIORITY` (`motion.gd:19`). `a5_throw` is never chosen alone.
  2. No reward term covers food.
  3. Food is worth about the same as a punch (average 9.8 dmg / 224 kb against 8 / 220) but costs a walk, a pickup and a throw.
  4. The pickup band is narrow (±26..70 px).
- **Sudden death never ends.** It sets 300% and 1 stock, then runs with no escalation. A blocked punch at 300% slides the target about 44 px and never launches it. Of 20 forced sudden deaths, 0 ended within 120 s. In regulation, 18 of 20 model-vs-model matches were still unresolved at the 120 s sudden-death cap.
- **The CPU is exploitable.** The model beat CPU Hard 20/20 (120/120 across runs). The CPU blocks rarely and has no answer to a turtling opponent.

Goal (user): play that feels like Smash and is fun both to play and to watch models fight. Success means the following:
- Shields have a cost and can break.
- Food is worth fetching.
- Sudden death always ends quickly.
- A retrained default model shows varied play: it fetches food, pressures shields, and still beats CPU Easy.

## Scope

### In Scope

**S1: Game changes. These ship without a schema change; the bundled v2 model keeps running, with degraded play.**
1. **Shield meter (Smash).**
   - Shield HP drains while the shield is held and when it absorbs a hit (shield damage scales with the hit's damage). It regenerates after release.
   - At 0 the shield breaks: the fighter is dizzy and stunned for about 2 s, and is fully punishable (hits apply full damage and knockback).
   - Blocked hits still deal chip damage.
   - All values are tunable data in the fighter profile or a resource.
2. **Shield HUD.** A per-fighter shield indicator: a shrinking bubble around the fighter or a bar on the HUD card, plus a clear break and dizzy cue. Only existing assets are used.
3. **Food rebalance.**
   - Every weight class beats a neutral punch in damage and knockback.
   - Food does not pierce the shield, but it deals high shield damage. One heavy food on a weakened shield breaks it. A full shield takes more than one heavy hit to break.
   - Food spawns faster (tunable cap on simultaneous food).
   - Pickup reach is larger and centered near the feet.
   - Two or three item-identity effects use existing art and VFX. One example: "hot" items (coffee/soup/stew) show a fire VFX and add knockback. The final list is set in design.
4. **Throw not masked by priority.** When a fighter holds food, the throw resolves ahead of punch and protect. Only recovery, dash and jump still outrank it. This also fixes human "punch + throw" collisions.
5. **Sudden-death escalation (Smash Ultimate).**
   - After about 20 s of sudden death, bombs fall from above the stage at an increasing rate.
   - They use the existing `2D Fire - Tutorial` VFX textures and the `fireball-explosion` SFX.
   - Bombs are unblockable: they ignore the shield. At 300% a bomb hit is lethal knockback.
   - A hard cap resolves any match that is still running (see Open Question 1).
   - Bomb timing uses match time, so it is unaffected by hit-stop `Engine.time_scale`. CPU particles keep it compatible with the web build.
6. **CPU update.** All difficulties respect the shield meter: they release before it breaks and do not hold it indefinitely.
   - Normal and Hard punish dizzy opponents, pressure shields (including with heavy food), and use the larger food reach.
   - Hard dodges falling bombs.
   - Easy stays simple and beatable, and keeps its current spec constraints (no directional aim or special).
   - Goal: fun against humans. This is not tuned to beat the model.
7. **Smoke tests.** Under `tests/smoke/`: shield drain, regen and break; dizzy punish; blocked chip; bomb unblockable at 300%; sudden death ends under the cap; food beats punch; pickup reach; throw priority; CPU respects the shield.

**S2: Schema 3 and training changes**
8. **`bvs-schema-3`.**
   - New module `bvs_schema_v3.gd` and a v3 decoder, plus a registry entry. v2 stays frozen and byte-identical.
   - New observation features: shield HP (self and opponent), dizzy flag and remaining time, sudden-death phase and elapsed time, and the nearest falling bombs (position and velocity, with sentinels).
   - The action layout is kept as the v2 `nvec` unless design shows a need to change it.
   - The v3 decoder makes `a5_throw` exclusive: while food is held, throw suppresses the same-window attack pulse.
   - `HubModel.BVS_SCHEMA_VERSION` changes to 3. The required snapshot keys are extended.
   - Golden observation fixtures are regenerated for v3. v2 fixtures are kept.
9. **Training changes.**
   - New reward terms (tunable data): pickup, food hit landed, shield break dealt or taken, and a small penalty for holding the shield too long.
   - Sudden death is included in training: a timer-expiry tie enters sudden death instead of a draw, and the step cap stays as truncation.
   - The eval script adds the combat-depth metrics:
     - sudden-death length
     - pickups and throws per minute
     - blocked-hit share
     - damage by source
     - shield breaks
   - The exploration harness becomes a committed, repeatable eval scenario.
   - Sidecar and tags move to `bvs-schema-3`.

**S3: Retrain, evaluate, bundle**
10. Retrain the default model on schema 3 with the existing curriculum plus sudden-death episodes. Then:
    - Run golden parity and the evaluation.
    - Rerun the exploration harness for the acceptance metrics.
    - Replace `game/ai/models/bvs_default` and commit the model, `bvs.json`, fixtures and report.

**S4: Gated remote operations. Each needs explicit user authorization.**
11. Re-upload to `RafaelJaime/BVS-default`: `model.onnx`, `bvs.json` and the model card, with tags `BVS` and `bvs-schema-3`.
12. Update the Space `RafaelJaime/BroVSister` with the new web build.

### Out of Scope
- Grabs, shield-grab, parry or perfect shield, rolls and spot dodges. Shield break and heavy food are the anti-turtle answer for now.
- Charged smash for policies or the CPU. `attack_held` stays false in schema 3.
- New art or audio assets.
- Community schema-2 models stay playable only if retrained. They are listed as "Trained for an older version".
- An online leaderboard, Elo, or new CI jobs.
- Air shield removal, unless decided otherwise (Open Question 2).

## Capabilities

### New Capabilities
- `fighter-shield`: shield meter (drain while held, drain on blocked hits scaled by damage, regen on release), blocked-hit chip and knockback, shield break into a dizzy/stun state (~2 s, punishable), unblockable hit flag, HUD shield and break indicator, and tunable data.
- `sudden-death-hazards`: falling bombs after a sudden-death grace period with an escalating rate, unblockable damage and knockback, existing VFX and SFX, match-time based (unaffected by hit-stop), and safe in training rows (Game-local).

### Modified Capabilities
- `food-fight-items`: food stats exceed a neutral punch, shield damage per weight class, faster spawns and a cap, larger pickup reach, throw priority over punch and protect while holding food, and a small set of item-identity effects. This reverses "Per-food effects are out of scope". No new assets.
- `match-flow`: sudden death adds escalation through `sudden-death-hazards` and a hard cap that always resolves the match (resolution rule per Open Question 1).
- `combat-hits`: hits against a shielding or dizzy target follow `fighter-shield`. Bomb hits bypass the shield. Post-hit invulnerability does not grant shield immunity to bombs. Hit-stop stays serialized.
- `cpu-opponent`: the CPU respects the shield meter. Normal and Hard punish dizzy opponents, pressure shields with heavy food, and dodge bombs (Hard). Difficulty ordering is preserved and Easy keeps its restrictions.
- `gameplay-state-snapshot`: new keys for shield HP, dizzy state and timer, sudden-death phase and elapsed time, and active bombs. Existing keys are unchanged.
- `ai-schema`: schema 3 is added as the current version (`BVS_SCHEMA_VERSION == 3`) with shield and hazard features and an exclusive throw decode. Schema 2 stays frozen in the registry.
- `rl-training-pipeline`: food and shield reward terms, sudden death in training episodes, combat-depth eval metrics and acceptance thresholds, sidecar and tags `bvs-schema-3`, and an upload gate that also covers the Space update.
- `hub-model-distribution`: "Compatible" means the current playable schema (3). Schema-2 models, still registered for frozen decoding and tests, are listed as "Trained for an older version" and cannot be selected.

## Approach

1. **Shield as a meter on the fighter, not a new controller concept.**
   - `protect.gd` keeps the existing `block` intent, so `HumanController`, `ScriptedController` and the v2 decoder need no change.
   - `Combat` routes a hit on a shielding target into shield damage plus chip.
   - A new `Dizzy` FSM state handles the break. It reuses the hitstun visuals with an added wobble or stars cue from existing sprites.
   - The values live in a resource, so balancing is data-only.
2. **Food rebalance in `FoodCatalog.WEIGHT_STATS`.** A `shield_damage` field and optional identity tags are added. Spawner cadence and the cap are exported. The `PickupArea` is resized and recentered.
   - Throw priority is a targeted `Motion` change: when food is held, `shoot` ranks above `punch` and `protect`.
3. **Bombs as a `SuddenDeathHazards` node owned by `Game`.**
   - Started by `_start_sudden_death` after the grace period.
   - Spawns Game-local bomb instances that hit the hurtbox with an `unblockable` flag.
   - The spawn interval tightens over time, so a KO arrives in practice within ~10-20 s of bombs starting.
   - A hard cap timer is the final safety net.
4. **CPU.** Extend the `CpuDifficulty` resource with shield-release threshold, punish-dizzy probability, food-pressure probability and bomb-dodge, and branch in `ScriptedController`. Verify with CPU-vs-CPU and keyboard playtests.
5. **Schema 3 alongside v2.** Copy the v2 module structure into `bvs_schema_v3.gd` and `bvs_action_decoder_v3.gd` and register version 3. v2 smoke and fixtures remain untouched to prove the freeze.
   - The picker's compatibility check moves from "registered" to "current playable version".
6. **Training.**
   - Add reward components in `reward_config.gd` and `reward_tracker.gd`, driven by pickup, food-hit and shield-break signals (not observation reads).
   - Allow sudden death in training rows.
   - Extend the eval script and commit the harness scenario.
   - Retrain time-boxed (~25-60 min per run). Iterate on reward weights only within the time box.
7. **Delivery.** One PR with `size:exception` and logical commits per slice, as in previous changes. S1 is shippable on its own: verify it with CPU and keyboard before starting S2.

### Slices (authored-line forecast; generated fixtures and binaries excluded)

| # | Slice | Forecast |
|---|-------|----------|
| S1 | Shield meter + Dizzy state + HUD, food rebalance + reach + throw priority + identity effects, sudden-death bombs + hard cap, CPU update, smoke tests | ~850 |
| S2 | Schema 3 module + decoder + registry/version bump, snapshot keys, picker compatibility rule, reward terms, sudden death in training, eval metrics + committed harness, v3 golden generation, smoke | ~600 |
| S3 | Retrain, parity, eval report, harness acceptance run, bundled model swap | ~80 + binaries |
| S4 | Model card update; gated HF re-upload and Space web build update (no new code) | ~30 |

Total: about 1,560 authored lines, well above the 400-line budget. Delivery is a single PR with `size:exception` (decided in preflight).

### Smoke-test plan (running Godot and tests is authorized for this change, as relayed by the orchestrator)
- **S1:** new shield, hazard, food and CPU smoke tests, plus regression of the existing suite (`hit_rules`, `combat`, `match_flow`, `cpu_*`, `hud`, `keyboard_playtest`, `match_e2e`).
  - The existing `schema_v2`, `onnx_golden` and `policy_match` tests must still pass (the v2 model still loads and plays).
- **S2:**
  - New `schema_v3` smoke test (dimension, bounds, sentinels, decode, throw exclusivity) and v3 golden parity.
  - `schema_v2` unchanged.
  - `train_loads` with sudden death enabled.
  - `hf_picker` (v2 shown as older version).
- **S3:** `policy_eval` (≥ 20 matches vs Easy and Normal) and the committed combat-depth harness (model vs model, model vs CPU, CPU vs CPU).

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `game/player/StateMachine/PlayerStateMachine/States/protect.gd` | Modified | Shield meter drain and regen, break trigger |
| `game/player/StateMachine/PlayerStateMachine/States/` (new `dizzy.gd`) | New | Shield-break stun state |
| `game/player/StateMachine/PlayerStateMachine/motion.gd` | Modified | Throw priority while holding food |
| `game/combat/combat.gd`, `game/combat/attack_profile.gd` | Modified | Shield damage, chip, unblockable flag |
| `game/player/fighter_profile.gd` (or new shield resource) | Modified/New | Tunable shield values |
| `game/food/food_catalog.gd`, `food_spawner.gd`, `food_pickup.tscn`, `food_projectile.gd` | Modified | Stats, shield damage, spawn cadence, reach, identity effects |
| `game/game.gd`, `game/game.tscn` | Modified | Sudden-death hazards, hard cap, HUD shield indicator |
| `game/hazards/` (new) | New | Bomb scene and hazard spawner (existing VFX and SFX) |
| `game/audio/sfx.gd` | Modified | Bomb and shield-break event bands (existing sounds) |
| `game/player/controllers/scripted_controller.gd`, `cpu_difficulty.gd` + resources | Modified | Shield-aware CPU, punish, bomb dodge |
| `game/ai/schema/` (new `bvs_schema_v3.gd`, `bvs_action_decoder_v3.gd`), `bvs_schema.gd` | New/Modified | Schema 3 and registry |
| `scripts/hub_model.gd`, `scripts/model_manager.gd` | Modified | Version 3, compatibility rule |
| `scripts/AIController/`, `ai/training/reward_config.gd`, `reward_tracker.gd`, `train.tscn` | Modified | Rewards, sudden death in training |
| `training/bvs_training/` (export, golden, eval), `training/README.md`, model card | Modified | Schema 3, metrics, tags |
| `game/ai/models/bvs_default/`, `training/reports/` | Modified | Retrained model and report |
| `tests/smoke/`, `tests/fixtures/` | New/Modified | New smoke tests, v3 fixtures |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Retrained policy still turtles or ignores food | Med-High | Throw priority, exclusive decode, food reward, higher food value and the shield cost remove the root causes. Acceptance gates on harness metrics. Iterate on reward weights within the time box, and keep the old bundled model if the gates fail. |
| Shield too strong or too weak; bombs feel unfair to humans | Med | All values are data. Keyboard playtest after S1. Bombs only appear after the grace period and are telegraphed (shadow or fall). |
| Hit-stop scaling `Engine.time_scale` skews sudden-death and dizzy timers | Med | Drive timers from match or physics ticks, not wall time. Smoke test asserts sudden death ends under the cap. |
| Longer training episodes from sudden death slow training | Low-Med | Bombs end sudden death fast. The step cap remains. |
| CPU balance regresses (Easy too hard, or Hard still exploitable) | Med | Difficulty ordering smoke test, CPU-vs-CPU harness, keyboard playtest. Not tuned against the model. |
| Interim S1 build degrades the bundled v2 model's play | Low | S1 to S3 ship in one PR. The interim state exists only on the branch. |
| Bomb VFX cost on the web (GL Compatibility) | Low | CPU particles, cap on simultaneous bombs. |
| v2 freeze accidentally altered | Low | Existing `schema_v2` and golden smoke tests must stay green and unedited. |
| Remote ops executed without authorization | Low | The S4 gate presents repo id, files, tags, credential and eval results, then STOPs. No ambient auth probing. |

## Rollback Plan

- One logical commit per slice. S3 can be reverted alone to restore the v2 bundled model, but the gameplay changes from S1 remain. S2 and S3 can be reverted together to return to schema 2 and its model on top of S1.
- Reverting S1 restores the unlimited shield, the old food stats and sudden death without hazards. Balance knobs are data, so most tuning problems are fixed without a revert.
- Reverting the PR restores master `bef271f` behavior completely.
- The HF re-upload is reversible by the user: the previous schema-2 revision stays in the repo's git history. The Space can be redeployed from the previous build. The agent does no remote cleanup without separate authorization.

## Dependencies

- Existing `training/` uv project, Godot 4.7.2 headless and an M5 for training (~25-60 min per run).
- Existing assets only: `assets/textures/2D Fire  - Tutorial/*`, `fireball-explosion.wav`, and the food sprites.
- `hf` CLI, authenticated by the user, needed only at the gated S4 step. The Space deploy method is confirmed at the gate.

## Success Criteria

- [ ] **Shield.** Holding the shield continuously breaks it within a tunable time (~5 s by default). A broken shield causes ~2 s of dizzy during which hits apply in full. Blocked hits deal chip. The HUD shows the shield level and the break.
- [ ] **Food.** Every weight class out-damages a neutral punch. A heavy food on a weakened shield breaks it. Throws are never masked while holding food (smoke test).
- [ ] **Sudden death.** Bombs start after ~20 s and are unblockable. 20/20 forced sudden deaths end, and every match ends at or before the hard cap.
- [ ] **CPU.** The CPU respects the shield, and Normal and Hard punish dizzy opponents. Difficulty ordering is preserved. A keyboard playtest confirms the CPU stays fun and beatable at Easy.
- [ ] **Schema 3.** `BVS_SCHEMA_VERSION == 3` and v3 golden parity passes. Schema-2 smoke tests and fixtures are unchanged and green. Schema-2 Hub models show "Trained for an older version".
- [ ] **Harness acceptance** with the retrained default:
  - Model-vs-model sudden death ends in under ~45 s on average.
  - Food pickups exceed 1/min per fighter.
  - The blocked-hit share is well under 99% (target ≤ 70%).
  - The model wins ≥ 60% by KO vs CPU Easy over ≥ 20 matches, with non-trivial play.
- [ ] **Artifacts.** Retrained model, `bvs.json` (schema 3), fixtures and eval report are committed.
- [ ] **Remote (after explicit authorization).** `RafaelJaime/BVS-default` carries `bvs-schema-3` and appears as Compatible in the picker. The Space runs the new build.

## Open Questions (product decisions for the orchestrator)

1. **Hard-cap resolution.** If sudden death is still running at the hard cap (proposed ~60 s after sudden death starts, practically unreachable with bombs), what decides the result? The options:
   - (a) The fighter with the lower damage % wins, and an exact tie is a draw.
   - (b) Always a draw ("No contest"). This needs a draw state on the results screen.
   - (c) Bombs simply become continuous, with no separate cap rule.
2. **Air shield.** Smash has no air shield, and the game currently allows air block (`fighter-movement` "Air block"). Should the shield become ground-only (more faithful, and it modifies `fighter-movement`)? Or should air block stay, draining the same meter (the proposal default)?

## Resolved Decisions (orchestrator, Smash-faithful, 2026-10-03)

1. **Hard cap → option (c), Smash Ultimate behavior.** In real matches there is no cap rule: bombs keep falling with an increasing spawn rate until someone is KO'd (a double KO restarts sudden death). A safety cap exists only for training episodes (ends the episode as a draw for reward purposes).
2. **Air shield → ground-only shield (Smash).** The shield works only on the ground. The current air block becomes an **air dodge**: brief invulnerability, a cooldown, no shield-meter cost, and one per airtime (resets on landing, ledge grab or being hit). This modifies `fighter-movement` "Air block".

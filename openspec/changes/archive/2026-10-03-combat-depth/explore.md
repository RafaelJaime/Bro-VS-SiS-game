# Explore: combat-depth

Mirror of Engram `sdd/combat-depth/explore`. Branch: `feat/combat-depth` (from master `bef271f`).

Feedback (user): models ignore the floor food (they only punch, block and jump), which is boring to watch and play; in sudden death, if one hits and the other blocks, a model-vs-model match never ends.

## 1. Measurements (scratch harness, not in repo)

Bundled model `game/ai/models/bvs_default` (schema 2, argmax, one decision per 4 frames). Full `game.tscn` matches, countdown skipped, 60 fps headless. Game time is scaled by hit-stop.

| Metric | Model vs model (20) | Model vs CPU Hard (20) | CPU Hard vs Hard (10) |
|---|---|---|---|
| Ending | 20/20 tie at 99 s then sudden death; 18/20 unresolved at SD cap 120 s | 20/20 KO, mean 19.4 s | 10/10 KO, mean 69.8 s |
| Sudden death alone (20 forced runs) | 0/20 end in 120 s | n/a | n/a |
| Pickups/min | 0.00 | model 0.00, CPU 4.41 | 6.44 |
| Throws/min | 0.00 | model 0.00, CPU 4.26 | 6.36 |
| Block uptime | 33-36%, max hold 1.03 s | model 30%, CPU 11% | 9-14% |
| Punches/min | ~63 | model 45.5, CPU 28.6 | ~33 |
| Hits blocked | 99.7% (3695/3706) | model blocks 95% of CPU punches, 3 of 27 food hits | ~33% |
| Damage by source | punch 100%, food 0, smash 0 | model takes food 26% | food ~21% |

- Food in pickup reach 16-24% of frames in PvP, yet 0 pickup attempts.
- Smash damage is 0 for models and CPU: nothing holds the punch to charge.

## 2. Why the models ignore food

1. **Throw is masked by priority**: `motion.gd:19` `ACTION_PRIORITY` recovery > dash > jump > punch > protect > shoot. `a5_throw=1` in 20.5% of decisions, never alone, so it never executes.
2. **No reward for food**: `reward_config.gd`/`reward_tracker.gd` credit damage, KO, win, time, off-stage, approach; pickup and throw get nothing. Training never reaches sudden death (obs[101] always 0).
3. **Expected value ≈ punch**: food light 6/160, medium 10/230, heavy 16/320 (dmg/kb) vs punch 8/220; food needs walking + pickup + throw, single use; block applies equally.
4. **Narrow pickup reach**: PickupArea r=70 centered on fighter origin 65 px above resting food → ±26..70 px horizontal.
5. Observation already exposes food adequately (2 nearest foods, projectiles, holding flags).
6. CPU does use food and the model barely blocks it (3/27).

## 3. Why sudden death never ends

- `game.gd` `_start_sudden_death`: 300%, 1 stock, no timeout, no escalation.
- `protect.gd`: no meter, no cooldown, no cost. Blocked hit = 50% damage, 30% knockback × (1 + dmg/50): neutral punch at 300% ≈ 44 px slide, never launches.
- Edge pressure can beat a perfect blocker (2.5-5.3 s in a scripted test), but models never corner each other.

## 4. Directions

- **A. Shield meter + break (Smash)**: shield HP drains while held and on blocked hits, regenerates on release; break → ~2 s dizzy, punishable. S-M effort; needs schema 3 (shield obs).
- **B. A + food rebalance + sudden-death escalation (recommended)**: more/bigger food, heavy food high shield damage, item effects; sudden death bombs after ~20 s (Smash Ultimate) with existing fire/explosion assets; food reward terms; retrain. M-L effort.
- **C. Minimal**: SD timer/bombs + chip + throw priority. S effort; doesn't fix block dominance in regulation.

## Training implications

Schema 3 (`bvs_schema_v3.gd` + registry entry; v2 frozen): shield features (+ hazards), throw priority/dedicated action, food reward terms, sudden death in training, retrain default (~25-60 min), HF re-upload of `RafaelJaime/BVS-default` (remote op → user authorization). Schema-2 models become "older version".

## Recommendation

Direction B in two slices: (1) game changes without schema break, verified with CPU + keyboard; (2) schema 3 + retrain, acceptance = rerun this harness (PvP sudden death ends < ~45 s, food pickups > 1/min per fighter, blocked share well under 99%).

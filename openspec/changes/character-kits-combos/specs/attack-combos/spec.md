# Attack Combos Specification

## Purpose

Combos that come from mechanics only (per-attack frame data, hitstun, knockback, jab chains and an attack input buffer), with fairness safeguards so no infinite or touch-of-death combo exists. One frame per animation is kept: no new art or audio. All numeric values are tunable defaults held in data (Resources), never hard-coded in state scripts. All timers in this capability are measured in match or physics ticks and MUST NOT depend on `Engine.time_scale` or hit-stop. Verification: Godot smoke tests under `tests/smoke/` (frame-advantage probes, infinite probe, HUD checks) and the Python harness checks described in `rl-training-pipeline`. Frame numbers below assume 60 ticks per second.

## Requirements

### Requirement: Per-attack frame data

Each attack (`AttackProfile`) MUST carry frame data: active frames, endlag, hitstun (explicit, or a base plus growth), link window, and a hit-stop scale. When a field is not set, its default MUST reproduce the pre-change behavior (global hitstun formula `clamp(0.2 + |kb| * 0.0004, 0.3, 0.9)` seconds, single punch duration and cooldown). The global hitstun formula MUST remain as the per-attack default only. Frame data MUST be tick-based and held in data.

#### Scenario: Defaults reproduce legacy behavior
- GIVEN an `AttackProfile` that sets no frame-data field
- WHEN it hits a victim at 0% damage
- THEN hitstun equals the legacy formula result and the attacker's next attack is available after the legacy cooldown

#### Scenario: Explicit hitstun wins
- GIVEN an attack with an explicit hitstun of 0.55 s
- WHEN it hits a victim
- THEN the victim is in hitstun for 33 ticks (before combo decay)

#### Scenario: Frame data is data-driven
- GIVEN the endlag of an attack is edited in its Resource
- WHEN a match starts
- THEN the attacker's recovery reflects the edit with no script change

### Requirement: Tick-based attack and hit timers

Punch duration, endlag, link windows and hitstun (the Punch and Hurt timers) MUST be measured in ticks via the combat clock and MUST NOT depend on `Engine.time_scale`. The post-hitstun invulnerability window keeps its existing fighter timer (it starts only when hitstun ends, so it is never on a link path). Hit-stop MUST NOT consume or extend link windows, hitstun or endlag.

#### Scenario: Hit-stop leaves attack timers intact
- GIVEN a hit triggers hit-stop that lowers `Engine.time_scale`
- WHEN the victim's hitstun and the attacker's endlag are measured in ticks
- THEN both equal the values measured without hit-stop

#### Scenario: Post-hit invulnerability starts at hitstun end
- GIVEN a victim whose tick-based hitstun expired
- WHEN the invulnerability window (default 0.5 s, existing fighter timer) is granted
- THEN it starts on the tick hitstun ends, and the hitstun length itself is identical with and without hit-stop

### Requirement: Attack input buffer

A fighter MUST buffer an attack press made during its own endlag or during hit-stop for a tunable number of ticks (default 6) and MUST fire the buffered attack on the first actionable tick. An expired buffered press MUST be discarded. Each chain step MUST require its own press: holding attack MUST NOT auto-chain or auto-repeat.

#### Scenario: Press during endlag fires on the first actionable tick
- GIVEN a fighter with 3 ticks of endlag left
- WHEN attack is pressed
- THEN the attack starts on the first tick the fighter is actionable

#### Scenario: Press during hit-stop is kept
- GIVEN a fighter in hit-stop that just landed a hit
- WHEN attack is pressed during the hit-stop
- THEN the press is buffered and fires on the first actionable tick if still within the buffer window

#### Scenario: Expired buffer is discarded
- GIVEN a press made more than 6 ticks before the fighter becomes actionable
- WHEN the fighter becomes actionable
- THEN no attack starts

#### Scenario: Holding does not auto-chain
- GIVEN a fighter in a jab chain and attack held continuously without a new press
- WHEN the link window of step 1 opens and closes
- THEN step 2 never starts and the chain resets

### Requirement: Jab chains

The neutral punch MUST be a chain of ordered steps defined by the kit (see `fighter-kits`). A neutral press inside the open link window of the current step MUST advance to the next step. A press outside the window MUST start step 1. The finisher (last step) MUST always launch the victim with the finisher's knockback. Jab steps MUST use a hit-stop scale below 1.0 (default 0.5) so chain pacing stays fluid. At low damage each non-final step MUST link into the next (the victim is still in hitstun when the link window opens); at high damage (about 70-90%) non-final steps MUST be able to whiff because knockback growth pushes the victim out of reach.

#### Scenario: Press in the link window advances
- GIVEN a fighter whose step 1 hit connected and whose link window is open
- WHEN attack is pressed
- THEN step 2 starts and the chain step counter equals 2

#### Scenario: Press outside the window restarts
- GIVEN the link window of step 1 has closed
- WHEN attack is pressed
- THEN step 1 starts and the chain step counter equals 1

#### Scenario: Finisher launches
- GIVEN the final step of a jab chain connects
- WHEN knockback is applied
- THEN the victim is launched with the finisher's knockback and the chain resets

#### Scenario: Frame advantage at low percent
- GIVEN a victim at 0% and each non-final jab step connecting
- WHEN the frame-advantage probe runs
- THEN the victim's remaining hitstun when the attacker becomes actionable is at least 0 ticks and at most the kit link slack (2 to 4 ticks)

#### Scenario: Jab hit-stop is lighter
- GIVEN a jab step and a finisher or smash that both connect
- WHEN hit-stop durations are compared
- THEN the jab step's hit-stop is shorter than the other's

#### Scenario: Chain whiffs at high percent
- GIVEN a victim at 80% damage
- WHEN the jab chain is mashed (one press per step)
- THEN at least one non-final step does not connect over the probe sample

### Requirement: Victim-side combo tracking

The victim MUST track the combo: hit count, start tick, accumulated combo damage and attacker. A combo MUST continue while a hit lands during hitstun or on the first actionable tick of the attacker's buffered follow-up before hitstun expires. A combo MUST reset when hitstun expires without a new hit. Blocked hits (shield) MUST NOT start or extend a combo. Combo tracking MUST be tick-based and read-only for observers.

#### Scenario: Second hit extends the combo
- GIVEN a victim in hitstun after hit 1
- WHEN hit 2 lands before hitstun expires
- THEN the combo count is 2 and the combo damage is the sum of both hits

#### Scenario: Reset on hitstun expiry
- GIVEN a victim whose hitstun expires without a new hit
- WHEN the next tick runs
- THEN the combo count is 0

#### Scenario: Blocked hit does not extend
- GIVEN a combo of 2 hits and a victim that raises the shield in time
- WHEN a hit is blocked
- THEN the combo count stays at its value and no hitstun starts

### Requirement: Anti-infinite safeguards

The system MUST guarantee that no combo is infinite, using tunable data:
1. Chain cap: the finisher always launches.
2. Hitstun decay: from combo hit 4 each further hit's hitstun MUST be multiplied by a decay factor below 1 per hit (default 0.75).
3. Knockback growth: knockback MUST be multiplied by 1.1 per combo hit (cumulative).
4. Hard cap: the 6th hit of a combo MUST launch the victim and the victim MUST become invulnerable immediately for the post-hit invulnerability window (default 0.5 s).
5. Time cap: a combo MUST end no later than 1.5 s (90 ticks) after its first hit; the next hit after the cap is treated as a new combo start only after the post-hit invulnerability window.
6. The existing 0.5 s post-hitstun invulnerability MUST be kept.

#### Scenario: Infinite probe terminates
- GIVEN a victim with zero knockback scale and an attacker mashing at the maximum rate
- WHEN the infinite probe runs for 4 s
- THEN no combo exceeds 6 hits and no victim stays in hitstun longer than 1.5 s continuously

#### Scenario: Hard cap on the 6th hit
- GIVEN a combo of 5 hits
- WHEN hit 6 lands
- THEN the victim is launched and takes no damage or knockback during the following 0.5 s

#### Scenario: Hitstun decay from hit 4
- GIVEN a combo where hits 3 and 4 use the same attack
- WHEN their hitstun is compared
- THEN hit 4's hitstun is shorter than hit 3's by the decay factor and hits 1 to 3 are not decayed

#### Scenario: Knockback grows per combo hit
- GIVEN two successive hits of the same attack in one combo at equal damage %
- WHEN knockback is compared
- THEN hit 2's knockback is 1.1 times hit 1's (within rounding)

#### Scenario: Time cap
- GIVEN a combo that started 90 ticks ago
- WHEN another hit would land
- THEN it launches the victim and the victim becomes invulnerable for the post-hit window

#### Scenario: Post-hitstun invulnerability kept
- GIVEN a victim whose hitstun just expired
- WHEN any hit connects within the next 30 ticks
- THEN no damage or knockback applies

### Requirement: Combo counter HUD

The attacker's HUD card MUST show a small "N HIT COMBO" label with the combo damage when a combo reaches 2 or more hits. It MUST NOT appear for single hits. It MUST fade about 1 s after the last hit of the combo (tunable) and MUST use only existing assets and VFX (for example `T_VFX_Glow_1`, `T_LeLuStar11`). It MUST be driven by a signal from the victim's combo state and MUST NOT alter gameplay.

#### Scenario: Counter appears at two hits
- GIVEN a combo reaches its second hit
- WHEN the HUD updates
- THEN the attacker's card shows "2 HIT COMBO" with the combo damage

#### Scenario: Counter hidden for one hit
- GIVEN a single hit
- WHEN the HUD updates
- THEN no combo label is shown

#### Scenario: Counter fades
- GIVEN a visible combo label
- WHEN about 1 s passes without a new hit
- THEN the label is hidden

#### Scenario: No new assets
- GIVEN the change applied
- WHEN `assets/` is diffed
- THEN no new art or audio files exist for the combo counter

### Requirement: Combo state in snapshots

The fighter snapshot MUST expose chain step, link window open, hitstun left, combo count dealt and hits taken in the current combo (see `gameplay-state-snapshot`). Reading them MUST NOT mutate state.

#### Scenario: Snapshot mid-combo
- GIVEN the attacker has landed 3 hits in a combo
- WHEN snapshots are taken
- THEN the attacker reports a combo count dealt of 3 and the victim reports 3 hits taken and positive hitstun left

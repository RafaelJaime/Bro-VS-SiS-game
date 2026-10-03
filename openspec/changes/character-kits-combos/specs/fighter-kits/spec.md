# Fighter Kits Specification

## Purpose

Rafael and Matilde play differently through per-character `FighterProfile` resources (movement, victim knockback scale, jumps, jab chain, per-direction attack data, air jab, recovery), with no new animation. Every value is a tunable default held in `.tres` data; balance is fixed through data, not code. Verification: Godot smoke tests under `tests/smoke/` and harness metrics (see `rl-training-pipeline`).

## Requirements

### Requirement: Profile assigned by character

Each fighter MUST receive the `FighterProfile` of its selected character at spawn (Rafael: `rafael_profile.tres`, Matilde: `matilde_profile.tres`) instead of a default `FighterProfile`. Characters without a profile MUST fall back to the default profile and report no error. The assigned kit id MUST be observable (see `gameplay-state-snapshot`).

#### Scenario: Rafael gets his kit
- GIVEN character Rafael is selected for a fighter
- WHEN the match starts
- THEN the fighter's profile is the Rafael profile and its run speed is 270

#### Scenario: Matilde gets her kit
- GIVEN character Matilde is selected for a fighter
- WHEN the match starts
- THEN the fighter's profile is the Matilde profile and its run speed is 340

#### Scenario: Mirror match
- GIVEN both fighters select Rafael
- WHEN the match starts
- THEN both use the Rafael profile independently

#### Scenario: Missing profile falls back
- GIVEN a character without a profile
- WHEN the match starts
- THEN the default profile is used and the match runs

### Requirement: Rafael kit (heavy, slow)

The initial Rafael values MUST be: run speed 270; knockback scale as victim 0.9; jump velocity -820; double jump -720; 2-hit neutral jab (step 1 4 damage, finisher 8 damage that launches); neutral single punch 10 damage (the charged grounded neutral; human-only, since the CPU and policies never charge); up punch is a heavy launcher (9 damage, endlag 0.55 s); side punch 13 damage with knockback (360, -90); down air spike 11 damage with knockback (40, 460); air jab is a single hit; link slack is tighter than Matilde's (2 to 3 ticks).

#### Scenario: Jab length
- GIVEN Rafael mashes neutral attack at 0%
- WHEN the chain completes
- THEN exactly 2 steps exist and the second launches

#### Scenario: Heavy up launcher
- GIVEN Rafael presses up plus attack and it connects
- WHEN damage and endlag are measured
- THEN damage is 9 and the attacker's endlag is 0.55 s

#### Scenario: Down air spike
- GIVEN Rafael is airborne and presses down plus attack and it connects
- WHEN the knockback is read
- THEN damage is 11 and the knockback vector is (40, 460) scaled by the victim's profile and damage %

#### Scenario: Air jab single
- GIVEN Rafael airborne with neutral attack
- WHEN he mashes attack
- THEN only one air jab hit exists per press and no second step exists

### Requirement: Matilde kit (light, fast)

The initial Matilde values MUST be: run speed 340; knockback scale as victim 1.1; jump velocity -900; double jump -780; 3-hit neutral jab (2.5, 2.5, finisher 4 that launches); neutral single punch 6 damage where the kit uses a single neutral hit; up punch is a combo launcher (6 damage, hitstun 0.55 s, endlag 0.30 s) intended to link into air follow-ups; side punch 8 damage with knockback (260, -90); down air spike 7 damage with knockback (30, 380); air jab is a 2-hit chain; link slack is looser than Rafael's (3 to 4 ticks); recovery (up special reach) is longer than Rafael's.

#### Scenario: Jab length
- GIVEN Matilde mashes neutral attack at 0%
- WHEN the chain completes
- THEN exactly 3 steps exist and the third launches

#### Scenario: Launcher into air follow-up
- GIVEN Matilde hits Rafael at low damage (0 to 30%) with the up launcher
- WHEN Matilde jumps and uses her air jab within the victim's hitstun
- THEN the air jab connects (the follow-up probe records at least one connect)

#### Scenario: Air jab two hits
- GIVEN Matilde airborne with neutral attack
- WHEN she presses attack inside the link window
- THEN the second air jab step starts

#### Scenario: Longer recovery
- GIVEN Matilde and Rafael use the up-recovery from the same off-stage position
- WHEN the vertical gain is compared
- THEN Matilde's gain is greater

### Requirement: Kits are data

Every kit value in the previous requirements MUST live in the kit resources and be changeable without editing GDScript. Movement values (run speed, jumps) MUST be read from the profile (see `fighter-movement`). Attack data MUST be read from the profile (see `smash-moves`).

#### Scenario: Edit changes behavior
- GIVEN Matilde's run speed is edited in her profile resource
- WHEN a match starts
- THEN her run speed reflects the edit

### Requirement: Kit balance targets

The two kits MUST be balanced by data: Rafael's win share MUST be within 40% to 60% in the CPU Hard mirror and in model vs model matches (both kits on both sides), and combo damage per combo MUST differ by no more than 20% between kits. Heavier kits MUST NOT gain infinite or touch-of-death combos: every safeguard in `attack-combos` applies to all kits.

#### Scenario: Win share
- GIVEN 100+ harness matches in CPU Hard mirror and model vs model with kits swapped across sides
- WHEN win share by kit is computed
- THEN Rafael's win share is between 40% and 60%

#### Scenario: Combo damage parity
- GIVEN the same harness output
- WHEN mean combo damage by kit is computed
- THEN the two values differ by at most 20%

#### Scenario: Safeguards apply to every kit
- GIVEN the infinite probe for each kit's chain
- WHEN it runs
- THEN no combo exceeds 6 hits for either kit

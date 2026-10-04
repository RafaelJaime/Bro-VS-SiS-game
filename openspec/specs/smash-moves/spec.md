# Smash Moves Specification

## Purpose

Smash-style signature moves (slice S5) using existing assets only, driven by `FighterIntent`. All numbers are tunable exported defaults.

## Requirements

### Requirement: Charged smash attack

Holding attack on the ground MUST charge for up to ~1 s (tunable). A release before the tap threshold (~0.15 s, tunable) MUST be a normal punch. On release after charging, damage and knockback MUST scale with charge (0..1). While charging, the fighter MUST glow using the existing glow texture, scaled/shown by charge. Charging MUST NOT start in the air. Charge MUST NOT conflict with pickup/throw (on `shoot`).

#### Scenario: Tap is a normal punch
- GIVEN a grounded fighter
- WHEN attack is pressed and released within the tap threshold
- THEN a normal punch occurs with no glow

#### Scenario: Full charge
- GIVEN a grounded fighter
- WHEN attack is held for 1 s or more and released
- THEN a smash hits with maximum damage/knockback, above those of a tap

#### Scenario: Glow feedback
- GIVEN charging
- WHEN charge increases
- THEN the glow sprite shows and grows with charge, and hides after release

#### Scenario: Charge cap
- GIVEN attack is held for 3 s
- WHEN released
- THEN charge equals the 1.0 cap

#### Scenario: No air charge
- GIVEN an airborne fighter
- WHEN attack is held
- THEN a normal air punch occurs, no charging and no glow

#### Scenario: Charge interrupted
- GIVEN a fighter charging
- WHEN it is hit
- THEN charge and glow are cancelled

### Requirement: Up-recovery move

A special upward burst MUST be usable once per airtime via special intent while airborne (human chord `P{N}_up` + `shoot` or `punch`, to be fixed in design). It MUST reset on landing and on being hit. It MUST have no hitbox, and reuse the jump frame and jump SFX with a pitch band. It MUST NOT make ring-outs impossible at high damage.

#### Scenario: Once per airtime
- GIVEN an airborne fighter with recovery available
- WHEN special is pressed twice
- THEN the first bursts upward and the second does nothing

#### Scenario: Reset on landing
- GIVEN recovery was used
- WHEN the fighter lands
- THEN recovery is available again

#### Scenario: Reset on hit
- GIVEN recovery was used and the fighter is airborne
- WHEN it is hit
- THEN recovery becomes available again

#### Scenario: Off-stage return
- GIVEN a fighter beside the stage edge, below the floor level
- WHEN it uses double jump and recovery
- THEN it can reach the stage

#### Scenario: Ring-out still possible
- GIVEN a fighter at high damage is launched toward a blast zone
- WHEN it uses recovery
- THEN it still crosses the blast zone and loses a stock

### Requirement: Directional punches

Up, down, and side punch variants MUST use the held aim direction plus punch, reuse the existing punch frame, and apply different knockback angles and tuning per direction. Their damage, knockback and frame data MUST come from the fighter's kit (see `fighter-kits`), not from shared exported constants. Neutral (no direction) MUST be the kit's jab chain (see `attack-combos`), or the kit's single neutral punch, which is the charged grounded neutral (a neutral held past the tap threshold) and the neutral of a kit with no chain; only human players reach it, because the CPU and policies never charge. Side MUST follow facing. The hold of attack MUST NOT chain jab steps (see `attack-combos`).
(Previously: per-direction tuning was exported on the shared profile and neutral behaved as the normal punch.)

#### Scenario: Up punch
- GIVEN aim up and attack pressed
- WHEN the punch connects
- THEN the target is launched mostly upward

#### Scenario: Down punch
- GIVEN aim down and attack pressed
- WHEN the punch connects
- THEN the target is launched at a clearly different (downward/low) angle than up

#### Scenario: Side punch
- GIVEN left/right plus attack
- WHEN the punch connects
- THEN the target is launched mostly horizontally along facing

#### Scenario: Last attack direction recorded
- GIVEN any directional punch
- WHEN the snapshot is taken
- THEN last attack direction reflects it

#### Scenario: Directional with charge
- GIVEN a charged attack with direction held at release
- WHEN released
- THEN the smash uses that direction's angle with charge scaling

#### Scenario: Kit supplies direction data
- GIVEN Rafael and Matilde each perform a side punch
- WHEN damage and knockback are read
- THEN Rafael's is 13 damage with knockback (360, -90) and Matilde's is 8 damage with knockback (260, -90) at 0% damage

#### Scenario: Neutral is the kit jab chain
- GIVEN a grounded fighter with neutral aim
- WHEN attack is pressed at the chain step window
- THEN the neutral press runs the kit's jab chain (2 steps for Rafael, 3 for Matilde)
### Requirement: Charged smash scales on kit values

The charged smash MUST keep its charge scaling (0..1) and apply it on top of the fighter's kit values for the chosen direction (damage, knockback and frame data come from the kit). A tap MUST NOT charge and MUST use the kit's jab chain (neutral) or kit direction data.

#### Scenario: Charge on kit values
- GIVEN Rafael and Matilde each fully charge a side smash
- WHEN damage is compared with each fighter's uncharged side punch
- THEN each is higher than its own uncharged value and the two differ by their kit values


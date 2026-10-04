# Delta for Smash Moves

## ADDED Requirements

### Requirement: Charged smash scales on kit values

The charged smash MUST keep its charge scaling (0..1) and apply it on top of the fighter's kit values for the chosen direction (damage, knockback and frame data come from the kit). A tap MUST NOT charge and MUST use the kit's jab chain (neutral) or kit direction data.

#### Scenario: Charge on kit values
- GIVEN Rafael and Matilde each fully charge a side smash
- WHEN damage is compared with each fighter's uncharged side punch
- THEN each is higher than its own uncharged value and the two differ by their kit values

## MODIFIED Requirements

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

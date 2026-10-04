# Explore: character-kits-combos

Mirror of Engram `sdd/character-kits-combos/explore`. Branch: `fix/shield-spam` (shield drop lag, air-punch momentum, player-colored shields, two-step HF picker, loser face portrait).

## Goal
Combos that make the two characters play differently, with one frame per animation: combos come from mechanics (hitstun, knockback, jab chains, cancels), not new animation. Existing VFX (`T_VFX_Glow_1`, `T_LeLuStar11`) may be reused.

## Current state (evidence)

- **Kits:** `game/player/fighter_profile.gd` is the kit seam, but no scene assigns a profile; `player.gd:146-147` uses `FighterProfile.new()`. Rafael and Matilde differ only in `CharacterUI` (name, color, sprites).
- **Hit pipeline:** `punch.gd` picks one of 5 variants from aim at press; `Combat.resolve` → `Hurt._enter` (`hurt.gd:34-71`): knockback × `knockback_scale × (1 + %/50)`; hitstun = `clamp(0.2 + |kb|×0.0004, 0.3, 0.9)`; post-hit invulnerability 0.5 s when hitstun ends. No per-attack cooldown or hitstun; punch cooldown 0.7 s from press, duration 0.3 s; no attack input buffer. Punch/Hurt use idle `Timer` nodes (newer timers use tick-based `CombatClock`).
- **Frame advantage (headless 60 fps, neutral at 0%):** hit f6; victim hitstun ends f25; attacker Idle f19 but can only punch at f43; victim invulnerable until f56 → no true combo at any measured %. Spam test: 3 full hits in 240 ticks.
- **Prototype:** cooldown ≤ hitstun creates chains immediately (0.25/0.25 → 7 hits in 4 s at 0%); with zero knockback it is an infinite stun-lock (15 hits/4 s); at 100% hits push out of reach after 3. Safeguards must ship with combos.
- **Schema 3:** 136 floats, no character/kit id, no hitstun-left, no chain state; `self_cd_punch` meaning changes with per-step cooldowns. Action space MultiDiscrete [3,3,2,5,2,2,2,2] already fits chains/launchers.
- **CPU:** single-press attacks gated on `cooldowns.punch ≤ 0.15`; decision intervals 0.12–0.40 s (needs a buffer to chain).

## Directions

- **A. Frame data only** (lower cooldown, per-attack hitstun, combo counter): S effort, combos identical for both characters.
- **B. Jab chains + per-attack frame data + per-character kits (recommended):** per-attack `endlag`, `hitstun`, `link_window`, active frames; jab chains (Rafael 2, Matilde 3); attack input buffer; victim combo tracking with safeguards; per-kit launchers/aerials; tick-based timers. M-L effort; needs schema 4.
- **C. B + cancels/specials:** XL, risky for RL and balance.

## Recommended design (B)

### Kits (initial values, tunable)

| Field | Rafael (heavy, slow) | Matilde (light, fast) |
|---|---|---|
| run_speed | 270 | 340 |
| knockback_scale (as victim) | 0.9 | 1.1 |
| jump / double | -820 / -720 | -900 / -780 |
| jab chain | 2 hits (J1 4 dmg, finisher 8 dmg launches) | 3 hits (2.5, 2.5, finisher 4) |
| neutral single | 10 dmg | 6 dmg |
| up | heavy launcher 9 dmg, endlag 0.55 | combo launcher 6 dmg, hitstun 0.55, endlag 0.30 |
| side | 13 dmg, kb (360,-90) | 8 dmg, kb (260,-90) |
| down air (spike) | 11 dmg, kb (40,460) | 7 dmg, kb (30,380) |
| air jab | single | 2-hit |

Link slack 2–4 frames (Rafael tighter on purpose). Jab chains naturally whiff at ~70–90% due to knockback growth.

### Anti-infinite (tick-based, on the victim)
Combo counter resets when hitstun expires without a new hit; chain cap (finisher always launches); hitstun decay from hit 4; hard cap at hit 6 (immediate invulnerability, hit launches); knockback ×1.1 per combo hit; 1.5 s time cap; keep 0.5 s post-hitstun invulnerability.

### UI / CPU
"N HIT COMBO" on the attacker's HUD (fades ~1 s, shows damage); lighter hit-stop for jabs; CPU Easy single jab, Normal chains, Hard chains + launcher follow-ups.

### AI
Schema 4 = v3 + 13 floats (149): self/opponent kit one-hot [4]+[4], chain step, link open, opponent hitstun left, combo count, hits taken in combo. Action layout unchanged. Training randomizes kits per side; small capped combo reward. Single retrain together with the shield fixes (T4 of `odd/tasks/shield-spam.md`). Schema 3 models become "older version".

### Acceptance metrics
2+ hit combos occur in CPU Normal/Hard and model matches; max combo ≤ 6 over 100+ matches; no victim > 1.5 s continuously in Hurt; Rafael win share 40–60% in CPU Hard mirror and model vs model (both kits, both sides); combo damage within 20% between kits; existing gates (shield spam, sudden death, food) hold.

## Slices
1. Tick-based Punch/Hurt timers + attack buffer. 2. AttackProfile frame data + jab chain. 3. Combo tracking + safeguards. 4. Kit resources assigned by character. 5. Combo UI + CPU combos. 6. Schema 4, kit randomization, metrics, retrain, bundle.

## Risks
Up-launcher → air follow-up may not connect (prototype first); 2–4 frame links sensitive to timers/buffer/hit-stop; balance iterations; schema-4 retrain may regress other gates; schema-3 models drop out of the picker.

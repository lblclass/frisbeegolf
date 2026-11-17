# Flight Model — v0.3 (Lift + Bank + Gravity)

Major rewrite from the v0.2 "lateral-force" model. The disc is no longer a
2D point pushed sideways — it's a banking, climbing-and-falling object whose
*orientation* (bank angle) evolves over time and whose lift gets split into
vertical support and horizontal turning.

## State (per disc in flight)

| Var | Units | Meaning |
|---|---|---|
| `disc_pos` | px | horizontal position in the world |
| `disc_vel` | px/s | horizontal velocity |
| `disc_height` | px | altitude above ground (≥ 0) |
| `disc_vz` | px/s | vertical velocity (+ up) |
| `disc_bank` | rad | current bank angle; +bank = hyzer for RHBH |

Hyzer/anhyzer at release seeds `disc_bank`; from there the *physics* moves it.

## Per-frame update (`_update_flight`)

### 1. Lift magnitude
```
lift = LIFT_BASE × (v / v_max)²  × (0.85 + 0.05 × glide)
```
Faster disc → more lift; better gliders shed lift more slowly.

### 2. Lift split — the heart of the new model
For a disc tilted at `bank` radians, the lift vector tilts with it. We decompose:
```
lift_vertical   = lift × cos(bank)            # supports against gravity
lift_horizontal = -lift × sin(bank) × LATERAL # banks the flight path
```
Flat (bank=0): all lift fights gravity, no turning.
Big bank: less vertical support (disc falls faster) AND more horizontal turning.

Forehand: `bank_eff = bank × spin_sign` where spin_sign = -1, so the lift's
horizontal component mirrors.

### 3. Gravity & vertical integration
```
disc_vz   += (lift_vertical - GRAVITY) × dt
disc_height += disc_vz × dt
```
Ground contact (`disc_height ≤ 0`) → land + roll phase.

### 4. Bank evolution (NEW — replaces direct lateral forces)
Three torques act on the bank angle:
```
turn_torque   = -turn  × (v/v_max)²        × TURN_TORQUE  × arc_factor
fade_torque   =  fade  × (1 - v/v_max)²    × FADE_TORQUE  × arc_factor
restore_torque = -bank × HYZER_RESTORE × (1 - commit)
disc_bank += (turn + fade + restore) × dt
```
- **Negative `turn`** (understable) pushes bank *toward anhyzer* at speed.
- **Positive `fade`** pushes bank *toward hyzer* at low speed.
- Restore torque pulls bank toward 0 at moderate angles; **suppressed at >0.6 rad**
  (`commit` factor) so spike-hyzer truly commits.
- `arc_factor` zeroes torques at putt power so short throws stay straight.

So turn/fade no longer apply a direct sideways force. They *tilt the disc over
time*, and §2 then converts that tilt into a curved path.

### 5. Wind
Unchanged from v0.2:
```
disc_vel += wind × (0.4 + (1 - speed_ratio) × 0.8) × dt
```
Affects late flight (slow speed) more.

### 6. Drag
```
drag = lerp(0.55, 0.18, glide/6) + |bank| × 0.45
disc_vel *= exp(-drag × dt)
disc_vz  *= exp(-0.25 × dt)        # mild vertical damping
```
Big bank → more induced drag → shorter flight.

## Why this is more truthful

The 5 emergent behaviors we wanted:

1. **Hyzer-flip works automatically.** Throw an understable disc (turn = -2) on
   a hyzer release. As it speeds along, `turn_torque` pushes bank → 0 → negative.
   The disc visibly *flips*. Once flat, lift is fully vertical → maximum glide.
   At slow speed, `fade_torque` finally pulls it back. Long, beautiful S.

2. **Spike hyzer dies fast.** Big bank → lift_vertical is small → gravity wins
   → disc lands quickly and locally. Roll damping further kills any roll-out.

3. **Flat throws fly the farthest.** Bank ≈ 0 → 100% vertical lift → longest
   time in air → most distance.

4. **S-curves "fail to develop" if there's no air time.** A low-power throw
   doesn't have time for fade to swing the bank back before height runs out.
   Just like real disc golf — putts and approaches barely curve.

5. **Big anhyzer = drops right.** The disc carves right (horizontal lift) but
   also drops because the vertical lift is reduced. If thrown hard, the
   negative `fade_torque` (BH: actually positive bank-direction torque) catches
   it eventually — that's the flex shot.

## Coordinate / sign conventions

- Screen is +X right, +Y down. Player at lower-left throws toward upper-right.
- `right_lateral = (-forward.y, forward.x)` is "player's right" relative to flight.
- **Positive `disc_bank`** = hyzer for RHBH = banks LEFT during flight.
- For FH (spin_sign = -1), the bank's lift direction inverts, so a +bank
  release banks RIGHT.

## Known simplifications (intentional)

- **No gyroscopic precession.** Real discs' bank torques produce 90°-rotated
  responses. We elide this; players already think "BH curves left, FH curves
  right" — adding precession would invert that learned intuition.
- **No pitch / nose angle.** Only roll-axis bank is modeled.
- **Wind is just velocity addition.** Real headwind raises effective speed
  → more lift → flips understable discs harder. We don't model this yet.
- **Trees are 2D circles**, not 3D — they block any height. A future patch
  could let high-altitude discs sail over short trees.
- **Bank during roll is reset to 0** (the disc is "on its edge" rolling). Roll
  speed is reduced by landing bank (spike-hyzer barely rolls).

## Tuning knobs (where to twiddle)

If feel needs adjusting:
- **Discs fly too short / too long** → `LIFT_BASE` (320) or speed×glide multipliers
- **Full Q/E shortens distance too much** → reduce bank-drag coefficient (the `* 0.15` on `bank_norm * bank_norm`)
- **Full Q/E doesn't curve enough** → bump `LIFT_LATERAL_SCALE` (1.7)
- **Hyzer-flip doesn't happen** → bump `TURN_TORQUE` (2.6) or reduce `HYZER_RESTORE`
- **Spike hyzer rolls too much** → reduce roll's `bank_damp` denominator
- **S curves don't return** → bump `FADE_TORQUE` (3.4)
- **Putts curve too much** → tighten `arc_factor` thresholds (currently 0.15/0.55)
- **Discs land too quickly** → reduce `GRAVITY` (260)

## What still uses v0.2-style math

- Drag (still exponential decay per-frame).
- Wind (still pure horizontal velocity add).
- Ground roll (no air dynamics during roll, just friction).
- Tutorial-mode predicted trajectory uses the same `_simulate_flight()` so what
  you see is what you'll get (modulo jitter, which adds the scatter ring).

# Course Design — 9-Hole Layout for v0.3

This is the concrete 9-hole course we'd build once v0.3 mechanics ship.
Each hole exists to **teach or test one specific skill** introduced by the
new mechanics, and difficulty ramps gradually.

> Distances are logical map units (1 unit ≈ 1 real-world meter).
> "Skill tested" = the mechanic the hole exists to exercise.

## Hole 1 — "Welcome Mat" · Par 3 · 95m

```
TEE ───────────────────────── BASKET
       (wide open field)
```

- **Skill**: Throwing basics. Any disc, any hand can reach.
- **Layout**: Wide open, no obstacles, calm wind.
- **Design intent**: First impression. Player gets an Ace or Birdie and feels
  the game.

## Hole 2 — "Tree Tunnel" · Par 3 · 110m

```
TEE ─[trees]─[trees]─[trees]─ BASKET
     [trees]──corridor──[trees]
```

- **Skill**: Mid-range straight throw; disc selection (Mid is right, Driver
  will fade left into trees).
- **Layout**: Narrow ~80m corridor of trees forming a tunnel. Walls of trees
  on both sides.
- **Design intent**: Punish anhyzer (drifts right into trees) and over-stable
  drivers (fade left into trees). Reward straight Mid or flat hyzer-flip.

## Hole 3 — "Dogleg Left" · Par 4 · 175m

```
                    [trees]──BASKET
                    [trees]
                    [trees]
TEE ────long open──[trees]
```

- **Skill**: Shaping a hyzer curve OR laying up + putting.
- **Layout**: Straight 100m, then sharp left turn at a tree wall, basket 75m
  further. No straight line of sight.
- **Design intent**: Reward huck + hyzer-flip from understable disc. Casual
  players can lay up to the corner with a Mid, then approach.

## Hole 4 — "Water Carry" · Par 3 · 120m

```
TEE ── ~~~ water ~~~ ── BASKET
                   ░░░ fairway ░░░
```

- **Skill**: Distance management + risk-reward + headwind compensation.
- **Layout**: 60m lake between tee and basket. Lake from x=70m to x=110m.
- **Wind**: Mild headwind (slows discs ~10%).
- **Design intent**: First water hazard. A weak throw plops in the water (+1).
  Forces players to pick a confident disc and commit. Encourages picking
  Driver despite the wind.

## Hole 5 — "Island Green" · Par 3 · 130m

```
TEE ─────fairway───── ~water~ [BASKET] ~water~
                              tiny island
```

- **Skill**: Putt finesse + basket spit-out awareness.
- **Layout**: Basket on a 25m × 25m island surrounded by water.
- **Design intent**: Hot drives that spit out land in water (+2 total!). Forces
  players to throttle down to Putt or Mid power even from 130m — or play it
  safe and lay up in front of the water (+1 from chip-in).

## Hole 6 — "Hyzer Around" · Par 4 · 195m

```
                            BASKET
                          [trees]
                        [trees]
                      [trees]
TEE ────────────────[trees]
```

- **Skill**: Carved hyzer shot, anhyzer/flex variant for FH players.
- **Layout**: Wall of trees curving 90° around the basket. Straight throw
  hits trees; need a sustained left-curving hyzer line.
- **Design intent**: Showcase that BH hyzer = FH anhyzer (visually mirrored).
  Players who learned forehand on Hole 3 get to use it here.

## Hole 7 — "Rough Approach" · Par 3 · 100m

```
TEE ── fairway ─░░░ rough ░░░── BASKET
              ░░░ rough ░░░
        narrow fairway corridor (~30m wide)
```

- **Skill**: Landing-zone control + roll management.
- **Layout**: Open tee, narrow fairway corridor to the basket. Rough on both
  sides. Disc landing in rough stops within ~5m; on fairway it rolls 20-40m
  depending on landing angle.
- **Design intent**: Teaches the roll mechanic. A flat throw that lands on
  fairway can roll into the basket; a spike-hyzer lands dead but accurate;
  a throw that lands in rough is short and out of position. Forces players
  to think about *where the disc first touches the ground*, not just where
  it ends up.

## Hole 8 — "Crosswind Gauntlet" · Par 4 · 165m

```
                  ←←← wind (strong crosswind)
TEE ──── ░░░ rough ░░░ ──── BASKET
         ░░░ rough ░░░
         narrow fairway
```

- **Skill**: Wind compensation + disc stability choice.
- **Layout**: Narrow 25m fairway with rough on both sides. Strong crosswind
  pushes discs into rough (slows landing, possible OB).
- **Design intent**: Force aiming upwind. Stable discs (Driver) hold line
  better than understable ones (Mid with -1 turn).

## Hole 9 — "The Signature" · Par 5 · 285m

```
                           BASKET
                          ░░░░░░░
                        ~~water~~
                     [trees]    
TEE ─long open─[trees]─dogleg right─~water~─green
```

- **Skill**: Everything.
- **Layout**: 
  - **Leg 1** (0–120m): wide-open drive, light tailwind.
  - **Leg 2** (120–200m): dogleg right around a tree cluster (FH-friendly OR a
    smart anhyzer hyzer-flip with BH).
  - **Leg 3** (200–285m): water carry to a small fairway green, possible
    spit-out from the basket.
- **Design intent**: Signature finale. Many shot sequences possible. Tests
  pace, disc selection per leg, both hands.

---

## Holes-to-Mechanics Coverage Matrix

| Hole | New mechanic tested |
|---|---|
| 1 | Drag basics, mode auto-select (mid) |
| 2 | Disc selection × narrow corridor |
| 3 | Huck mode, hyzer curve, lay-up strategy |
| 4 | Water penalty, headwind |
| 5 | Putt mode, basket spit-out, risk-reward |
| 6 | BH hyzer = FH anhyzer mirror |
| 7 | Surface roll mechanic, landing-zone control |
| 8 | Crosswind drift, rough |
| 9 | Multi-leg planning, all mechanics |

## Hole Authoring Format

For implementation, each hole becomes a small data structure:

```gdscript
class Hole:
    var name: String
    var par: int
    var bounds: Rect2          # logical world rect for this hole
    var tee: Vector2
    var basket: Vector2
    var wind: Vector2
    var obstacles: Array       # [{ type, pos, radius/rect }]
    var water_zones: Array     # [Polygon2D]
    var rough_zones: Array     # [Polygon2D]
    var fairway_hint: Polygon2D
```

This pushes us to refactor the current per-hole data into a cleaner format.
Probably worth a `Hole.gd` resource class plus a JSON or .tres file per hole
so non-programmers (or future-us) can iterate on layout without touching code.

## Difficulty Curve

Expected first-time scores from a beginner who completed the tutorial:

| Hole | Par | Expected | Skilled |
|---|---|---|---|
| 1 | 3 | 3 | 2 |
| 2 | 3 | 4 | 3 |
| 3 | 4 | 5 | 3 |
| 4 | 3 | 4 | 3 |
| 5 | 3 | 5 | 3 |
| 6 | 4 | 5 | 3 |
| 7 | 3 | 4 | 3 |
| 8 | 4 | 5 | 4 |
| 9 | 5 | 7 | 5 |
| **Total** | **32** | **42 (+10)** | **29 (-3)** |

Target: a new player breaks 40 by their 3rd full round.

## Variants & Replay Value

To stretch a 9-hole course's replayability:

- **Wind variants**: each launch reshuffles wind direction on holes 1, 4, 5, 8.
- **Tee positions**: easy / medium / pro (closer / further / different angle).
- **Daily seed**: same layout, deterministic random wind/tee → leaderboard fair.

These are quick wins for v0.3.5 or v0.4.

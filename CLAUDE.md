# CLAUDE.md — Project Context

This file is auto-loaded by future Claude Code sessions in this directory.

## What This Project Is

A 1-week disc-golf game prototype, built with **Godot 4.3** in **GDScript**.
Top-down 2D, custom parametric flight model. Owner is a game-dev beginner;
collaboration model is "AI writes code + writes design docs, human plays and
gives feedback".

Started 2026-05-24.

## Current State (v0.3 Stage 1)

- 3 reworked holes with new mechanics (Open Meadow / Wooded Dogleg / Hazards).
- **Power tiers**: PUTT / MID / HUCK auto from drag, or forced via Z/X/C, V=auto.
- **Tier × Hand matrix** for accuracy and range — captures real-world rules:
  - PUTT: BH dominant accuracy (90% real-world stat)
  - MID: equal hands
  - HUCK: BH longest, FH more accurate
- **Visible release offset** for BH/FH (disc shifts to player's left/right).
- **Disc tilt + horizon gauge** for hyzer visualization.
- **Predicted trajectory ghost** (Pro Mode toggles off via P).
- **Post-landing roll**: hyzer-damped initial roll speed × surface friction.
- **Surfaces**: fairway / short grass / rough / sand / water (penalty).
- **Basket spit-out**: hot drives can rim out.
- Full state machine + tutorial cards (5 cards updated for v0.3 vocab).
- All gameplay still in `scripts/Main.gd` (single file, ~1400 lines).

## Stage 2 (not yet implemented)

- 9-hole course (see `docs/COURSE_DESIGN.md`).
- Camera follow + larger logical world per hole (e.g. 2400×1400).
- Mini-map.
- Window resize support.
- Tutorial polish (more pages, animated demos).

## Read These First

In order:
1. [`README.md`](README.md) — quick start and controls.
2. [`docs/DESIGN.md`](docs/DESIGN.md) — vision, scope, what we're NOT building.
3. [`docs/PHYSICS.md`](docs/PHYSICS.md) — flight model formulas and tuning knobs.
4. [`docs/ROADMAP.md`](docs/ROADMAP.md) — 7-day plan + status + decisions log.

## Architectural Conventions

- **One scene file** (`Main.tscn`), procedural rendering via `_draw()` in `Main.gd`.
  Avoid hand-edited `.tscn` until needed.
- **Godot 2D coords**: +X right, +Y down. "Right" perpendicular to flight is
  `(-forward.y, forward.x)`.
- **No external assets in v0.1**. All visuals via `draw_*` primitives. When art
  comes in, drop CC0 PNGs in `assets/` and reference via `preload`.
- **Sign convention**: assume right-hand backhand (RHBH). Positive `hyzer_angle` =
  disc banks left. To support forehand, mirror turn/fade signs in physics.

## Decisions Already Made (don't relitigate without reason)

- Top-down 2D, not 3D. ([DESIGN.md](docs/DESIGN.md))
- Custom flight model, not real aerodynamics. ([PHYSICS.md](docs/PHYSICS.md))
- Single-file gameplay until Day 3 refactor.
- No online multiplayer this week.

## How to Run / Test

User runs Godot manually on macOS — see `README.md`. Claude cannot launch the
editor headlessly without extra setup; rely on user playtest feedback.

When changing physics, mention which tuning knob in `PHYSICS.md` was touched
so the user knows what to feel for.

## Work Style With This User

- Build incrementally; commit early to a "playable" state each day.
- After each batch of changes, give the user a short list of *specific things to
  feel for* during playtest (not "tell me what you think"). Example: "throw the
  driver flat — does it carve right early then fade left at the end?"
- Update `docs/ROADMAP.md` decision log when scope or direction changes.

## Known Issues / Hacks

- Trees are circular hard stops; no deflection physics.
- No height dimension — disc is a 2D point. Can't model overhead throws or skips.
- Out-of-bounds is a clamp + force-land, not a proper penalty system.
- Single hole only; no scorecard or course flow.

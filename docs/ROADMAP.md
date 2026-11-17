# 1-Week Roadmap

Timezone reference: started 2026-05-24 (Sunday).

Status legend: ✅ done · 🚧 in progress · ⬜ not started · ❌ cut.

## Day 1 — Skeleton (2026-05-24)

- ✅ Godot 4 project structure (`project.godot`, `Main.tscn`, `scripts/`).
- ✅ Parametric flight model (hyzer + turn + fade + drag).
- ✅ Drag-release input + hyzer angle keys + disc switch.
- ✅ One hand-placed hole with trees, tee, basket.
- ✅ Stroke counter, complete-hole banner with par feedback.
- ✅ Design docs: `DESIGN.md`, `PHYSICS.md`, this file.

**Playtest target**: user opens project, throws ~10 discs across all 3 types,
reports which feel best/worst and what's confusing.

## Day 2 — Feel pass (2026-05-24, same day push to v0.2)

- ✅ State machine: Title → Tutorial → Playing → Hole Complete → Round Complete.
- ✅ 3-hole mini-course with distinct character (open / wooded / corridor).
- ✅ Backhand vs Forehand: distance + jitter + mirrored spin.
- ✅ Wind per hole, HUD indicator, late-flight bias.
- ✅ 5-step interactive tutorial.
- ✅ Procedurally synthesized SFX (throw, chain, land, tree, click) — zero asset files.
- ✅ Scorecard in HUD + final scorecard screen.
- ⬜ Disc rotation animation, basket chain particles.
- ⬜ OB zones as a proper penalty (currently just clamp).

## Day 3 — Course

- ⬜ Refactor `Main.gd`: split `Disc.gd` (physics), `Hole.gd` (level data), `Game.gd` (round state).
- ⬜ Hole data structure: tee, basket, par, obstacles, OB polys, wind.
- ⬜ Build 9 holes total. Mix of: open, dogleg-left, dogleg-right, wooded, long, putt-only.
- ⬜ Hole-to-hole flow: scorecard between holes.

## Day 4 — Throws

- ⬜ Forehand toggle (mirror turn/fade signs).
- ⬜ Putt mode for short range (different power curve).
- ⬜ Disc bag: expand to ~6 discs (overstable/understable variants of each class).

## Day 5 — Polish

- ⬜ Main menu, course select, settings (mouse sensitivity, sound).
- ⬜ Scorecard view between holes + final.
- ⬜ Replay last throw button.
- ⬜ Particle effects on landing / chain-out.

## Day 6 — Polish + content

- ⬜ Second 9-hole course (different theme: tighter wooded vs open meadow).
- ⬜ Wind variation per hole.
- ⬜ Persistent best-score (Godot's `user://` save).

## Day 7 — Ship

- ⬜ Bug bash from playtest log.
- ⬜ Export macOS / Windows / Web builds.
- ⬜ itch.io page draft.
- ⬜ Share with friends, gather feedback.

## Cut List (won't do this week)

- ❌ Online multiplayer.
- ❌ Custom course editor.
- ❌ 3D upgrade.
- ❌ Disc unlock progression.
- ❌ Real-time wind gusts during flight.

## Decisions Log

- **2026-05-24**: Picked top-down 2D over first-person 3D. Reason: 3D animation
  cost too high for 1 week. ([DESIGN.md](DESIGN.md))
- **2026-05-24**: Picked custom 2D lateral-force model over real aerodynamics.
  Reason: hits 80% of the "feel" at 5% of the dev cost. ([PHYSICS.md](PHYSICS.md))
- **2026-05-24**: All gameplay in single `Main.gd` for v0.1 — refactor on Day 3
  once we know which abstractions actually matter.

# Disc Golf (Godot 4 Prototype)

A one-week disc-golf side project. Top-down 2D, parametric disc-flight model
that approximates real disc behavior (Speed / Glide / Turn / Fade + hyzer angle).

## Quick Start (macOS)

1. Download **Godot 4.3 (or 4.4) — Standard** for macOS:
   <https://godotengine.org/download/macos/>
2. Unzip and drag `Godot.app` into `/Applications`.
3. First launch: macOS may block it. Right-click `Godot.app` → **Open**, or
   System Settings → Privacy & Security → "Open anyway".
4. Open Godot → **Import** → pick the `project.godot` in this folder.
5. Hit **F5** (or the play button top-right). On first run Godot may ask to set
   the main scene — pick `Main.tscn`.

## Controls (v0.3)

| Action | Key / Mouse |
|---|---|
| Begin / next hole / dismiss | Click or `SPACE` |
| Aim & throw | Left-click drag from disc → release |
| Hyzer (bank left) / Anhyzer (right) | `Q` / `E` |
| Select Putter / Mid / Driver | `1` / `2` / `3` |
| Toggle Backhand / Forehand | `F` |
| **Force PUTT / MID / HUCK mode** | `Z` / `X` / `C` |
| **Reset to AUTO mode** | `V` |
| **Toggle Pro Mode** (hide predicted curve) | `P` |
| Reset hole | `R` |
| Back to title | `ESC` |
| Skip tutorial | `S` |

Yellow dashed line = aim direction. **Cyan curve = predicted flight path** (off in Pro Mode).
The horizon bar above the disc visualizes hyzer tilt. The disc icon itself tilts as an ellipse.

## What's in v0.3 (Stage 1)

- **Power tier system**: drag length picks `PUTT` / `MID` / `HUCK` automatically; force-override with Z/X/C.
- **Backhand/Forehand × Tier matrix**: BH-Putt is most accurate, FH-Huck is most accurate at long range. Real-world calibration.
- **Visible release point**: a player marker shows facing; disc sits to your left (BH) or right (FH).
- **Hyzer visual upgrade**: disc icon tilts as an ellipse, with a horizon-style gauge above it.
- **Predicted flight ghost**: cyan curve runs the actual sim forward while you aim. Toggle off via Pro Mode (`P`).
- **Post-landing roll**: disc keeps moving after flight ends. Spike-hyzer = no roll; flat = long roll.
- **Surfaces**: fairway (normal), short grass, rough (heavy friction), sand (almost no roll), water (penalty).
- **Water penalty**: +1 stroke, disc drops at last in-bounds position.
- **Basket spit-out**: hot drives have up to ~60% chance to bounce out (rim hit). Putts always catch.
- 3 reworked holes featuring fairways, rough, sand, water.

## Project Layout

```
frisbeegolf/
├── project.godot          # Godot project config
├── icon.svg               # App icon
├── Main.tscn              # Single root scene (procedural rendering)
├── scripts/
│   └── Main.gd            # All gameplay (input + physics + render)
└── docs/
    ├── DESIGN.md          # Vision, scope, gameplay design
    ├── PHYSICS.md         # Flight model & tuning notes
    └── ROADMAP.md         # 1-week plan & status
```

See `CLAUDE.md` for context any future AI session needs to pick up the project.

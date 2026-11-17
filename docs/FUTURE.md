# Future Direction — Roadmap Beyond v0.3

Once v0.3 ships with the redesigned core mechanics + 9 holes, the game has
a solid foundation. Where can it go from here? Ranked roughly by *value
delivered per effort*.

---

## Tier 1 — Polish & Depth (v0.3.x — Weeks 2-3)

These don't add new pillars, but make the existing game shine. Most are
small, all are noticeable.

### 1.1 Audio depth (1-2 days)
- Ambient layer per environment (forest birds, lake water lap, wind).
- Wind-strength-modulated whoosh during flight.
- Distinct chain sounds for "clean catch" vs "rim out" vs "wedge in".
- Footstep / approach SFX when player avatar moves between throws.

### 1.2 Visual polish (1-2 days)
- Disc rotation animation (spin speed proportional to throw power).
- Basket chains as animated lines that pulse on hit.
- Particle effects: dust on landing, water splash on OB, sparks on rock.
- Trail rendered as a soft gradient instead of dashed line.

### 1.3 Expanded disc bag (1 day)
Currently 3 discs (Putter / Mid / Driver). Expand to ~8 spanning the real
flight-number space:

| Disc | S | G | T | F | Vibe |
|---|---|---|---|---|---|
| Putter (Aviar) | 3 | 4 | 0 | 1 | Default putter |
| Approach (Zone) | 4 | 3 | 0 | 3 | Overstable approach |
| Mid neutral (Buzzz) | 5 | 5 | -1 | 1 | Current Mid |
| Mid stable (MD3) | 5 | 5 | 0 | 2 | Wind / approach mid |
| Fairway flippy (Leopard) | 7 | 5 | -2 | 1 | Hyzer-flip line driver |
| Fairway straight (River) | 7 | 7 | -1 | 1 | Long straight glider |
| Distance overstable (Firebird) | 9 | 4 | 0 | 3 | Wind driver |
| Distance flippy (Wraith) | 11 | 5 | -1 | 3 | Max range driver |

Players choose 5 to bring per round (bag-building decision).

### 1.4 Statistics & feedback (1 day)
End-of-round screen shows: fairway-hit %, OB count, average shot length,
longest throw, par save %. Compare against best previous round.

### 1.5 Local hot-seat multiplayer (1 day)
2-4 players, same machine, alternating turns. Players type names on a
pre-round screen. Per-hole scoreboard side panel.

### 1.6 Pro mode toggle (half day)
Setting: hide predicted-trajectory preview, hide power meter %. For
players who want a harder challenge after mastering the basics.

---

## Tier 2 — New Content (v0.4 — Month 1)

### 2.1 Multiple courses (2-3 days each)
Themed environments, distinct biomes:
- **Forest** (current 9 holes — wooded, mixed obstacles)
- **Park** (open, water features, paved paths as OB)
- **Mountain** (elevation, talus-rock fields, high winds)
- **Beach** (sand OB, wide open, strong sea breeze)
- **Urban** (walls as reflective obstacles, narrow corridors)

Each course = its own theme + tileset + obstacle palette + 9 hand-designed
holes. Targets 5 courses × 9 holes = 45 holes total.

### 2.2 Elevation / 2.5D upgrade (3-5 days)
Currently the disc is a 2D point. Add a `height` dimension to the flight
model with simple ballistics:
- Player picks release angle (low / mid / high) — affects glide vs. drop
- Trees have **canopy heights** — low throws blocked, high throws skim over
- Hills affect roll-out distance
- Spike hyzer makes sense (sharp drop)

This is a significant physics extension but stays in 2D rendering — just
add height as a "depth" parameter with shadow + size scaling for visuals.

### 2.3 Course editor (3-5 days)
Player can place tee, basket, obstacles, water, rough on a blank canvas.
Save as `.hole` file. Share files between players (text format).

### 2.4 Achievement system (1-2 days)
50 achievements covering: first ace, first eagle, 100 throws, hit a tree, 
landed in water 3 times in one round, completed all courses, etc. Pure
positive reinforcement, no FOMO.

---

## Tier 3 — Systems (v0.5 — Months 2-3)

### 3.1 Persistent profile (1 day)
- Save best scores per course.
- Save disc bag preference.
- Save Pro Mode preference.
- Use Godot's `user://` filesystem.

### 3.2 Daily challenge (2 days)
Same layout for everyone that day. Deterministic wind seed. Submit score
to a (local-only first) leaderboard. Replayable until midnight.

### 3.3 Online leaderboards (3-4 days)
Backend: tiny Go/Python server with a sqlite db. Submit round JSON, get
back rank. No accounts at first — just a chosen name + a guid in profile.

### 3.4 Tournament mode (3-4 days)
- Choose a course
- Set number of players (1-8 hot-seat, or vs CPU)
- Multi-round with cut after round 1
- Cumulative scoring
- Final leaderboard

### 3.5 AI opponents (2-3 days)
Simulated bots with skill levels:
- **Beginner**: random hand, ±15° aim, picks Mid 70% of the time
- **Pro**: picks correct disc/hand for hole, ±2° aim, putts from 25m+
The skill ceiling is implemented by tuning aim noise and decision tree.

---

## Tier 4 — Big Reaches (v1.0 — Months 4-6)

These would meaningfully change the game's scope and require real planning.

### 4.1 Real 3D upgrade
- 6-DOF disc flight (Hummel-style aero) in actual 3D
- 3D courses with elevation, trees-as-meshes, water reflections
- 3D camera that follows disc with cinematic angles
- This is essentially a rewrite. Worth it only if the 2D version proves a
  hit.

### 4.2 Online multiplayer (live)
- Lobby system, room codes
- Synchronized rounds, see opponents' throws in near-real-time
- Spectator mode
- Voice chat optional
- Requires server infrastructure for matchmaking

### 4.3 Career / progression mode
- Player starts with a beginner bag, earns discs through play
- Sponsor tournaments unlock by skill rating
- Stat tracking influences future opponent difficulty
- This is the "game" inside the game — gives long-term motivation

### 4.4 Steam / itch / mobile release
- Polished launch, trailer, press kit
- Mobile control rework (touch drag for aim, holds for hyzer)
- Steam Workshop for community courses
- Pricing: $5-10 indie tier OR free + cosmetic DLC

---

## Crazy / Optional Creative Directions

Things that could be fun but aren't on the critical path:

- **Story mode**: characters, dialog, a campaign across 5 courses with
  rivals and tournaments. Disc-golf "Mario Tennis Aces".
- **Trick-shot challenge mode**: "Land in zone X after exactly 2 tree
  bounces" — puzzle-game energy.
- **Asynchronous PvP**: "challenge a friend's recorded round" — they throw
  their best, you try to beat them shot-by-shot, both see ghost trails.
- **Procedural courses**: nightly generated layouts with shared seed for
  competitive play.
- **Disc-golf-meets-pinball hybrid**: ridiculous holes with windmills,
  jumps, bouncers — pure arcade fun, not realism.
- **VR port**: real arm swing, real aiming. Niche but devoted audience.

---

## Decision Framework for "What's Next"

For each candidate feature, score 1-5 on:
- **Player value** — how much does it improve the experience?
- **Effort** — how many days to ship a polished version?
- **Maintenance burden** — does it complicate ongoing dev?
- **Strategic value** — does it unlock further features?

Pick the highest **value / (effort × burden)**. The Tier 1 polish items mostly
win on this metric early. Don't jump to Tier 4 (3D, online) until the 2D game
has proven engagement.

## Personal Recommendation

If we ship v0.3 successfully and the user-base is small but enjoying it:

**Next 4 weeks**: Tier 1 (polish + disc bag + hot-seat MP + stats).
**Months 2-3**: One more 9-hole course in a different theme + elevation.
**Month 4+**: Course editor (unlocks community content, biggest leverage).
**Year 2 only if engagement is real**: 3D upgrade + online.

Most disc-golf games die in the "almost-3D-but-bad" valley. We should stay
distinctly 2D and over-deliver on level design, *then* maybe 3D.

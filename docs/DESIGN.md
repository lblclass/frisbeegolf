# Disc Golf — Game Design

## Vision

A bite-size disc-golf game where the **fun comes from disc selection + release angle**,
not from twitch input. The player should feel the difference between throwing an
overstable putter on a hyzer line and an understable driver flexed through a gap.

Target session: **5–10 minutes** for a 9-hole round.
Target player: anyone who can use a mouse — no disc-golf knowledge required, but
players who *do* know the sport should immediately recognize the flight shapes.

## Why Top-Down 2D

Three options were considered:

| Option | Why considered | Why rejected for v1 |
|---|---|---|
| Top-down 2D | Smallest art surface, fastest iteration | (chosen) |
| First-person 3D power-bar | Visceral feel | 3D scenes / animation cost too high for 1 week |
| True 3D physics sim | Most authentic | Disc aerodynamics + 3D courses = months of work |

Top-down keeps the design surface tight and lets us spend the AI-augmented dev
budget on **flight feel** and **level design**, which is where the fun lives.

## Core Loop

1. Stand on the tee (or current lie).
2. Pick a disc (1/2/3).
3. Adjust hyzer angle (Q/E).
4. Drag-release to set direction + power.
5. Watch the disc carve, fade, hit a tree, or chain in.
6. From wherever it stops, repeat until in basket.

## Pillars

- **Readable physics.** Every disc behavior should be explainable post-hoc:
  "Driver fades hard at the end, that's why it pulled left into the trees."
- **One-shot input.** No active flight control, no spamming. Commit and watch.
- **Forgiving for newcomers, deep for sport players.** Default flight is intuitive;
  hyzer + understable disc = hyzer-flip is rewarded by a longer straight line.

## Anti-Pillars (Things We Are NOT Building)

- Real-time aerodynamics with pitch/roll/yaw.
- 3D character animation.
- Online multiplayer.
- Disc unlock economy / progression grind.
- Frame-perfect timing inputs (no "hit the green zone").

## Disc Inventory (v1)

Speed numbers are loosely based on PDGA flight-rating conventions.

| Disc | S | G | T | F | Use |
|---|---|---|---|---|---|
| Putter | 3 | 4 | 0 | 1 | Approaches, in-circle |
| Mid    | 5 | 5 | -1 | 1 | All-purpose, default |
| Driver | 9 | 5 | -2 | 2 | Tee shots, long fairways |

A negative `T` disc thrown flat at high speed will visibly turn right (RHBH);
a positive `F` disc at low speed will hook left. Hyzer release biases the early
flight; the disc's natural tendencies take over as it slows.

## Scope Plan (1 Week)

- **Day 1–2 (DONE in v0.1)**: Project skeleton, flight model, single hole, basic UI.
- **Day 3**: Tune flight feel based on user playtest. Add wind. Add OB zones.
- **Day 4**: Build 8 more holes (9-hole course). Add forehand option.
- **Day 5**: Sound effects, hit-chain SFX, basket animation.
- **Day 6**: Polish — main menu, scorecard, "next hole" flow.
- **Day 7**: Bug fix, package, share with friends.

## Open Questions

- Forehand vs backhand: is it worth the input complexity in 2D, or is selecting a
  disc with reversed turn rating enough?
- Putt mechanic: should sub-10m putts use a different input (timing meter)?
- Trees: hard stop (current) vs deflection physics?

These get resolved by playtest feedback, not on paper.

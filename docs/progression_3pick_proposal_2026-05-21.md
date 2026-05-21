# Progression Choice — 3-Pick Replacement for Sector Map

**Status:** proposal for review (2026-05-21). Mockup dev screen lives at
`scenes/dev/progression_mockup.tscn` + `scripts/dev/progression_mockup.gd`.

---

## Goal

Replace the current sector map V2 (12-row grid with forward-only edges) with
a tighter linear progression: after each combat/event, the player is shown
**three node choices** and picks one. A persistent **Sector Progress bar**
sits underneath and fills as the player progresses, signalling distance to
the sector boss.

This trades the sector map's geographic-feel exploration for a sharper
moment-to-moment decision cadence: fewer choices, each one weightier, and
the boss is always a known distance away.

---

## Model

### Sector length

- **6 nodes per sector** (default; tunable per-sector via SectorSpec).
- Final node is always **Boss** — non-negotiable, no other choices on the
  last pick.
- Penultimate node bias: **at least one Outpost in the choices** (so the
  player can stock up before the boss).

### Node types in the pool

Reusing the existing sector_map_v2 node enum so combat/event handlers stay
intact:

| Type | Combat? | Bounty? | Notes |
|---|---|---|---|
| `COMBAT_NORMAL` | yes | yes | Standard wave; default flavour |
| `COMBAT_ELITE` | yes | high | Tougher wave, mini-boss style enemy, fewer chaff |
| `HAZARD_MINEFIELD` | hazard | yes | Existing minefield level |
| `HAZARD_ASTEROIDS` | hazard | yes | Existing asteroid field level |
| `OUTPOST` | no | spend | Shop; weapon edits, part swaps, super refill |
| `SIGNAL_EVENT` | no | varies | Existing signal-event picker (Freespace Miner, etc.) |
| `BOSS` | yes | huge | Always last node |
| `TREASURE` (new) | no | gain | One-shot bounty boost or guaranteed Part roll |

### Pick generation

Each pick presents **3 distinct types** drawn from the pool, weighted by
current sector position:

- **Position 1 (sector start):** combat-heavy mix. 70% combat (normal),
  20% hazard, 10% signal event. No Outpost (force first node to be action).
- **Position 2–4 (mid-sector):** balanced. 50% combat (normal/elite),
  25% hazard, 15% outpost, 10% signal event / treasure.
- **Position 5 (penultimate):** **forced Outpost in slot 1** + 2 random
  combat/event picks. Player can always re-arm before the boss.
- **Position 6 (final):** Boss only, no choice — fades the cards out and
  transitions straight into the boss intro.

### Repetition avoidance

Within a single sector, no node type appears in two consecutive picks unless
the pool is exhausted (forces variety without complex distance math).

### Persistence

Each sector starts with `Run.sector_progress = 0` and `Run.sector_total = 6`.
On node clear, `sector_progress += 1`. Save/load via `Run`'s existing
snapshot mechanism — same shape as current `sectors_cleared`.

---

## UI shape

Three large cards in a horizontal row, occupying the center 60% of the
playfield. Each card:

- **Top:** Icon (combat/hazard/outpost/etc. — reuse `enemy_codex`'s holo
  preview shader for thematic cohesion).
- **Mid:** Type label ("ELITE COMBAT", "OUTPOST", "MINEFIELD").
- **Bottom:** One-line flavour description + reward hint
  ("+300 bounty", "Shop access", "+1 Part roll").

Hovering a card highlights it (accent glow), clicking it transitions to that
node's scene.

**Sector Progress bar** below the cards:
- Pill-shaped, ~80% of viewport width, ~12 px tall.
- Filled portion = `progress / total`. Animates over ~400ms when the player
  picks a card.
- Boss icon pinned at the right end of the bar so the destination is visible.
- "Sector N — Node X / 6" caption above the bar.

Background: dimmed live `galaxy_backdrop` (V3) at ~40% modulate so the
choice screen feels in-universe, not a separate menu state.

---

## Why this beats the sector map

| Concern | Sector Map V2 | 3-Pick |
|---|---|---|
| Choice cadence | Once per row, branches obscure | Every node, three weighted options |
| Sense of progress | Visible position on grid | Explicit progress bar with boss icon |
| Pacing variance | Player can dodge most events by routing around | Player must engage with each pick; no skip-everything routes |
| Author control | Hard to enforce "always have an outpost before boss" | Trivial — position 5 forces it |
| Implementation cost | Grid math, edge validation, backward-edge stripping (already implemented) | Linear, much less code, can reuse existing node-type handlers |
| Replayability | Different routes feel similar after a few runs | Different RNG yields different 3-card surfaces every node |

---

## Open questions

- **Sector count:** keep current 4-sector run length, or shorter sectors
  with more of them (e.g., 8 sectors × 4 nodes each)? See enemy density
  research for the gameplay-length argument.
- **Re-roll mechanic:** should the player be able to spend a small bounty
  fee to re-roll the 3 choices? Adds a cost-vs-luck axis. Default: no.
- **Visibility of upcoming sector boss:** show the boss type in the
  progress bar's right-end icon, or keep it a surprise? Recommend showing
  — reduces "what should I prep for" anxiety.
- **Treasure node:** new type, needs an authored screen. Stub for now,
  spec later.

---

## Implementation plan (if approved)

1. Extend `Run` autoload with `sector_progress: int`, `sector_total: int`,
   `pending_choices: Array[Dictionary]`.
2. Build `scenes/progression_choice.tscn` + `scripts/progression_choice.gd`
   (driven by sector_map_v2 currently — straightforward swap).
3. Replace sector_map_v2 entry in the run flow with progression_choice when
   `Run.sector_progress < Run.sector_total - 1`; auto-pick Boss for the
   final node.
4. Reuse existing node-type combat/event handlers (`outpost.tscn`,
   `signal_event.tscn`, etc.) — no changes to those.
5. Stash sector_map_v2 behind a `Run.use_legacy_sector_map` debug flag for
   the first few playtests so we can A/B.

Estimated effort: ~half-day for the UI screen + ~quarter-day for the Run
plumbing + ~quarter-day for choice generation weighting. Existing handlers
do all the heavy lifting.

---

## Mockup

`scenes/dev/progression_mockup.tscn` — three-card layout with placeholder
icons + the progress bar. Re-roll button cycles through positions 1–6 so
you can see how the weighting changes and how the bar fills. Live backdrop
behind for atmospheric context.

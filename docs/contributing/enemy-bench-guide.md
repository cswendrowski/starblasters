# Enemy Bench — User Guide

A reference for the **Enemy Bench** dev tool (`scripts/dev/enemy_bench.gd`,
`scenes/dev/enemy_bench.tscn`). Launch it from the **Dev Menu**. It is a
human-run tuner, never shipped.

## What it is

A live test bench for **enemies** (it replaced the old Shipyard). You pick an
enemy from the list, it spawns in the 480×270 preview, cycles through its
movement patterns, and fires at a **dummy player you drive with the arrow
keys**. The right panel tunes that enemy's weapons, stats, locomotion, and
death — and you either **Save** the draft or **Copy GDScript** to paste back
into source.

> **The golden rule:** the bench **does not edit the game.** Everything you
> change lives in a tuner JSON (`user://tuners/enemy_bench.json`). To make a
> change real, hit **Copy GDScript** and paste the snippet into the roster /
> `enemy_strings.gd`. **Save** only persists your draft so it survives across
> sessions. This is the tuner contract — every tuner has a Copy-GDScript handoff.

---

## Left column

- **Faction tabs** (`All / Core / Supremacy / Privateer / Corporate / Zealot /
  Hazards`) — filter the list. Buckets are derived from the scene's **folder
  path**, not its tags, so a privateer minelayer stays under Privateer (not
  Hazards). Bosses are deliberately excluded — they don't tune cleanly here.
- **Enemy list** — every dev-roster enemy in the active faction. Icons are
  clipped to frame 0 so they read like the codex.

---

## Bottom bar

- **Next Pattern** — cycles to this enemy's next *eligible* movement pattern
  (from the eligibility matrix) and respawns. The label under the preview shows
  `Pattern: <key> (n/total)`.
- **Save** — writes the current enemy's settings to the tuner JSON.
- **Copy GDScript** — puts a paste-ready snippet on the clipboard (stats,
  mounts, emitters, locomotion, and an `enemy_strings.gd` entry). **This is the
  handoff to real code.**
- **Back / Esc** — returns to the dev menu (and restores audio mute state).
- **SFX toggle** — mutes/unmutes the SFX bus locally. Music is force-muted in
  dev menus.

---

## Right panel — Enemy tab

### Top: Name + stats readout
A live header showing the display name and `HP / Bounty / Eligible patterns`.

### Turret payload
The bullet used by enemies that fire through **child turrets** (zealot tank
turret, gun_turret, etc.). **This header + dropdown only appear when the selected
enemy actually has child turrets and no mounts** — it's hidden otherwise (the old
hull weapon was retired, and mount turrets carry their own payload). Choices are
the four bullet **families** (see below).

### Explosion
Death explosion variant. Applies live (no respawn needed) since it only matters
on death.

### Recycle (check + passes + chance)
The **recycling system** — enemies that exit the bottom and come back for
another pass instead of fleeing.
- **Recycle checkbox** — off = the enemy always flees (no recycle).
- **passes** — how many return passes it makes when it *does* recycle.
- **chance** — probability (0–1) it recycles vs. flees on any given exit.
  `1.0` = always recycle, `0.3` = 30% chance.

### Name / Codex
Editable display name and codex blurb. Renames sync live into the list header
and sidebar. Copied out as an `enemy_strings.gd` STRINGS entry.

### Template (size + traits) + stat knobs
The **derived-stats** layer — pick a size class + tags and HP/bounty/shield/
locomotion auto-fill from the size template, then hand-tweak the stat knobs that
sit right below it.
- **Size** (`tiny→giant`) — drives base HP / bounty / shield / locomotion from
  `SIZE_TABLE` + `SIZE_LOCOMOTION`.
- **tough** — `tough` tag, roughly ×2 HP.
- **shielded** — adds a **charge** shield sized to the template (live preview of
  the shield component).
- **omni / strafe / retro** — locomotion capability flags that decouple *facing*
  from *travel*:
  - **omni** = always faces the player while moving however it likes.
  - **strafe** = slides sideways without turning to face travel.
  - **retro** = can reverse without flipping its sprite.

  These ship inert by default (no production enemy sets them yet); the checkboxes
  let you preview the behavior.
**Stat overrides** — HP / Bounty / Bullet-speed are **opt-in**. Each is a
checkbox; leave it unticked (the default) and the enemy uses its template/native
value, keeping the row to a single line. Tick it to reveal a spinbox and pin an
explicit value:
- **Max HP** — `max_health` (respawns). Off = the size+traits template HP.
- **Bounty** — `bounty_value` (applies live). Off = template bounty.
- **Bullet speed ×** — `bullet_speed_mult`. Off = native 1×.

> *Display-scale and bullet-damage knobs were removed (2026-06-29) — enemies are
> always 1× scale and 1× bullet damage, so those weren't worth tuning. The
> remaining stat knobs became opt-in overrides the same day.*

### Locomotion (this enemy)
- **Engine ±rung** — an opt-in override (same checkbox pattern as the stats).
  When ticked, a **rung offset** on the size's base speed: each step = ±60 px/s
  (`+1` = +60 px/s faster), without changing weight/turn. Off = size-derived
  speed. (It defaults *on* for enemies whose roster entry already ships a
  non-zero engine offset, so you can see it.)
- **Depth** — the hold/cross band (`high / mid / low`) for how deep into the
  playfield it advances. `(default)` = derived from size/identity (this dropdown
  is its own opt-out, so it isn't gated behind a checkbox).

### Mounts editor (Add Mount)
Mounts are the actual weapons now (extra emitters beyond the retired hull
weapon). Each mount row:

| Control | What it does |
|---|---|
| **kind** | `Gun / Turret / Launcher / Beam`. Turret rows auto-get a faction turret graphic so they're visible. |
| **marker** | Where on the ship it fires from. `(hull)` = ship origin; named markers are the scene's `Marker2D`s; a `Muzzle*`-style **glob** means "all markers in that family." |
| **payload** | The bullet **family** (`Ball / Bolt / Laser / Wave`) or, for launchers, a projectile scene (Rocket / Missile / Bomblet). The family auto-restyles to the enemy's **faction** at spawn (see below). |
| **aim** | `Down / At Player / To Center / Forward`. |
| **rate** | **Seconds between shots** (not shots/sec) — lower = faster. `1.5` = fire every 1.5s. |
| **count** | Bullets per shot. |
| **spread** | Fan angle (degrees) across those bullets. |

**Bullet families + factions:** payloads are the four shapes — `Ball / Bolt /
Laser / Wave` — plus `Drop`. The four families auto-restyle to the enemy's
faction at spawn (`BulletCatalog.faction_variant`). Privateer + Zealot have real
art; Supremacy reuses the Zealot look and Corporate the Privateer look for now.
The bench preview stamps the selected enemy's faction so you see the right style.

**Dropping shots (Caltrop-style):** pick the **`Drop`** payload + aim **Down**.
`Drop` is a slow lingering pellet (45 px/s, 5s life) — because it crawls far
slower than the enemy descends, it hangs in the lane as a trail of dropped shots
in the enemy's wake. It reuses the **Ball** sprite, so it takes the enemy's
faction colour like the other families. Combine it with rear `Muzzle*` markers,
`count`/burst, and a `path` phase (the Caltrop fires a 4-shot burst at path phase
`0.4`) to reproduce the Caltrop's dropper.

**Gun/Launcher get extra firing controls:**
- **muzzles** (`All / Cycle`) — when a mount covers multiple markers: `All` fires
  every marker each shot; `Cycle` fires them one at a time round-robin.
- **volley** (`Simultaneous / Burst`) — `Simultaneous` fires all `count` bullets
  at once (a spread volley); `Burst` spaces them out by **burst gap** seconds.
- **burst gap** — seconds between consecutive shots in a burst (only shown in
  Burst mode).
- **speed** — bullet-speed override in px/s; `-1` = use the payload's default.
- **nose** — only fire when actually **aimed at the player**, within…
- **tol** — the aim tolerance in degrees for the `nose` gate (e.g. 18° cone).
- **path** — **path-phase** firing: comma-separated points along its movement
  path (0–1) where it's allowed to shoot, e.g. `0.4,0.7` = fire ~40% and ~70%
  of the way through its run.
- **beat** — when path-phases are set, snap those shots to the conductor's
  musical beat.
- **phase** — a named movement phase to gate firing on (for enemies with
  multi-phase state machines).

### Emitters editor (Add Emitter)
Emitters **drop or spawn a payload scene** on a trigger — the generalized form
of the interceptor's mine/missile drop. Separate from weapon mounts.

| Control | What it does |
|---|---|
| **trigger** | `Spawn` (once on entry) / `Timer` (repeating) / `On Death`. |
| **payload** | What to drop (from `EMITTABLE` — mines, bomblets, missiles, etc.). |
| **every** | Cadence in seconds (Timer trigger). |
| **count** | How many to drop per emission. |
| **max/pass** | Cap on total emissions per pass (`0` = unlimited). |
| **on-screen** | Only emit while the enemy is in the visible playfield band (so it doesn't litter offscreen). |

---

## Right panel — Sizes tab

Edits the production `SIZE_TABLE` (per size class: **HP / Shield cap / Bounty /
Speed×**). **No live preview** here — size stats scale *wave-spawned* enemies
(`compose_stats`), not the bench's direct spawn. **Save Sizes** stores the
draft; **Copy GDScript** emits a paste-ready `SIZE_TABLE` const for
`enemy_roster.gd`.

## Right panel — Locomotion tab

Edits `SIZE_LOCOMOTION` — per-size chassis kinematics: **Base speed** (a clarity
rung, 60–480 px/s), **Weight**, **Turn** (deg/s), **Accel** (px/s²). The
per-enemy **Engine** knob (Enemy tab) shifts an individual unit's speed off this
base. **Save Loco** / **Copy GDScript** → paste into `SIZE_LOCOMOTION`.

---

## The three concepts most people trip on

1. **Save ≠ apply to game.** Save = your private draft. Copy GDScript = the thing
   you actually paste into source. Nothing here touches the running game's data
   until you paste.
2. **"rate" is a period, not a frequency.** It's seconds between shots, so bigger
   = slower fire.
3. **nose / path / phase are firing *gates*** — they restrict *when* a mount is
   allowed to shoot (aimed-at-player, at a point on its path, during a named
   phase). Leave them off and the mount fires on its plain `rate` timer.
   Off-screen suppression is **automatic** for every enemy (no toggle) — a mount
   never fires while the enemy is off the visible playfield.

---

*Related: enemy/movement/weapon architecture is in
[Doc 03 — Combat, Waves & Enemies](03-combat-waves-enemies.md). The size/
locomotion/roster data this bench edits lives in
`scripts/levels/enemy_roster.gd`.*

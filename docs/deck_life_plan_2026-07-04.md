# Deck Life — bringing the outpost hangar plate to life

**Status:** SCOPED / NOT BUILT (2026-07-04). Design + phased plan; no code yet.

**Goal:** the outpost dock plate is static and boring once the ship lands. Make the deck feel like a
working carrier hangar: 2px **crew** wandering with drop shadows, **vehicles** (lifter / tractor /
trailer) doing jobs, and — the payoff — the deck **reacting to what the player does** in the shop
(welders swarm the ship and throw sparks when you Repair, a crate is delivered when you Buy/Refill,
crew haul a part off when you Sell/Scrap).

This is a **cosmetic** layer. It never blocks or gates shop logic — reactions are fire-and-forget.

---

## 1. Constraints & principles

- **Reuse, don't reinvent.** The plate already ships with everything we need to hang this on:
  - `scenes/hangar_stage.tscn` (`scripts/screens/hangar_stage.gd`) — the shared plate. Markers:
    `RunwayMarkers` (M0–M11), `FillLights` (2×3 PointLight2D), `Slots` (`Pad`, `LifterIdle`,
    `Park0..6`, `FlankL`, `FlankR`), `ClutterZones` (12 wall markers). API: `slot(name)`,
    `slots_prefixed(prefix)`, `clutter_node()`, `fill_lights()`, `ensure_key_light()`, `plate_size()`.
  - Effects: `spark_trail_fx.gd`, `damage_smoke_trail.gd`, `point_light_fx.gd` (PointLight2D factory),
    `light_shadow_fx.gd` (light-derived shadows), `hangar_clutter.gd` (crate scatterer).
  - Vehicle scenes: `scenes/outpost/outpost_lifter.tscn`, `outpost_tractor_trailer.tscn`,
    `outpost_tractor.tscn`; crate sheets `outpost_6px_crates` / `outpost_7px_crates` /
    `outpost_ammo_crates`.
  - The dock (`scripts/screens/outpost_arrival.gd`) already builds sparks + point-lights on the ship
    (`_attach_spark`, `_build_engine_lights`, `_make_light_texture`) — the welding FX is these, retargeted.
- **Everything rides the plate.** Crew/vehicles are children of the dock's `_plate` node so they
  descend in on arrival and slide out on departure. **Spawn only once `landed`; scatter + free on depart.**
- **Screen-owned, not baked into the shared scene.** The plate is shared with **Patrol Start**
  (`scripts/dev/patrol_start.gd`). So `DeckLife` is instantiated *by the screen* as a child of `_plate`,
  not authored into `hangar_stage.tscn`. Outpost opts in with the full config; patrol can opt in later
  with a quieter one (or not at all).
- **Pixel-art discipline.** Native 480×270 SubViewport, `TEXTURE_FILTER_NEAREST`, 1× sprite scale,
  **integer positions** (sub-pixel offsets shimmer against the moving plate — see the clutter code).
- **Slow, legible motion.** Crew walk ~1 px/f, vehicles ~1–3 px/f — well under the 8 px/f clarity ceiling
  (`scripts/systems/clarity.gd`). Nothing should strobe.
- **Tunable by the human.** Ship behind a dev lab with sliders + a **Copy GDScript** button (tuner
  contract). Placeholder-friendly: prototype with colored rects, drop in art later.
- **Perf budget.** Cap crew (~4–8), simple per-agent FSM, **no group scans in `_process`**, pooled
  nodes. A handful of tiny sprites in a 480-wide viewport is cheap.

---

## 2. Architecture

```
_plate (hangar_stage, dock-owned, descends/slides)
└── DeckLife (Node2D)                     scripts/screens/deck/deck_life.gd
    ├── waypoint graph (from plate markers)
    ├── crew pool: DeckCrew × N           scripts/screens/deck/deck_crew.gd
    ├── vehicles: Lifter, Tractor rig     (thin controllers over the existing scenes)
    └── task dispatcher / reaction API
```

### DeckLife (controller)
- Built by `outpost_arrival` on the `landed` signal (`_plate.add_child(deck_life)`), removed on depart.
- Reads waypoints from the plate: `ClutterZones` + `Slots` (`Park*`, `FlankL/R`, `Pad`) → an array of
  deck positions. (Optionally add a `DeckWaypoints` marker group to the .tscn for finer authoring.)
- Owns the crew pool + vehicles + a small task queue.
- Public API: `spawn(config)`, `set_active(bool)`, `scatter_and_clear()` (departure), and
  **`react(kind, ctx)`** — the reactive hook (see §3).
- Reads ship state for ambient mood: more/`concerned` crew when `damage_level` is high, calmer when pristine.

### DeckCrew (agent) — `Node2D`
- Children: `Sprite2D` (tiny walk cycle) + a baked drop `Shadow` (a 2–3px dark ellipse, like the ship's
  `DropShadow`); optionally registered as a `light_shadow_fx` caster later for sweeping shadows.
- **FSM:** `IDLE` (brief pause) → `WANDER` (walk to a random waypoint) → back to IDLE; plus task states
  `GOTO` (walk to a target), `WORK` (play a job anim in place, e.g. welding), `RIDE` (hidden inside a
  vehicle), `FLEE` (walk to nearest plate edge on departure).
- Move: `position` steps toward target at `speed` px/f, snapped to integers; `Sprite2D.flip_h` from
  travel direction; 2-frame walk-cycle tick.
- Cheap, self-contained `_process` (no scene queries).

### Task / reaction dispatcher
- A task = `{kind, target_pos, duration, on_done}`. DeckLife assigns a free crew (and/or a vehicle),
  drives it `GOTO → WORK`, then returns it to WANDER.
- `react(kind, ctx)` maps a shop action to one or more tasks (§3). Idle timer also enqueues ambient
  tasks (maintenance rounds, crate shuffles) so the deck is never fully still.

### Vehicles (thin controllers over existing scenes)
- **Lifter** (`outpost_lifter.tscn`): idles/bobs at `slot("LifterIdle")` with its grav-lights; on a task
  flies a `GOTO`-style path to a point (crate pickup/delivery over the ship), then returns. Already has
  hover lights + a 4-frame engine-glow anim.
- **Tractor+trailer** (`outpost_tractor_trailer.tscn`): ground loops between `ClutterZones` hauling a
  crate; a crew can `RIDE` it (driver hides, vehicle lights on).

### Welding FX (the hero effect) — `deck_weld_fx.gd`
Retarget the dock's existing spark + light kit to a point on the ship hull:
- **Sparks:** `SparkTrailFx.spawn(host, weld_pos)` bursts (reuse `_attach_spark` tuning).
- **Arc light:** a bright white/blue `PointLight2D` (via `PointLightFx.make`) whose energy **flickers**
  (noise) — the weld strobe. Casts brief flashes on the ship + deck.
- **Smoke:** a short `damage_smoke_trail`/puff wisp.
- Duration scales with the repair (pips restored). The ship's `damage_level` already tweens down in
  `_do_repair` → the fray recedes *as the crew work* — perfect sync, no extra wiring.

---

## 3. Reaction map (outpost action → deck reaction)

Hook points already exist as handlers in `outpost_arrival.gd`; add one thin call each:
`if _deck: _deck.react(<KIND>, ctx)`.

| Shop action (handler)                       | Deck reaction |
|---|---|
| **Repair** (`_do_repair`)                   | 1–2 **welders** `GOTO` the damaged hull → `WORK` weld (sparks + arc flashes + smoke). ★ hero moment. |
| **Refill ammo** (`_on_refill_*`)            | Lifter/tractor brings an **ammo crate** (`outpost_ammo_crates`) to the ship; a crew loads it. |
| **Buy part** (`_buy_market`)                | Lifter flies a **crate** over, lowers it onto the ship, flash. |
| **Sell / Scrap** (`_sell_*` / `_scrap_*`)   | A crew **hauls a crate away** to a scrap corner; scrap adds grinding sparks. |
| **Upgrade** (`_upgrade_part_live`)          | A bigger **pit-crew swarm** — extra welders, brighter light show. |
| **Idle** (no action for N s)                | Ambient: a crew does a maintenance round (walk to ship, tap/inspect, wander off), or the tractor shuffles a crate pile. |
| **Ship damaged** (high `damage_level`)      | More crew gather near the ship / a red beacon pulses if hull critical. Pristine → calmer, fewer crew. |
| **Depart** (`depart_requested`)             | Crew **scatter to the plate edges and wave** as the ship spools up, then free with the plate. |

---

## 4. Phased plan

Each phase is independently shippable and reviewed via a GIF (`tools/capture_deck_life.*` → `captures/`).

### Phase 0 — Scaffold (foundation)
- `deck_life.gd` + `deck_crew.gd`; DeckLife instantiated on `landed`, freed on depart.
- Waypoint list from plate markers. ONE crew wandering IDLE↔WANDER with a baked drop shadow, placeholder
  sprite (colored rect ok).
- A **Deck Life Lab** dev scene (or a tab in the Outpost Arrival Lab): sliders for crew count + speed +
  idle-pause range; Copy GDScript button.
- **Accept:** a crew wanders the landed deck, rides the plate in/out, no jitter, headless-clean.

### Phase 1 — Crew wander system (ambient life)
- Crew pool of N (tunable), facing/flip, idle pauses, staggered starts, integer motion.
- Baked shadows polished; optional `light_shadow_fx` caster registration behind a lab toggle.
- Ambient idle tasks (maintenance rounds, crate taps). Hull-state crowd density.
- **Accept:** deck reads as alive at rest; tunable; capped/pooled; perf lint clean.

### Phase 2 — Reactive hooks (the payoff)
- `DeckLife.react(kind, ctx)` + the thin calls in the shop handlers.
- Build the **welding-on-repair** hero moment first (`deck_weld_fx.gd`) — highest payoff, reuses the
  spark/light kit. Then buy/refill (crate delivery), sell/scrap (haul-away).
- **Accept:** repairing visibly summons welders whose sparks/flashes sync with the receding fray; each
  shop action triggers a legible deck response; still non-blocking.

### Phase 3 — Vehicles + group work (Roman's ambient ideas, 2026-07-04)
Specific behaviors to build (each a small crew/vehicle state machine; reuse patrol_start's rig code —
`_make_rig`, `_rig_lights`, `HangarClutter.fill_trailer`, the tractor+trailer scenes/hitch markers):
- **Lifter run:** a crewman walks to a parked lifter → boards (crew hides) → the reactor/engine-glow
  turns on → the lifter moves boxes around the deck (pick up a crate, fly it to a pile, set down).
- **Tractor + trailer run:** crew boards a tractor → lights on → drives to a trailer → links (rear
  Hitch ↔ trailer HitchF) → operator gets out, checks the link, gets back in → drives the trailer
  somewhere. The lifter can load/unload crates to/from the trailer.
- **Crew walk to boxes** — the clutter piles (`ClutterZones` / `clutter_node()`) become waypoints.
- **Congregate** — 2+ crew gather at a shared spot and pause (a group chat). *(BUILT Phase 1.)*
- **Two-crew crate carry** — 2 crew flank a crate (one on either side), lift it, walk it together to a
  new spot, set it down. Needs a movable crate entity + paired-agent sync.
- **Accept:** vehicles do real jobs tied to player actions; crew board/drive them + carry crates in pairs.

### Phase 4 — Polish
- Departure scatter + wave; light-derived sweeping shadows; ambient props (slow radar dish, warning
  beacons, vent puffs); maintenance micro-drones along the ceiling.

---

## 5. Assets needed from Roman

I can **prototype every phase with placeholder rects** (like the cruiser placeholder PNGs), so the
systems land first and art drops in later. Eventual art wishlist:
- **Crew sprite sheet** — small (≈4–6px tall), 2-frame walk cycle + a "work/weld" pose + idle. 1–2 color
  variants would add life. (Down-facing/side-facing is enough for a top-down deck.)
- Optional props: a scrap/weld rig, a radar dish, a warning beacon.
- Lifter / tractor / trailer / crates **already exist**.

---

## 6. Dev lab & review loop

- **Deck Life Lab** (tuner contract: sliders + Copy GDScript, JSON persist to
  `user://tuners/deck_life.json`) so Roman tunes counts/speeds/reaction intensity — no edit-capture-look.
- Review visuals via **GIF capture** (`tools/capture_deck_life.gd` + `.ps1` → ffmpeg → `captures/`),
  not by reading frames.

---

## 7. File layout (per `docs/file-structure.md`)

- `scripts/screens/deck/deck_life.gd`, `deck_crew.gd`, `deck_weld_fx.gd` (dock-adjacent, near
  `hangar_stage.gd`).
- `scenes/outpost/deck_crew.tscn` (crew instance), placeholder art under
  `graphics/outpost/placeholder/` (regen tool if generated).
- `scenes/dev/deck_life_lab.tscn` + `scripts/dev/deck_life_lab.gd`; dev-menu button.
- `tools/capture_deck_life.gd` + `.ps1`.

---

## 8. Open questions for Roman

1. **Crew density / vibe** — a sparse professional crew (2–3) or a busy deck (6–8)?
2. **Patrol Start** — want the deck alive there too (quieter), or outpost-only for now?
3. **Reaction priority** — is the **welding-repair** moment the one to nail first (my assumption), or a
   different action?
4. **Art** — hand me a crew sheet up front, or should I prototype with placeholders and you draw over them?

**Recommended start:** Phase 0 + the Phase 1 wander system behind the lab (the foundation everything
hangs off), prototyped with placeholder crew — then Phase 2's welding moment so the reactive payoff is
visible early.

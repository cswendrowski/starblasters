# Starbase Assault — design

**Status: SCOPED / NOT BUILT** (2026-07-28). Design for a non-asteroid base-assault level type built
on Roman's authored station prefabs (`scenes/enemies/ground/station/prefab_*.tscn`). Nothing below
exists in code yet. The asteroid Stronghold Attack (`SectorNode.NodeType.STRONGHOLD = 6`) is the
sibling system this reuses; where the two agree, **the stronghold code is the reference**, not this
doc.

---

## 1. What the prefabs are

Four authored sections under `scenes/enemies/ground/station/`. All share one anatomy:

```
Starbase (Node2D)              <- prefab root
└── Node                       <- plain Node, no transform
    ├── Background Platform    TileMapLayer, 0.5x, modulate ~0.38  (deep understructure)
    ├── Background Girders2    TileMapLayer, 0.5x, modulate ~0.38
    ├── Background Girders     TileMapLayer, 1x,   modulate ~0.76
    ├── Angled Platform        TileMapLayer, 1x,   full bright     <- THE DECK
    │   └── TileMapLayer       conduit detail
    └── Enemy* ...             raw building/turret .tscn instances
```

Tilemaps are **pure scenery** — no collision, no groups, no physics layers. The building instances
are the only nodes in the `enemies` group. This matches the 2026-07-18 altitude model the asteroid
stronghold landed on: the ground plane is terrain the ship flies *over*, and only the structures on
it are shootable.

### Measured footprints

Decoded from the `tile_map_data` PackedByteArrays (16 px tiles, parent transforms applied):

| prefab | deck (`Angled Platform`) | full tile footprint | buildings | reads as |
|---|---|---|---|---|
| `prefab_platform` | x[128,320] y[48,144] | y[40,152] — **112 px** | y 64–128 | connector |
| `prefab_platform_fuel` | x[128,320] y[48,144] | y[40,152] — **112 px** | y 64–128 | connector, fuel farm |
| `prefab_hangar` | x[128,320] y[0,272] | y[−16,288] — **304 px** | y 16–256 | set piece, ~1.1 screens |
| `prefab_battle_station` | x[128,320] y[0,768] | y[−16,800] — **816 px** | y 16–256 *(WIP)* | boss gauntlet, ~3 screens |

**All four decks are exactly x 128–320.** The understructure girder layers vary (112–336 on three,
160–288 on `prefab_platform`) but that's decorative depth behind the deck, so it doesn't affect
stitching.

`prefab_battle_station` is in progress — it will become a long stretch of structure lined with
weaponry. **Its height will keep changing**, which is why every footprint below is measured at
runtime from `TileMapLayer.get_used_rect()` rather than baked into a table.

### Deck is 16 px left of playfield centre

`Playfield.CENTER.x = 240` (band 132–348). The decks span 128–320, centre **224**. So the deck's
right edge stops 28 px short of the band's right edge while its left edge pokes 4 px past the left.
**Resolved (Roman, 2026-07-28): fixed at source** — the prefabs get recentred, so no runtime offset
is needed. The field applies **no** implicit centring; silently correcting authored art would hide
intent the moment a section is deliberately asymmetric. `x_offset` in the registry (§4.1) stays
available as an opt-in escape hatch, unused by default.

---

## 2. The load-bearing gotcha: buildings are inert as authored

The prefabs instance `enemy_square_turret.tscn` / `enemy_square_launcher.tscn` / etc. **raw**. Those
scenes carry `movement = LateralDrift(mode 1)` and **no `mounts`** — a building's weapon lives in
`enemy_roster.gd`, not in its scene. Dropped into a level as-is, every turret on these decks would
**drift off the platform and never fire**.

`stronghold_building_palette.gd::spawn` already solves this for asteroid strongholds. Its order of
operations (the Enemy Bench / director contract) is:

```
inst = scene.instantiate()
inst.movement = null                                  # BEFORE add_child
inst.mounts   = EnemyRoster.make_mount_specs(roster_mounts_for(type))
parent.add_child(inst)                                # _ready fires here
inst.start(local_offset)                              # inits movement + facing
inst.offscreen_mode = NONE                            # ride the parent, never self-recycle
inst.slot_weight    = 0                               # don't consume director slots
```

HP and livery need no help — `enemy_core_building_turret._ready()` already calls
`_apply_roster_health()` and `_apply_livery()`, and pins `recycle_passes = 0`.

**`PackedScene.instantiate()` does not fire `_ready`** — `_ready` fires on `add_child` into the
tree. So a prefab can be instantiated, walked, adopted, and *then* added, preserving the contract
exactly.

### Change: split the palette into `pre_add` / `post_add`

Add to `scripts/enemies/stronghold_building_palette.gd`:

```gdscript
static func adopt_pre_add(inst: Node) -> void    # movement=null, mounts from roster (keyed off scene_file_path)
static func adopt_post_add(inst: Node, offset: Vector2) -> void   # start(), offscreen_mode, slot_weight
```

and rewrite `spawn()` to call them, so the placed-by-editor path and the authored-in-scene path share
one implementation. The type key derives from `inst.scene_file_path` via the existing `_key_for`,
so `ALIASES` and the roster-discovery scan keep working untouched.

---

## 3. Decisions taken (Roman, 2026-07-28)

| question | decision |
|---|---|
| Battle-station boss beat | **Gauntlet scroll-through.** The spine never freezes; it passes at reduced speed. Bar = Σ structure HP as a progress/damage meter. Clears when the tail passes — skipped turrets just scroll off. Bounty scales with what was actually levelled. |
| Section stitching | **Continuous ribbon** (`gap = 0`). Sections butt deck-to-deck into one unbroken station. |
| Sector-map placement | **Planet POIs.** Orbital station over the world. No new deco art, no churn to the `randi() % 3` chains. Flyover suppressed on promoted nodes. |

### Consequence: scroll speed belongs to the field, not the section

A ribbon is rigid. If the battle station scrolled at ×0.5 while the section behind it ran at ×1.0,
they'd telescope into each other. So `scroll_speed` is a **property of the field**, and the field
tweens it down when the gauntlet's head enters and back up once its tail clears. Sections carry no
drift of their own. (This is the one place the design departs from `asteroid_stronghold.gd`, where
each rock owns its `drift_speed`.)

### Consequence: stitch on the deck, not the union footprint

`prefab_platform`'s girders overhang its deck by 8 px top and bottom (footprint 112, deck 96).
Stitching on the union footprint would leave an 8 px deck gap at every seam, bridged only by
girder overhang. Stitching on the **deck layer** butts the walkable surface flush and lets the
understructure overlap slightly at seams — which is what the girders are for.

So: **stitch height = the deck layer's `get_used_rect()` height**, resolved as

1. the registry entry's explicit `stitch_height`, if set; else
2. the layer named `Angled Platform`, if present; else
3. the union of all `TileMapLayer` used rects.

---

## 4. Architecture

### 4.1 New — `scripts/levels/station_sections.gd`

Registry of authored sections, the `asteroid_strongholds.gd` analogue. Scene-path based rather than
JSON-dict based, because authoring happens in the Godot editor, not a bespoke tool.

```gdscript
const DATA: Array = [
    { "name": "Platform",       "scene": "res://scenes/enemies/ground/station/prefab_platform.tscn",
      "role": "normal" },
    { "name": "Fuel Platform",  "scene": ".../prefab_platform_fuel.tscn",  "role": "normal" },
    { "name": "Hangar",         "scene": ".../prefab_hangar.tscn",         "role": "normal" },
    { "name": "Battle Station", "scene": ".../prefab_battle_station.tscn", "role": "boss",
      "speed_mult": 0.5 },
]
# optional per-entry: stitch_height, x_offset, category (overrides auto-classification)
```

`load_all()` mirrors the stronghold loader's shape so the shared field base can consume either.

### 4.2 New — `scripts/levels/station_section.gd`

Runtime wrapper for one prefab. Mirrors `asteroid_stronghold.gd`'s **exact public surface** so the
shared field base drives either without knowing which it holds:

- `configure(entry: Dictionary)` — instantiate, adopt buildings (§2), measure stitch height,
  normalize the z-stack, register per-building HP.
- `role()`, `max_hp()`, `is_defeated()`, `release_drift()`
- signals `locked_in()`, `health_changed(cur, mx)`, `cleared()`

Differences from the asteroid version:

- **No drift of its own** — the field moves it (§3).
- **`is_defeated()` for a gauntlet** = the section's tail has cleared the bottom of the screen, OR
  every structure is dead (whichever lands first). The asteroid version requires all-structures-dead;
  a scroll-through spine needs the tail condition or the level can never clear.
- **Footprint measured, not authored** — `get_used_rect()` union, per §3.

**Z-stack** — see §5.1. Assigned absolutely at configure time by layer order (deepest first), so a
new prefab with more or fewer layers works without hand-set z. Backdrop lives on its own negative
`CanvasLayer`s, so even −16 still draws above it. This mirrors `asteroid_stronghold
.build_rock_visual` pinning the rock at `GROUND_Z - 3`.

### 4.3 Refactor — `scripts/levels/ground_field_base.gd`

Extract from `stronghold_field.gd`, unchanged in behaviour. About 200 lines of encounter plumbing
that is **identical** for both field types:

- `_spawn_encounter` / `_on_encounter_locked` / `_on_encounter_cleared`
- parallax stop + resume (`_stop_parallax` / `_resume_parallax`, the `Backdrop.drift_speed` tween)
- music envelope (`_music_up` / `_music_down`, `set_walk_frozen` + `set_intensity`)
- boss bar (`_show_bar` / `_hide_bar` against `main.boss_hp_bar` / `main.boss_label`)
- `director.boss_gate` handoff
- `_on_player_died` + `_exit_tree` teardown guards (these exist because a death mid-encounter
  otherwise leaks a frozen music envelope and a stuck boss bar — **do not drop them**)
- the weighted progression helpers (`_progress`, `_weight_at`, `_category_for_wave`,
  `_wave_size_for`, `PROG_WEIGHTS`) and content classification (`_classify`)

`stronghold_field.gd` and `station_field.gd` both extend it. This must be a **pure refactor** — the
stronghold assault has to play identically afterwards, verified before `station_field.gd` is written.

### 4.4 New — `scripts/levels/station_field.gd`

The conveyor. Replaces the stronghold's "wait for the last rock to descend" heuristic, which tears a
rigid ribbon:

```
spawn the next section at   last.top_y - gap - next_stitch_height
when                        last.top_y >= -spawn_margin
```

with `gap = 0` for the ribbon. All live sections move at the field's single `scroll_speed`. Sections
free themselves once `top_y > screensize.y`, which is what lets the `enemies` group drain →
`director.level_cleared` → outro.

Composition reuses the extracted progression wholesale: sections classify by building content (the
existing substring count of `launcher` / `turret` / everything-else, so new prefabs bucket
themselves), then each slot rolls from progress-weighted light → heavy → mixed → core buckets that
ramp alongside the ship generator's density.

**Finiteness is load-bearing.** Same contract as the stronghold field: the sequence must end and
every section must be freeable, or `level_cleared` never fires.

### 4.5 Production node wiring

| file | change |
|---|---|
| `scripts/systems/sector_node.gd` | append `STATION = 7` to `NodeType` — **appended, never renumber** (the int is serialized in `sector_map_cache`); label + icon char |
| `scripts/autoload/run_state.gd` | `_promote_station_pois(rows, seed)` mirroring `_promote_stronghold_pois` — eligible = `_poi_obj_kind() == 0` (planet), decorrelated rng salt, own `STATION_MAX_PER_ROW` / `_PER_SECTOR` / `_CHANCE` caps |
| `scripts/game/main.gd` | branch on node type 7 → same `WaveGen.build` + ship-depth-cap treatment the stronghold branch uses, then `_want_station_field` |
| `scripts/parallax/stellar_gameplay.gd` | node type 7 → no asteroid belt; **suppress the flyover roll** so the deck doesn't fight a scrolling planet surface |
| `scripts/screens/sector_map_v3.gd` | icon, tooltip, `_PN_STATION_PREFIX` name list |
| `scripts/dev/combat_lab.gd` | "Starbase Assault" encounter entry (`node_type = 7`), honouring the depth spinners + faction dropdown |
| `scripts/parallax/backdrop_coordinator.gd` | create the shadow rig on station nodes too — the gate is `asteroid_shadows and has_asteroids`, and a planet-POI starbase has neither (§5.3) |
| `scripts/parallax/asteroid_shadow_rig.gd` | per-frame `should_cast(caster)` filter in `_update_masks`: skip `_cycling` ghosts and station buildings (§5.3) |
| `scripts/effects/recycle_controller.gd` | ✅ **BUILT 2026-07-28** — `GHOST_Z = -18` + `_sink_ghost` / `_raise_ghost` (§5.4). Global; also fixes ghosts over stronghold + asteroid-POI terrain |
| `graphics/station_shadow_receive.gdshader` | new — 3-line `SCREEN_UV` mask receiver, ported from `Asteroids.gdshader:176-178` (§5.3) |

Untouched: `WaveGen`, `director`, `enemy_core_building_turret`, `BuildingShadow`, `BuildingBoom`,
`Factions`, `SceneTransition`'s stray-actor sweep, the loading screen (`"Flying to <POI>"` is
already generic).

---

## 5. Rendering — shadows and depth

Four requirements (Roman, 2026-07-28). Three of them are the same z-ordering problem seen from
different sides, so §5.1 settles the stack first.

> **Boundary with the lighting workstream.** Scene light direction is handed off separately
> ([`scene_light_direction_2026-07-28.md`](scene_light_direction_2026-07-28.md), owned elsewhere as
> of 2026-07-28). The two overlap on exactly one file: **`scripts/parallax/asteroid_shadow_rig.gd`**
> — the lighting work changes `SHADOW_DIR` (a const at the top), this work adds a `should_cast()`
> filter inside `_update_masks` (§5.3). Different regions, but the same file, so whoever lands
> second should rebase rather than overwrite. `scripts/effects/building_shadow.gd` is **read-only**
> from this side — §5.2 consumes `DEFAULTS.sun_dir`, never writes it — so there's no contention
> there. Nothing here blocks on the lighting work landing.

### 5.1 The full z-stack

Everything below −7 is new; every existing pin (−7 / −5 / −4 / −1 / 0) is untouched.

```
recycle ghosts        -18   <- NEW (§5.4), currently 0
  Background Platform  -16
  Background Girders2  -15
  Background Girders   -14
  DECK SHADOW          -13   <- NEW (§5.2), generated
  Angled Platform      -12       the deck
  CONDUIT SHADOW       -11   <- NEW (§5.2), generated
  conduit layer        -10
                     (-9, -8 headroom)
building shadows       -7   existing, BuildingShadow z -2 relative to a -5 building
buildings              -5   existing, enemy_core_building_turret.GROUND_Z, absolute
overlay frames         -4   existing
player bullets         -1
actors / enemy bullets  0
```

Assigned from a base of −16 stepping forward one per layer, with the generated shadow layers
inserted inline — so section prefabs stay authorable without hand-set z values.

### 5.2 Structural shadows *within* a section (notes 1 + 2)

> *"The rounded platform needs a drop shadow on the other background layers under them. The deco
> conduits need a short drop shadow on the rounded platform layer."*

Both casters are **static relative to their receivers** — the deck never moves against the girders
beneath it. So this needs no shader and no ray-march: for each casting layer, `duplicate()` it, set
`modulate = Color(0, 0, 0, alpha)`, offset it by `sun_dir * distance`, and insert it directly below
its caster in the stack. The caster draws on top, so the shadow only shows where the caster doesn't
cover — which is exactly the wanted result, including through gaps in the deck.

Generated at runtime in `station_section.configure()` rather than hand-authored, so Roman doesn't
maintain ~8 extra `TileMapLayer`s per prefab and new sections pick it up for free.

**Use `BuildingShadow.DEFAULTS.sun_dir` = `Vector2(0.7071, 0.7071)` (45°, down-right)** — *not* the
asteroid rig's direction. The buildings standing on the deck already cast at 45° via
`BuildingShadow`; a deck casting at a different angle than the crates sitting on it is the most
visible possible mismatch.

Knobs (tuner candidates): deck shadow distance ≈ 4–6 px (it's a raised platform over open
girderwork), conduit shadow ≈ 1–2 px ("short"), plus alpha for each.

> ⚠️ **Sun-direction split, pre-existing and wider than two systems.** Live right now: PlanetKit
> planets + map bodies at **180°**, baked rocks + `BuildingShadow` at **225°**, `AsteroidShadowRig`
> at **≈249°**. Unifying them (and making them star-reactive) is designed separately in
> [`scene_light_direction_2026-07-28.md`](scene_light_direction_2026-07-28.md). **Not a prerequisite
> for this work** — the station shadows read `BuildingShadow`'s 45° directly today and switch to
> `SceneLight.shadow_dir()` when that lands.

### 5.3 Ships casting onto the deck (note 4)

> *"Active in-combat enemies and the player should cast drop shadows on the starbase layer like we
> do for asteroids."*

`asteroid_shadow_rig.gd` already does the hard part and needs no structural change. It auto-tracks
the `player` + `enemies` groups every frame, bakes each caster's silhouette (offset + scaled per
band) into a per-band mask `SubViewport`, and exposes `mask_texture(band)` + `band_strength(band)`.
Receiving is three lines of shader — `Asteroids.gdshader:176-178`:

```glsl
if (shadow_strength > 0.0) {
    float sm = texture(shadow_mask, SCREEN_UV).a;
    out_rgb *= 1.0 - sm * shadow_strength;
}
```

So: a small `graphics/station_shadow_receive.gdshader` doing exactly that over `TEXTURE`, applied to
**every** station `TileMapLayer` (screen-space mask, so a ship over a gap correctly darkens the
understructure visible through it), bound once at configure exactly like
`asteroid_stronghold._apply_shadow` — `SCREEN_UV` tracks the ship as the deck scrolls under it, so
there's no per-frame update. Band `"near"`, matching the stronghold rock.

Three wiring items this exposes:

1. **The rig won't exist.** `backdrop_coordinator._populate` creates it under
   `if asteroid_shadows and has_asteroids:` — a planet-POI starbase has no asteroids, so **no rig,
   no ship shadows**. The condition needs to include station nodes.
2. **Recycling ghosts must not cast.** The rig scans the `enemies` group, and a recycled enemy stays
   in that group while it flies back (it is *not* reparented — `recycle_controller` only swaps the
   body material and sets `_cycling`). A ship that has receded into mid-depth casting a full-strength
   shadow on the deck is wrong. `enemy._cycling` is the discriminator, already on `enemy_base:215`.
3. **The station's own buildings must not cast.** They're in `enemies` too, so they'd cast rig
   shadows onto the deck they stand on, doubling with their tuned `BuildingShadow` oblique shadow.

All three filter cleanly through one per-frame `should_cast(caster)` check in `_update_masks`, which
already sets `ms.visible` per caster per frame — no structural change to the rig.

### 5.4 Recycling enemies flying under the station (note 3)

> *"Recycling enemies are going to be flying UNDER the prefab."*

A recycled enemy is **not** reparented — `RecycleController` applies a depth-tint material via
`MidDepthPresentation.recede_body`, sets `_cycling`, and flies it back up. Its `z_index` is never
touched, so it sits at **0**, above a deck pinned at −12. As things stand it would fly *over* the
station, not under.

`MidDepthPresentation.add_above_backdrop` deliberately avoids a `z_index` override, but its comment
warns specifically against a *positive* one lifting the ghost above the ships. A **negative** pin
sinks it, which is what a receded object should do anyway. So: pin cycling ghosts to z −18 for the
duration of the fly-back, restored in `_restore_ghost_look` alongside the material and modulate.

> ✅ **BUILT 2026-07-28** (Roman approved the global change), ahead of the rest of this design.
> `RecycleController.GHOST_Z = -18`, applied in `_sink_ghost` from `_apply_ghost_look` and reversed
> in `_raise_ghost` from `_restore_ghost_look` — the existing symmetric pair, so the despawn+credit
> path (which frees the node) needs no restore. Pinned absolutely so the ghost lands at the same
> depth regardless of host; children keep `z_as_relative`, so a multi-part hull sinks as one piece
> with its internal ordering intact.
>
> **This is global, not starbase-local**, and deliberately so: ghosts also flew over the asteroid
> stronghold rock (−8) and loose asteroid-POI rocks (−1). A receded ship occluding terrain it's
> meant to be behind was a bug in both places, so stronghold and asteroid-POI levels change too.
> (The station-only alternative doesn't exist: putting the station on its own `CanvasLayer` sorts it
> *below* the entire default canvas, the wrong direction.)
>
> Verified: `tools/test_recycle_ghost_depth.gd` (11 assertions — sink depth clears all three ground
> planes, round-trip for relative *and* absolute-z enemies, idempotent double-sink, no-op raise),
> plus `parse_check` 408/0 and a clean 300-frame headless boot. **Not yet seen in play** — the
> visible change on stronghold levels wants Roman's eye.

## 6. Build order

- **P0 — prefab prep.** Resolve the 16 px centring (§1). Add `station_sections.gd` with role +
  `speed_mult` per prefab.
- **P1 — one section on screen.** `station_section.gd` + the palette `adopt_*` split + a Combat Lab
  entry that drops a **single** section, no field. This is the checkpoint that proves the armed-turret
  fix, HP from roster, the z-stack, faction livery, and self-free on exit.
- **P1.5 — structural shadows (§5.2).** The generated deck + conduit shadow layers. Self-contained,
  visible on a single static section, no field needed — worth landing while P1 is on screen.
- **P2 — the field.** Extract `ground_field_base.gd` as a pure refactor (**stronghold must play
  identically** — verify before moving on), then `station_field.gd` on top.
  *(The recycle-ghost z pin, §5.4, was pulled forward and landed 2026-07-28.)*
- **P3 — production node.** `STATION = 7`, POI promotion, `main.gd` branch, map icon + names,
  flyover suppression. The shadow-rig creation gate (§5.3) rides along — it's the same
  planet-POI-has-no-asteroids condition.
- **P3.5 — ship shadows (§5.3).** Receiver shader + the rig caster filter. After P3 because the rig
  has to exist on a station node first.
- **P4 — tuning.** `Run` meta `station_field_knobs` (scroll speed, gap, gauntlet speed mult, section
  count, progression weights) + the shadow distances/alphas from §5.2. A dedicated tuner only if the
  knobs actually need iteration — per the tuner contract, if one gets built it needs a **Copy
  GDScript** button.

## 7. Open / deferred

- **`background_platforms.png`** and some `graphics/backgrounds/Starbase/` tilesets are slated for
  removal in a later cleanup pass. Don't build a parallax underlayer on them.
- **Debris pepper.** The asteroid stronghold has `asteroid_pepper.gd` peppering loose rocks through
  the fight. A station equivalent (drifting containers / hull debris) is a natural follow-up, not P1.
- **Seam dressing.** If butted sections read as a hard cut, a shared connector strip drawn at each
  seam would bridge them. Deferred until the ribbon is on screen and can be judged.
- **Scene light direction.** Moved out to its own design —
  [`scene_light_direction_2026-07-28.md`](scene_light_direction_2026-07-28.md). Independent of this
  work; the station shadows use `BuildingShadow`'s angle until it lands.

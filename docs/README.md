# Starblaster docs — index & canon

This file says **which doc is the live reference for each system**, and which docs are
**history**. It exists because the project moved fast and older design docs kept getting cited
as if current (see the 2026-06-15 staleness audit: [`doc_staleness_audit_2026-06-15.md`](doc_staleness_audit_2026-06-15.md)).

**The code is always the ultimate source of truth.** Docs point at it; they don't replace it.

## How to read a doc's status

Every doc should declare its status near the top. Treat them as:

- **CURRENT** — the live reference for its system. Trust it, but verify specifics against code.
- **`docs/archive/…`** — historical / superseded. Every archived doc carries a banner
  (`⚠️ ARCHIVED … SUPERSEDED BY …` or `✅ ARCHIVED … this shipped`). **Never cite an archived
  doc as current design** — follow its banner pointer instead.
- **SCOPED / NOT BUILT** — a design for unbuilt work. Useful as intent, but the feature does not
  exist yet; don't describe it as shipped.

When you write a new design doc, give it a one-line `Status:` header and, when it's superseded,
move it to `docs/archive/` with a banner rather than deleting it.

## Where current truth lives

| System | Canonical reference |
|--------|--------------------|
| Project rules + architecture map | [`../CLAUDE.md`](../CLAUDE.md) |
| Newcomer tour | [`contributing/`](contributing/) (01–06) |
| File layout / where new files go | [`file-structure.md`](file-structure.md) (deferred orphan-cleanup backlog: `file_reorg_audit_2026-06-14.md` §2) |
| Splitting work across sessions | [`session-handoff-map.md`](session-handoff-map.md) — 16 work sections with owns/shared/verify/canon per section, the shared-file collision spine, and a handoff prompt template |
| Modular enemy system (M6) | [`m6_modular_enemies_design_2026-06-05.md`](m6_modular_enemies_design_2026-06-05.md) + [`m6b_faction_tagging_2026-06-06.md`](m6b_faction_tagging_2026-06-06.md); live roster = `scripts/levels/factions.gd` + `scripts/enemies/` |
| Movement-pattern eligibility | [`pattern_eligibility_2026-06-08.md`](pattern_eligibility_2026-06-08.md) + `scripts/levels/pattern_eligibility.gd` |
| Wave authoring principles | [`wave_composition_guide_2026-06-03.md`](wave_composition_guide_2026-06-03.md); authored-pattern editor **BUILT 2026-06-16**: [`wave_pattern_editor_design_2026-06-15.md`](wave_pattern_editor_design_2026-06-15.md) (dev tool `scripts/dev/wave_pattern_editor.gd` + `scripts/levels/authored_patterns.gd`) |
| Level structure (3-stretch + slot density) | **BUILT 2026-07-01, unverified in-game** — [`level_structure_redesign_2026-07-01.md`](level_structure_redesign_2026-07-01.md) (3-part ~3-min levels: `WaveGenerator._build_stretch` + `EnemyBase.slot_weight` + `director._alive_slots`; caps 16/26/36; chaff roll-back reverses the 2026-06-08 recycle:0) |
| Player weapons — data model | [`weapon_data_centralization_2026-06-11.md`](weapon_data_centralization_2026-06-11.md) (stats live in `.tres`) |
| Player weapons — live DPS numbers | [`weapon_dps_report_2026-06-13.md`](weapon_dps_report_2026-06-13.md) (rebalance candidates are deferred, not a to-do) |
| Enemy weapons + projectiles | [`weapons_system_2026-06-05.md`](weapons_system_2026-06-05.md) |
| Mount + emitter → one "Hardpoint" system | **BUILT 2026-07-03** — [`hardpoint_unification_design_2026-07-02.md`](hardpoint_unification_design_2026-07-02.md) (unified `MountSpec`/`MountComponent` + `EmitterComponent`; aim BACKWARD/LEFT/RIGHT, muzzle INWARD/OUTWARD, payload Delay/Inertia/Nose, deviation, volleys, max_fires) |
| Hardpoint v2 — Payload × Delivery × Trigger | **Phases A + B + C ALL SHIPPED 2026-07-05 (unverified in play)** — [`hardpoint_v2_design_2026-07-05.md`](hardpoint_v2_design_2026-07-05.md) (launcher→gun payload ✅, beam→payload ✅, turret honors all firing settings + projectile payload ✅, rings→RING hardpoint delivery ✅. Deferred-cosmetic: retire turret/launcher/beam/ring *kinds* for a Payload+Delivery schema, beam×turret, migrate bespoke bloom/mine orbits) |
| Faction bullet/muzzle recolor (grayscale + tint) | **SCOPED / NOT BUILT** — [`faction_energy_recolor_design_2026-06-22.md`](faction_energy_recolor_design_2026-06-22.md) (waits on grayscale assets; color data = `Factions.MUZZLE_GLOW_COLOR`) |
| Shift modes (Focus / Phase / Hyper) | [`shift_mode_system_2026-06-08.md`](shift_mode_system_2026-06-08.md) |
| Passive module bay | [`passive_module_bay_2026-06-13.md`](passive_module_bay_2026-06-13.md) |
| Enemy shields | [`shield_unification_2026-06-08.md`](shield_unification_2026-06-08.md) |
| Signal events | [`signal_event_redesign_2026-06-08.md`](signal_event_redesign_2026-06-08.md) |
| Sector Conditions (ex-"sector modifiers") | **SCOPED / NOT BUILT** — [`sector_conditions_redesign_2026-07-06.md`](sector_conditions_redesign_2026-07-06.md) (parked system re-eval; effect wiring lives behind `Run.SECTOR_MODIFIERS_ENABLED`) |
| Economy / outpost | **Code is the reference** — `scripts/autoload/run_state.gd` (bounty + Materials, outpost hub) + `scripts/screens/outpost.gd`. The old two-currency design is archived. |
| Outpost deck life (crew/vehicles/reactions) | **IN PROGRESS 2026-07-04 (Phase 0–3 partial, uncommitted)** — [`deck_life_plan_2026-07-04.md`](deck_life_plan_2026-07-04.md). BUILT: `scripts/screens/deck_life.gd`+`deck_crew.gd` (2px top-down crew wander + weld-on-repair + congregate + two-crew crate carry + walk-to-boxes), rides `_plate`, tuned via Outpost Arrival Lab. NOT built: vehicle runs (lifter/tractor), real art, ship-select |
| Sector map | `scripts/screens/sector_map_v3.gd` wrapped by `scripts/screens/sector_map_hd.gd` (routed via `scripts/systems/sector_map_route.gd`) |
| Scene light direction (planets / asteroids / shadows) | **BUILT 2026-07-28 (L1+L2+L3), UNPLAYTESTED** — [`scene_light_direction_2026-07-28.md`](scene_light_direction_2026-07-28.md). SSOT is `scripts/systems/scene_light.gd`; canonical azimuth **225° up-left** (Roman's call). One sun: planets/map bodies, baked + live rocks, building shadows, ship shadows and the flyover ground all derive from it. **Star-reactive** — the sun swings **207°–243°** with `system_frac` (position along the row), published in `BackdropCoordinator._populate`, reset per scene hop in `SceneTransition._run`; tune with the single constant `SceneLight.STAR_SWING_DEG`. ⚠ **The `sun_dir` uniform means the LIGHT direction in `planet_ground.gdshader` but the SHADOW direction in `building_shadow.gdshader`** — use `light_dir()` vs `shadow_dir()` accordingly; backwards is a silent 180° flip. Guard: `tools/validate_scene_light.gd` (`VERDICT: PASS`). Baked parallax rocks deliberately stay pinned to the constant (lighting is in the atlas pixels) |
| Starbase Assault (station base-assault levels) | **SCOPED / NOT BUILT** — [`starbase_assault_design_2026-07-28.md`](starbase_assault_design_2026-07-28.md) (authored `scenes/enemies/ground/station/prefab_*.tscn` sections stitched into a continuous scrolling ribbon; reuses the asteroid Stronghold rig via an extracted `ground_field_base.gd`. Sibling system = `scripts/levels/stronghold_field.gd` + `scripts/enemies/asteroid_stronghold.gd`, which are the reference where the two agree. §5.4 recycle-ghost depth pin is BUILT 2026-07-28) |
| Backdrop/parallax system review | **REVIEW 2026-07-06, handoff doc** — [`parallax_backdrop_review_2026-07-06.md`](parallax_backdrop_review_2026-07-06.md) (why depth feels "off": bunched scroll ratios + inverted brightness ramp + 6 independent color authorities + conveyor motion; P0 global-RNG reseed bug; dead V1/V2/V3; tuner-pipeline gaps; 4-phase roadmap) |
| Renderer / engine gotchas | [`godot-patterns.md`](godot-patterns.md); portable heuristics: [`godot-learnings-for-new-projects.md`](godot-learnings-for-new-projects.md) |
| Asteroid HDR-2D darkening | **FIXED 2026-06-24** — [`asteroid_hdr_darkening_2026-06-23.md`](asteroid_hdr_darkening_2026-06-23.md) (asteroid shader wrote alpha-0 fragments → crushed over HDR-bright; now opaque-or-discard in `Planets/Asteroids/Asteroids.gdshader`) |
| UI palette | [`ui_color_reference.md`](ui_color_reference.md) |
| Controller support | [`controller_support_plan_2026-06-05.md`](controller_support_plan_2026-06-05.md) — **designed, not built** |
| Intercept signal events | [`intercept-signal-events.md`](intercept-signal-events.md) — **backlog idea, not built** |
| Working trackers | [`../Worklist.md`](../Worklist.md) (canonical current index) · [`../TODO.md`](../TODO.md) (backlog) · `../Worklog.md` (history) |

Everything under [`archive/`](archive/) is superseded/historical — kept for design history only.

**Open code follow-ups** (code decisions surfaced by the doc audit, not doc issues):
[`code_followups_2026-06-15.md`](code_followups_2026-06-15.md).

## Ground-truth anchors (verify against code if a doc disagrees)

These are the migrations older docs most often pre-date. If a doc contradicts one of these, the
doc is stale:

1. **Renderer / target** — `forward_plus`, Windows-only. Web/HTML5 export was retired 2026-06-10.
   `gl_compatibility` is the old renderer.
2. **Engine** — Godot 4.6.3 standalone, **no Mono** (consolidated 2026-05-26 from a 4.3-Mono +
   4.4.1-standalone split).
3. **File layout** — `scripts/` has no root `.gd` files; everything is under
   `scripts/{autoload,game,hud,screens,parts,parallax,levels,systems,enemies/…}/` (reorg 2026-06-14).
   Bosses under `scripts/enemies/bosses/`.
4. **Player slots** — live build axes are `CANNON` (primary), `HARDPOINT_WING` (secondary),
   `DEVICE_BAY_1` (Smart Bomb super), `SHIFT_MODE` (Focus/Phase/Hyper), `MODULE` (a 6-slot passive
   **list** bay), and `ENGINE`. `WING_LEFT/RIGHT`, `TAIL`, `SHIELD`, `HARDPOINT_WINGTIP`,
   `DEVICE_BAY_2` are vestigial enum entries with no Part.
5. **Outpost** — a persistent, boss-refreshed **hub button**, not a per-row POI node.
6. **Viewport** — internal 480×270 (4× = 1920×1080); gameplay band X 132–348.
7. **Weapon stats** — live in `resources/weapons/*.tres`, not the weapon scripts (centralized 2026-06-11).
8. **Sector map** — routed scene is `sector_map_hd.tscn`, which wraps `sector_map_v3` in a SubViewport.

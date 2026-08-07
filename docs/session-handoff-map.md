# Session handoff map

**Status: CURRENT** (2026-08-07). A partition of Starblaster into **16 work sections** so that
separate Claude sessions can be handed independent slices without stepping on each other or
burning context on topic-swaps.

**How to use it:** pick ONE section per session. Paste its "Owns / Shared / Verify / Canon" block
into the opening prompt. If a task spans two sections, either sequence them (finish + commit one
first) or read the [Collision spine](#collision-spine) and decide who owns the shared file.

**The two rules that actually prevent overruns:**
1. **One session per section at a time.** Sections are context-disjoint by design; the shared
   files listed under [Collision spine](#collision-spine) are the only real overlap.
2. **Never let a session read a 2k+-line file whole.** See [Context cost](#context-cost) — a
   single unguarded `Read` of `player.gd` or `shader_lab.gd` costs ~45k tokens and derails the
   session before work starts.

---

## ⚠ Live workstream — read before dispatching anything

The working tree currently has **84 uncommitted entries**, essentially all in **§5 Ground assault
(strongholds & starbase)** and its blast radius: ground-building scene renames
(`building_*` → `b_<class>_<name>`), the new station prefab set, `scripts/systems/scene_light.gd`,
and edits reaching into `enemy_base.gd`, `mount_component.gd`, `enemy_roster.gd`, `factions.gd`,
four `parallax/` files, four `effects/` files, and `scene_transition.gd`.

Until that lands, treat **§1, §2, §11, §12** as **frozen for parallel work** — a second session
editing those files will conflict with unstaged changes it cannot see in `git log`. §7–§10 and
§13–§16 are safe to dispatch now.

---

## Quick index

| # | Section | Primary dirs | Parallel-safe now? |
|---|---|---|---|
| 1 | [Enemy chassis & behavior](#1-enemy-chassis--behavior-m6) | `scripts/enemies/{patterns,components}` | ❄ frozen |
| 2 | [Hardpoints, enemy weapons, projectiles](#2-hardpoints-enemy-weapons--projectiles) | `scripts/enemies/mounts`, `scripts/projectiles` | ❄ frozen |
| 3 | [Bosses](#3-bosses) | `scripts/enemies/bosses` | ✅ |
| 4 | [Waves, director & level structure](#4-waves-director--level-structure) | `scripts/levels` | ⚠ shares roster |
| 5 | [Ground assault: strongholds & starbase](#5-ground-assault-strongholds--starbase) | `scenes/enemies/ground` | 🔴 ACTIVE |
| 6 | [Hazards: asteroids & minefields](#6-hazards-asteroids--minefields) | `scripts/enemies/mine*`, `asteroid*` | ⚠ shares bake cache |
| 7 | [Player ship, parts & loadout](#7-player-ship-parts--loadout) | `scripts/parts`, `scripts/game/player.gd` | ✅ |
| 8 | [Run flow, sector map & economy](#8-run-flow-sector-map--economy) | `scripts/screens`, `scripts/autoload` | ✅ |
| 9 | [Outpost & deck life](#9-outpost--deck-life) | `scripts/screens/outpost*`, `deck_*` | ✅ |
| 10 | [HUD & UI framework](#10-hud--ui-framework) | `scripts/hud`, `scripts/ui` | ✅ |
| 11 | [VFX, shaders & effects](#11-vfx-shaders--effects) | `scripts/effects`, `graphics/*.gdshader` | ❄ frozen |
| 12 | [Parallax & backdrop](#12-parallax--backdrop) | `scripts/parallax` | ❄ frozen |
| 13 | [Audio & music](#13-audio--music) | `music_manager`, `*_sfx.gd` | ✅ |
| 14 | [Dev tools & tuner infrastructure](#14-dev-tools--tuner-infrastructure) | `scripts/dev` | ⚠ per-lab |
| 15 | [Build, perf & release](#15-build-perf--release) | `tools/*.ps1`, `project.godot` | ✅ |
| 16 | [Docs, assets & housekeeping](#16-docs-assets--housekeeping) | `docs/`, `graphics/` | ✅ |

---

## 1. Enemy chassis & behavior (M6)

Locomotion, movement patterns, chassis stats, components, faction tagging. The "how does this
enemy move and what is it made of" section.

- **Owns:** `scripts/enemies/{enemy_base,enemy_core,movement_pattern,ship_kinematics,hazard_spacing}.gd`
  · `scripts/enemies/patterns/**` (lane_path, drift, skirmish, loiter, omni_thrust, …)
  · `scripts/enemies/components/**` (EnemyComponent, Shield, Orbit, BeamChargeVisual)
  · `scripts/enemies/{core,factions/<faction>}/**` + mirrored `scenes/enemies/{core,factions}/**`
  · `scripts/systems/{lanes,lane_traffic,clarity}.gd`
- **Shared (coordinate first):** `scripts/levels/enemy_roster.gd` · `scripts/levels/factions.gd`
  · `scripts/levels/pattern_eligibility.gd` · `scripts/strings/enemy_strings.gd`
  · `scripts/dev/enemy_bench.gd`
- **Verify:** `tools/validate_bench_sync.gd` · `validate_pattern_eligibility.gd`
  · `validate_faction_purity.gd` · `audit_roster_movement.gd` · `clarity_audit.gd`
- **Canon:** `docs/m6_modular_enemies_design_2026-06-05.md` · `m6b_faction_tagging_2026-06-06.md`
  · `enemy_locomotion_reference.md` · `pattern_eligibility_2026-06-08.md`
  · `contributing/03-combat-waves-enemies.md`
- **Dev tools:** Enemy Bench · Lane Visualizer · Path Editor · Pattern Eligibility Editor
- **Skill/agents:** `/add-enemy`, `enemy-design`, `data-author`
- **Load-bearing rules:** prefer `enemy_core` + `movement`/`shoot_pattern` Resource slots over
  bespoke `_process`. Speeds go on a **clarity rung**, 8 px/f (480 px/s) hard ceiling.

## 2. Hardpoints, enemy weapons & projectiles

Everything that fires and everything that flies. Distinct from §1 (which owns the airframe).

- **Owns:** `scripts/enemies/mounts/{mount_spec,mount_component,mount_builder}.gd`
  · `scripts/enemies/shoot_patterns/{shoot_pattern,weapon,pair_shot}.gd`
  · `scripts/enemies/{beam_emitter,firing_scheduler,projectile_mods,enemy_turret,enemy_gun_turret,enemy_beam_turret}.gd`
  · `scripts/projectiles/**` · `scripts/weapons/{enemy_bullet,enemy_rocket,enemy_rocket_plain}.gd`
  · `scenes/projectiles/**` · `data/bullets/`
- **Shared:** `enemy_base.gd` (`bullet_speed_mult`/`bullet_damage_mult`) · `enemy_core.gd`
  (`_realize_shoot_pattern_mount`) · `enemy_roster.gd` (per-enemy mount specs)
- **Canon:** `docs/hardpoint_unification_design_2026-07-02.md` ·
  `hardpoint_v2_design_2026-07-05.md` (A+B+C shipped, unverified in play) ·
  `weapons_system_2026-06-05.md` · `multimesh_bullets_design_2026-06-19.md`
- **Dev tools:** Smart Mount Lab · Weapon Lab · Enemy Bench
- **Load-bearing rules:** hull firing is **unified through the mount engine** — no hull ShootTimer
  on non-boss enemies. Projectiles spawn as children of `get_tree().root`, never the spawner.

## 3. Bosses

Self-contained: separate base chain, separate firing path, separate scenes.

- **Owns:** `scripts/enemies/bosses/**` (boss_base, boss_phase, boss.gd + `boss_*.gd`)
  · `scenes/enemies/bosses/**` · `scripts/enemies/patterns/boss_sweep.gd`
  · `scripts/enemies/{aegis_pylon,conductor_satellite,destructible_part,bombing_run_attack}.gd`
- **Shared:** `enemy_base.gd` (parent class) · `wave_generator.gd` (boss roster, **keyed by
  script path**) · `main.gd` + `base_missile.gd` (boss detection by `resource_path` literal)
- **Canon:** `docs/design/boss_encounter_system.md` · `docs/design/Boss - Shepherd.md`
  · `docs/conductor_systems_review_2026-07-02.md`
- **Dev tool:** Boss Bench · **Agent:** `boss-composer`
- **Load-bearing rules:** each boss sets stats in `_ready()` **before** `super._ready()` (the
  `<=0 ? default` pattern caused a 1-HP bug). `boss_base.gd` has **no `class_name`** on purpose —
  three files compare `resource_path == "res://scripts/enemies/bosses/boss_base.gd"`. Bosses keep
  their own live `ShootTimer`; that is unrelated to §2's mount engine.

## 4. Waves, director & level structure

The producer: what spawns, when, in what shape, and how a level is paced.

- **Owns:** `scripts/levels/{wave_generator,levels_v2,director,formation_composer,formation_shapes,
  phrase,wave_def,level_def,authored_patterns,combat_score,score_adapter,score_wave}.gd`
  · `scripts/game/main.gd` (`new_game`, run outro)
- **Shared:** `enemy_roster.gd` (pulls from) · `factions.gd` (scoped filter) · `conditions.gd`
  · `pattern_eligibility.gd` · `scripts/dev/wave_pattern_editor.gd`
- **Canon:** `docs/level_structure_redesign_2026-07-01.md` (**BUILT, unverified in-game** — 3-part
  ~3-min levels, slot caps 16/26/36) · `wave_composition_guide_2026-06-03.md` ·
  `wave_pattern_editor_design_2026-06-15.md`
- **Dev tools:** Wave Pattern Editor · Combat Lab
- **Signals to know:** director emits `enemy_died` / `enemy_spawned` / `wave_started` /
  `level_cleared`; `level_cleared` → `main._run_outro()`.

## 5. Ground assault: strongholds & starbase 🔴 ACTIVE

Base-assault level type — the ship flies **over** terrain and shoots the structures on it.

- **Owns:** `scripts/levels/{stronghold_field,asteroid_strongholds}.gd`
  · `scripts/enemies/{asteroid_stronghold,stronghold_building_palette}.gd`
  · `scripts/enemies/core/{composed_building,landing_pad,cannon_bay,enemy_core_building_turret}.gd`
  · `scenes/enemies/ground/**` (22 `b_*` buildings + `station/prefab_*.tscn`)
  · `scenes/levels/starbase.tscn` · `scripts/systems/scene_light.gd`
  · `graphics/{building_shadow,planet_ground}.gdshader` · `scripts/effects/building_{boom,shadow}.gd`
- **Shared:** `enemy_roster.gd` · `factions.gd` · `parallax/{flyover_backdrop,layer_planet,
  stellar_gameplay,asteroid_shadow_rig}.gd` · `systems/scene_transition.gd`
- **Verify:** `tools/validate_station_prefabs.gd` · `tools/validate_scene_light.gd` (`VERDICT: PASS`)
- **Canon:** `docs/starbase_assault_design_2026-07-28.md` · `scene_light_direction_2026-07-28.md`
  · `flyover_combat_backdrop_design_2026-07-18.md`
- **Dev tool:** Asteroid Stronghold Editor
- **Load-bearing gotcha:** the `sun_dir` uniform means the **light** direction in
  `planet_ground.gdshader` but the **shadow** direction in `building_shadow.gdshader` — use
  `light_dir()` vs `shadow_dir()`. Backwards is a silent 180° flip.
- **Ground rule:** the stronghold code is the reference where it and the starbase doc disagree.

## 6. Hazards: asteroids & minefields

Non-wave obstacles conducted through the wave conductor.

- **Owns:** `scripts/enemies/{asteroid,mine,mine_base,mine_shielded,mine_smart,gravity_mine,
  tether_mine,firecore_core,firecore_hazard}.gd` · `scripts/levels/{asteroid_pepper,hazard_shapes}.gd`
  · `scripts/effects/{asteroid_explosion,asteroid_fragment}.gd`
  · `scripts/parallax/{asteroid_bake_cache,asteroid_shadow_rig}.gd` · `scenes/hazards/`
- **Shared:** `levels_v2.gd` (`build_minefield` / `asteroid_field_level`) · `director.gd`
  · `Run.set_meta("minefield_mine_type")`
- **Canon:** `docs/asteroid_hdr_darkening_2026-06-23.md` (FIXED — shader is opaque-or-discard)
- **Dev tools:** Asteroid Lab · Asteroid Bake Lab
- **Open item:** the asteroid bake path is built but dev-gated (`AsteroidBakeCache.enabled`
  default OFF); productionizing it is a standing TODO.

## 7. Player ship, parts & loadout

The player half of combat, plus the Mk.1–9 upgrade system.

- **Owns:** `scripts/game/{player,ship,player_alarms}.gd` · `scripts/parts/**` (70+ Part scripts +
  PartFactory/PartCatalog/PartTier) · `scripts/weapons/{loadout,player_loadout,SlotTypes,
  WeaponStyle,shell_eject_small}.gd` · `resources/weapons/*.tres` · `scenes/player/**`
- **Shared:** `run_state.gd` (loadout snapshot) · `scripts/hud/hud_weapon_status.gd`
  · `scripts/screens/outpost.gd` (shop stock)
- **Verify:** `tools/validate_weapon_data.gd` → must print `VERDICT: PASS`
- **Canon:** `contributing/04-player-parts-economy.md` · `weapon_data_centralization_2026-06-11.md`
  · `weapon_dps_report_2026-06-13.md` · `shift_mode_system_2026-06-08.md`
  · `passive_module_bay_2026-06-13.md` · `ship_starting_loadouts_2026-07-11.md`
  · `ship_unlock_system_2026-07-11.md`
- **Dev tools:** Hangar/Shipyard · Weapon Lab · Player FX Lab · **Skill/agents:** `/add-part`,
  `part-author`, `economy-sim`
- **Load-bearing rules:** **weapon stats live in the `.tres`, not the script** — a weapon's
  `_init()` sets identity + behavior only. Shield is a **charge pool**, not a damage bar.

## 8. Run flow, sector map & economy

The meta layer between combat nodes.

- **Owns:** `scripts/screens/{sector_map_v3,sector_map_hd,cleared_summary,run_summary,run_history,
  main_menu,pause_menu,loading_screen,credits,onboarding,signal_event,enemy_codex}.gd`
  · `scripts/systems/{sector_node,sector_map_route,conditions,scene_transition,scene_transition_overlay,
  level_launcher,black_hole}.gd` · `scripts/autoload/{run_state,settings}.gd` · `scripts/game/run_save.gd`
  · `scripts/systems/outpost_econ.gd` · `scripts/strings/sector_name_generator.gd`
- **Shared:** `main.gd` (combat handoff) · the `Run.set_meta(...)` one-shot config contract
  · `parallax/backdrop_coordinator.gd` (map POI → backdrop)
- **Verify:** `tools/validate_reachability.gd`
- **Canon:** `docs/sector_conditions_redesign_2026-07-06.md` (**SCOPED / NOT BUILT** — wiring sits
  behind `Run.SECTOR_MODIFIERS_ENABLED`) · `signal_event_redesign_2026-06-08.md` ·
  `intercept-signal-events.md` (backlog idea) · `contributing/02-architecture.md`
- **Dev tool:** the `scripts/dev/sector_map_v3.gd` variant (note: **distinct file** from the
  `screens/` one — check which you're editing)

## 9. Outpost & deck life

The hub scene and its cinematic dock. Big, self-contained, and mostly disjoint from combat.

- **Owns:** `scripts/screens/{outpost,outpost_arrival,deck_life,deck_crew,deck_vehicle,hangar_stage,
  hangar_clutter,patrol_start,part_stats_view}.gd` · `scenes/outpost/**`
  · `scenes/{outpost,outpost_arrival,hangar,hangar_stage,patrol_start}.tscn`
  · `scripts/effects/{dock_const,dock_shadow_rig,outpost_sfx}.gd`
- **Shared:** `run_state.gd` (bounty/Materials) · `part_catalog.gd` (shop stock) · `Music`
  context `"outpost"`
- **Canon:** `docs/deck_life_plan_2026-07-04.md` (**IN PROGRESS** — Phase 0–3 partial; crew wander
  + weld + crate carry BUILT, vehicle runs + real art NOT) · `patrol_setup_handoff_2026-06-27.md`
- **Dev tool:** Outpost Arrival Lab

## 10. HUD & UI framework

- **Owns:** `scripts/hud/**` (ui.gd root + 12 widgets) · `scripts/ui/**` (HdScreen, ui_theme,
  options_overlay, ship_select_overlay, summary_ui, menu_backdrop, volume_slider)
  · `scenes/hud/**` · `scenes/ui.tscn` · `scripts/strings/**`
- **Shared:** player signals (`hull_changed`, weapon state) · director wave signals · `run_state`
- **Canon:** `docs/ui_color_reference.md` · `contributing/05-projectiles-effects-visuals.md`
- **Dev tool:** UI Designer (`tools/build_ui_theme.gd` regenerates the theme)
- **Load-bearing rules:** gameplay is a **216×270 band (X 132–348)** — always import
  `scripts/systems/playfield.gd`, never `get_viewport_rect()`. Layers: Glass=1, HUD=5, Outline=10.

## 11. VFX, shaders & effects

- **Owns:** `scripts/effects/**` (~70 static-helper modules) · `graphics/*.gdshader` · `shaders/`
  · `scenes/effects/**` · `scripts/effects/{recycle_controller,death_effects,ship_damage_tells,
  combat_postfx,vfx_glow_config,sprite_baker}.gd`
- **Shared:** `enemy_base.gd` (`explode`, debris) · `player.gd` (damage tells)
  · `base_bullet.gd` (`BULLET_HDR_GAIN`) · `systems/scene_light.gd`
- **Canon:** `contributing/05-projectiles-effects-visuals.md` · `godot-patterns.md`
  · `asteroid_hdr_darkening_2026-06-23.md`
- **Dev tools:** Shader Lab · Combat VFX Lab · Sequence Lab · Player FX Lab · Recycle Tuner
- **Agents/skills:** `vfx-author`, `/capture`
- **Load-bearing rules:** explosions always **1× scale** (more blasts, never stretched sprites);
  debris drifts downward from frame 0 (never freeze-then-fall); under `use_hdr_2d` a shader
  writing **alpha-0 fragments** crushes to black over >1 content — use opaque-or-discard.

## 12. Parallax & backdrop

- **Owns:** `scripts/parallax/**` (backdrop_coordinator + layer_{stars,stellar,planet,streaks},
  galaxy_backdrop v1/v2/v3, flyover_backdrop/planner, stellar_composer/gameplay, bg_mine)
  · `scenes/parallax/**` · PixelPlanets/`Planets/` kit placement
- **Shared:** sector-map POI data → `backdrop_coordinator._populate` (also publishes the
  star-reactive sun swing) · `systems/scene_light.gd` · `asteroid_bake_cache.gd`
- **Canon:** `docs/parallax_backdrop_review_2026-07-06.md` (**the handoff doc** — why depth reads
  wrong: bunched scroll ratios, inverted brightness ramp, 6 color authorities, conveyor motion;
  **P0 global-RNG reseed bug**; dead V1/V2/V3; 4-phase roadmap) · `parallax_v4_showcase_plan_2026-07-06.md`
  · `parallax_rework_safe_rebuild_2026-06-18.md`
- **Dev tools:** Parallax Tuner · Nebula Lab · Planet Flyover Lab · Parallax Showcase
- **Load-bearing rule:** every PixelPlanets scene needs the 3-step pixel-parity setup —
  set `scale`, **`add_child()` first**, *then* `_apply_pixel_parity()`. Skipping the order
  silently mismatches shader cells.

## 13. Audio & music

Cleanly isolated — a good candidate for a parallel session any time.

- **Owns:** `scripts/autoload/music_manager.gd` · `scripts/systems/{music_library,music_library_data}.gd`
  · `scripts/effects/*_sfx.gd` (enemy, engine, explosion, laser, mine, outpost, shield, weapon)
  · `assets/audio/**` · `default_bus_layout.tres`
- **Verify:** `tools/validate_music_library.gd` · regenerate with `tools/build_music_library.gd`
- **Canon:** `docs/ovani_music_migration_2026-06-24.md`
- **Dev tool:** Music Lab
- **Contexts:** `Music.set_context("menu"/"combat"/"boss"/"outpost"/…)` — read `music_manager.gd`
  for the live list.

## 14. Dev tools & tuner infrastructure

Per-lab work is independent; the shared surface is `dev_menu.gd` and the HdScreen contract.

- **Owns:** `scripts/dev/**` (43 tools) · `scenes/dev/**` · `scripts/dev/dev_menu.gd`
- **Shared:** `scripts/ui/hd_screen.gd` (lab preview contract) · whatever system the lab previews
  · `scripts/dev/enemy_bench.gd` ↔ `enemy_roster.gd` (see `validate_bench_sync.gd`)
- **Canon:** `docs/dev_tool_unification_design_2026-07-07.md` · `contributing/01-getting-started.md`
  · `contributing/enemy-bench-guide.md` · **agent:** `tuner-builder`
- **Two hard contracts:**
  1. **Copy GDScript button** on every tuner, emitting a paste-ready snippet. Without it the
     human→agent handoff is broken.
  2. **Lab preview parity:** host gameplay in `HdScreen.make_play_subviewport(...)`, or call
     `HdScreen.apply_native_parity(vp)` on a hand-built one; register the world node in the
     `"bullet_world"` group; add `HdScreen.verify_native_subviewport.call_deferred(vp, "<lab>")`.
     SubViewports do **not** inherit `hdr_2d` / `snap_2d_transforms_to_pixel`.
- **Authoritative tool list:** read `scripts/dev/dev_menu.gd` — it drifts constantly.

## 15. Build, perf & release

- **Owns:** `tools/{parse_check,publish,smoke,perf,godot,run_renderer}.ps1`
  · `tools/{compile_check,clarity_audit}.gd` · `export_presets.cfg` · `project.godot`
  · `scripts/autoload/crash_log.gd` · `tools/perf_baseline.json`
- **Canon:** `TODO.md` § "Efficiency / burst-reduction backlog" — MultiMesh bullets (**IN
  PROGRESS**), productionize the asteroid bake, shared particle emitters, level enemy pools +
  shared materials, export-time Shader Baker · `docs/multimesh_bullets_design_2026-06-19.md`
- **Agents:** `publish-gate` (every publish), `perf-runner`, `smoke-runner`, `regression-bisect`
- **Hard rules:** publish only via `tools/publish.ps1 -Version "0.1.NN"` — **never `butler push`
  directly**, and never push without explicit confirmation. Pre-ship: set
  `crash_log.gd  ENABLED = false`.
- **Engine:** Godot 4.6.3 standalone; path is duplicated in `parse_check.ps1` **and**
  `publish.ps1` — update both. `max_fps=60` is intentional; do not raise it.

## 16. Docs, assets & housekeeping

- **Owns:** `docs/**` · `CLAUDE.md` · `TODO.md` / `Worklist.md` / `Worklog.md` · `README.md`
  · `ONBOARDING.md` · `reports/**` · `graphics/**` imports + `.import` sidecars
- **Canon:** `docs/README.md` is the **doc canon index** — it says which doc is live vs archived.
  `docs/file-structure.md` holds the **move-safety checklist**.
- **Agents/skills:** `asset-importer`, `design-reviewer`
- **Deferred backlog (high surface, low value — do as one mechanical batch or not at all):**
  `graphics/` → `assets/graphics/` prefix replace · `Mini Pixel Pack 3/` → `vendor/` (note the
  spaces in the path) · orphan cleanup per `docs/archive/file_reorg_audit_2026-06-14.md` §2 and
  `reports/orphan_audit_2026-07-17.md`
- **Doc hygiene rule:** every new design doc gets a one-line `Status:` header; superseded docs
  move to `docs/archive/` with a banner rather than being deleted.

---

## Collision spine

These files are touched by **multiple** sections. They are where parallel sessions actually
collide. Counts are edits across the last 200 commits.

| File | Edits | Sections that write it | Handoff rule |
|---|---|---|---|
| `scripts/levels/enemy_roster.gd` | 46 | 1, 2, 4, 5, 6 | **The #1 collision file.** One session at a time, full stop. Splitting it is the one load-bearing refactor — see [Refactor candidates](#refactor-candidates). |
| `scripts/dev/enemy_bench.gd` | 32 | 1, 14 | Must stay in sync with the roster — run `validate_bench_sync.gd`. Bundle with whoever edits the roster. |
| `scripts/enemies/mounts/mount_component.gd` | 19 | 2, 5 | §2 owns it; §5 borrows. Sequence, don't parallelize. |
| `scripts/levels/factions.gd` | 17 | 1, 4, 5 | §1 owns `ENEMY_TAGS`; §4 owns `pick_for_level`/`allowed_in`. Split by function if you must overlap. |
| `scripts/levels/director.gd` | 16 | 4, 6 | §4 owns it. §6 only via the hazard conductor path. |
| `scripts/game/player.gd` | 13 | 7, 10, 11 | §7 owns it. §10/§11 read signals, don't edit. |
| `scripts/enemies/enemy_base.gd` | 12 | 1, 2, 3, 5, 11 | §1 owns it. Any other section editing it is a smell — push the change into a component or pattern instead. |
| `scripts/game/main.gd` | 8 | 3, 4, 8 | §4 owns combat setup; §8 owns the scene handoff. |
| `scripts/autoload/run_state.gd` | 7 | 7, 8, 9 | §8 owns it. Others go through `Run.set_meta(...)`. |
| `scripts/strings/enemy_strings.gd` | 7 | 1, 10 | Keyed **by scene path** — renaming an enemy scene silently breaks it at runtime, never at parse. |
| `scripts/dev/dev_menu.gd` | 5 | 14 (+ any section adding a lab) | Append-only; keep the diff to one function. |

**Silent-failure class to warn every session about:** runtime `resource_path == "res://..."`
comparisons and dicts keyed by a path (`enemy_strings`, the `wave_generator` boss roster,
`boss_base` detection in `main.gd`/`base_missile.gd`). These never fail at parse — only at
runtime. Any file move or scene rename must grep for literals, not just rely on `uid://`.

---

## Context cost

Sections whose central file is huge. A session dispatched here should be told to read **targeted
ranges** (`Grep` for the symbol, then `Read` with `offset`/`limit`) rather than the whole file.

| File | Lines | ~Tokens if read whole | Section |
|---|---|---|---|
| `scripts/dev/shader_lab.gd` | 4014 | ~45k | 14 / 11 |
| `scripts/game/player.gd` | 3679 | ~43k | 7 |
| `scripts/screens/outpost_arrival.gd` | 3277 | ~33k | 9 |
| `scripts/dev/enemy_bench.gd` | 2871 | ~35k | 14 / 1 |
| `scripts/levels/enemy_roster.gd` | 2501 | ~33k | 1 (shared) |
| `scripts/screens/patrol_start.gd` | 2307 | ~25k | 9 |
| `scripts/screens/outpost.gd` | 2185 | ~22k | 9 |
| `scripts/screens/sector_map_v3.gd` | 2046 | ~23k | 8 |
| `scripts/levels/director.gd` | 1971 | ~26k | 4 |
| `scripts/autoload/run_state.gd` | 1805 | ~20k | 8 |
| `scripts/levels/wave_generator.gd` | 1521 | ~22k | 4 |
| `scripts/enemies/enemy_base.gd` | 1422 | ~18k | 1 |

Reading any three of these blows half a context window before a line is written.

---

## Refactor candidates

Should the big files be split to remove the bottleneck? **For two of them, yes** — and for the
most valuable one the payoff is *collision* relief, not context. Verdicts below are grounded in
coupling counts, not line counts.

**Splitting the work-sections above does NOT help.** §7 divided into "player core / parts" still
leaves `player.gd` as one 3679-line file that whoever draws §7a must read. A section boundary
cannot fix a file-size problem; only a file split can.

| File | Lines | Verdict | Why |
|---|---|---|---|
| `scripts/levels/enemy_roster.gd` | 2501 | ✅ **SPLIT — do this one** | 1600 lines are one const literal; the data already partitions along the §1/§5 boundary |
| `scripts/dev/shader_lab.gd` | 4014 | ✅ **SPLIT — cheap** | ~18 self-contained modes; dev tool, so near-zero regression surface |
| `scripts/game/player.gd` | 3679 | ⚠ **PARTIAL — Smart Mounts only** | 39 Part files reach into 82 fields incl. privates; wholesale split is unsafe |
| `outpost_arrival` / `patrol_start` / `outpost` | 3277/2307/2185 | ❌ no | all §9 — one session owns all three and never needs them at once |
| `scripts/dev/enemy_bench.gd` | 2871 | ❌ not yet | only 3 tab seams; roster-coupled, so it must follow the roster split |
| `director` / `wave_generator` / `run_state` / `enemy_base` | 1400–2000 | ❌ no | cohesive; the size is what the cohesion costs |

### 1. `enemy_roster.gd` — split `ENTRIES` by faction/ground

The 2501 lines are **~1600 of const array literal** (`ENTRIES`, L218–1817, 107 entries) wrapped in
~900 lines of logic. The seam is already latent in the data:

| scene-path prefix | entries | owned by |
|---|---|---|
| `res://scenes/enemies/factions/` | 75 | §1 |
| `res://scenes/enemies/ground/` | 21 | §5 |
| `res://scenes/enemies/core/` | 11 | §1 |

That ground-vs-faction line is exactly the §5/§1 boundary colliding today. **This is the only
refactor here that is load-bearing** — it takes the #1 collision file (46 edits, 5 sections) and
lets §1 and §5 run in parallel. Context relief is the side benefit.

- **Feasibility (verified):** only four real consumers of `ENTRIES` outside the file, and **zero
  const-context consumers** — so `const` → `static var` built in `_static_init()` keeps
  `EnemyRoster.ENTRIES` source-compatible for every reader.
- **Loose end:** `scripts/enemies/stronghold_building_palette.gd:75` carries a comment asserting
  "Safe to cache: ENTRIES is a const" — behavior stays correct, but update the comment.
- **Verify:** `validate_bench_sync.gd` · `audit_roster_movement.gd` · `validate_faction_purity.gd`

### 2. `shader_lab.gd` — one file per mode

~18 banner-delimited modes (Embers, Smoke trail, Player Modes, Explosions, Explosion Tuner, Ship
Damage, Death effects, Nebula, Asteroids, Firecore Glow, Star Glow, Halo, Bloom Env, Glow, Damage,
Damage Smoke, Building Shadow, Building Boom), each with its own state block + build func and
almost no cross-talk. Target: a ~300-line host + mode registry, one `shader_lab_<mode>.gd` each.

It's a **dev tool** — not shipped, so the regression surface is "does the lab still open."
Cheapest split in the codebase.

### 3. `player.gd` — extract Smart Mounts, leave the rest

The obvious candidate, and mostly the wrong one. **39 Part files reach into the ship across 82
distinct fields**, and not through a stat interface — they poke privates (`ship._beam_active`,
`ship._burst_phase`, `ship._invuln_t`, `ship._on_mode_changed`). Decomposing into component nodes
means redirecting 82 field paths across 39 files while preserving `apply`/`unapply` symmetry in
each, and the failure mode is **silent stat drift, not a parse error**. Don't.

**The one worthwhile extraction:** the Smart Mounts banner (L1995–3611) is **1616 lines / 60 funcs
— 44% of the file** — and Parts touch it only through ~15 flat `ship.module_*` scalars, never its
internals. That's a real boundary. Extracting it lands `player.gd` at ~2050 lines for the cost of
one narrow interface.

### Order of operations

1. **Smart Mounts extraction** (§7) — §7 is clear right now; can start immediately.
2. **`enemy_roster` `ENTRIES` split** (§1 + §5) — **blocked** until §5's uncommitted tree lands;
   it has live edits to that file.
3. **`shader_lab` mode pages** (§14) — also blocked on §5 (it's in the uncommitted set).

**Only #2 is load-bearing.** The grep-then-range-read mitigation in [Context cost](#context-cost)
costs nothing and works today, so #1 and #3 are convenience cleanup. #2 buys parallel §1/§5
sessions, which no amount of careful reading can.

---

## Parallel-safety matrix

**Safe to run simultaneously** (no shared writes):
- §3 Bosses ‖ §9 Outpost ‖ §13 Audio ‖ §16 Docs
- §7 Player/Parts ‖ §10 HUD (as long as HUD only *reads* player signals)
- §8 Run flow ‖ any combat-content section
- §15 Build/perf ‖ anything — but it must run **after** the others commit, or the gate lies

**Never simultaneously:**
- §1 ‖ §2 ‖ §4 ‖ §5 — all write `enemy_roster.gd`
- §1 ‖ §14 when the lab is Enemy Bench — bench-sync validator will fail
- §11 ‖ §12 — both write the lighting/shader surface (`scene_light.gd`, `*.gdshader`)
- §5 ‖ anything in §1/§2/§11/§12 **right now** — the uncommitted tree spans all four

---

## Handoff prompt template

```
Section: §N <name> (docs/session-handoff-map.md)

Task: <the actual ask>

You own: <paste the "Owns" list>
Do NOT edit: <paste the "Shared" list> — coordinate with me first if you need one.
Canon: <paste the "Canon" doc list>. Read CLAUDE.md first; the code wins over any doc.
Dev tool: <the lab> — if this needs 3+ knobs iterated, ask me to run the tuner and paste
values back. Do not iterate by edit-capture-look.
Verify: tools/parse_check.ps1 + a headless boot, plus <the section's validator>.
Context: <big file> is <N> lines — grep for the symbol and Read a range, never the whole file.
Finish with: /ship
```

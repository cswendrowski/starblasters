# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Godot 2D top-down vertical shmup (GDScript). Roguelite with branching sector map, slotted parts, Mk.1–9 upgrade scaling. Renderer: `forward_plus` (pivoted from `gl_compatibility` 2026-06-10; distribution is Windows-only now — the Web pipeline is retired). **Internal viewport 480×270, 4× display = 1920×1080.** Gameplay constrained to **216×270 playfield band (X 132–348)**. Side gutters host glass panels + HUD. **Always import `scripts/systems/playfield.gd` (`Playfield.X_MIN`, `X_MAX`, `CENTER`, `clamp_pos`) for gameplay bounds — never `get_viewport_rect()`** (returns full 480 width). Backdrop/despawn margins may read the viewport directly.

## Engine version

**Godot 4.6.3 standalone** (no Mono) — single binary for editor + export. Consolidated from a 4.3-Mono editor + 4.4.1-standalone exporter split on 2026-05-26 since the project never used C#. Binary path lives in `tools/parse_check.ps1` and `tools/publish.ps1`; update both if it moves. (A `_console.exe` variant sits beside it — reliable stdout on Windows when you need to capture output.)

## Running / building

- Headless smoke: `godot --path . --headless --quit-after 2`
- Full parse check: `tools/parse_check.ps1`
- Publish: `tools/publish.ps1 -Version "0.1.NN"` — bumps version, runs parse_check, exports the WINDOWS preset ("Starblaster", embedded pck → single exe in `../Starblaster_win/`), mtime-validates the exe, then `butler push` to `tikibones/starblaster:windows`. **Never `butler push` directly.** Don't push without explicit user confirmation. (Web/html channel retired with the 2026-06-10 Forward+ pivot.)

## Workflow: human-iterated, agent-consumed

Context is the scarce resource. Iteration-heavy work belongs in a dev tuner the **human** runs.

**For UI/HUD layout, visual tuning, or numeric balance:**
- Existing tuners include `UI Designer`, `Parallax Tuner`, `Wave Tester`, `Asteroid Lab`, `Movement Lab`, `Shipyard` (current list lives in `scripts/dev/dev_menu.gd` / `docs/contributing/01-getting-started.md`). Ask Roman to run one and paste the exported values. Do not iterate by edit-capture-look.
- No tuner for a 3+-knob system? Scaffold one first (see `scripts/dev/ui_designer.gd` as reference — JSON persist to `user://tuners/<name>.json`).
- **Tuner contract:** every tuner must have a **Copy GDScript** button emitting a paste-ready snippet. Without it the handoff is broken.

**For visual mechanics:** write `tools/capture_<mechanic>.gd` + `.ps1` → ffmpeg → GIF in `captures/`. Hand Roman the GIF path to review; don't read PNG frames yourself unless actively debugging a specific visual bug. (Discord/external posting is retired — produce the artifact and report its path.)

## Input map

Actions: `left`/`right`/`up`/`down` (arrow keys), `shoot` (Space/Z), `shoot2` (C), `shoot_nose` (X), `focus` (Shift), `primary_swap` (G), `autofire_toggle` (A), `smart_mount_toggle` (S). Bindings drift — `project.godot` `[input]` is the source of truth; confirm there before relying on a specific key. (Rebindable in `scripts/ui/options_overlay.gd`'s Controls list.)

## Autoloads (`/root/...`)

- `Run` (`scripts/autoload/run_state.gd`) — run state: bounty, hull/shield, loadout snapshot, sector_map_cache, current_node_id/type, current_hazard_subtype, sectors_cleared, run_seed. `Run.new_run()` resets. One-shot config via `Run.set_meta(...)` (e.g. `wave_v2_knobs`, `forced_boss_scene`, `minefield_mine_type`).
- `Dbg` — debug helpers
- `Music` — context-aware BGM (`set_context(...)`, e.g. `"menu"`/`"combat"`/`"boss"`/`"outpost"`; see `scripts/autoload/music_manager.gd` for the contexts it handles)
- `Settings` — persisted user prefs

## Architecture

> **This section is a terse map for orientation. The detailed, newbie-friendly
> tour lives in `docs/contributing/` (verified against code).** Keep load-bearing
> RULES here; for volatile FACTS (exact scene names, thresholds, dev-tool lists)
> the code + the contributing docs are the source of truth — point, don't copy.
>
> **File layout + where new files go: `docs/file-structure.md`.** Relocating a file is
> reference-fragile (uid + literal paths) — follow that guide's move-safety checklist.

### Scene flow
`main_menu.tscn` → `main.tscn` (combat) ↔ `sector_map_v3.tscn` → `outpost.tscn` / `signal_event.tscn` / `cleared_summary.tscn` / `run_summary.tscn`. Forward-only branching grid (see `docs/contributing/02-architecture.md` for the grid details). Confirm the live sector-map scene in `main_menu.gd`/`main.gd` rather than trusting this line.

### Combat flow (`scripts/game/main.gd`)
`new_game()` builds `LevelData` via `WaveGen.build()` (= `WaveGenerator.build()`, production) or `Levels.build_minefield/asteroid_field_level()` (hazard nodes); the dev wave-authoring tool is `scripts/dev/wave_editor.gd`. `director.gd` walks `WaveSpec`s and emits `enemy_died` / `enemy_spawned` / `wave_started` / `level_cleared`; `level_cleared` → `_run_outro()` → fly-out → wipe → cleared summary. Full walkthrough: `docs/contributing/03-combat-waves-enemies.md`.

### Enemies (`scripts/enemies/` + `scripts/enemies/enemy_core.gd`)
- `scripts/enemies/enemy_base.gd` — base (`Area2D`, `class_name EnemyBase`). Health, `take_hit`, `explode`, engine flame + parallax shadow + damage overlay shader (gated by `auto_rotate`), debris on death, offscreen cleanup. Also holds the `components: Array` slot (M6) + `bullet_speed_mult`/`bullet_damage_mult` weapon scalars.
- `scripts/enemies/enemy_core.gd` (alongside `enemy_base.gd` since the 2026-06-14 reorg) — extends the base, adds `movement: Resource` + `shoot_pattern: Resource` slots. Ticks components; attaches a `BeamEmitter` when the weapon is a beam.
- `patterns/` — movement Resources; subclass `movement_pattern.gd`, override `compute_step(enemy, delta) -> Vector2`.
- Custom enemies (bomber, bulwark v2) extend `enemy_base.gd` directly, expose `hull`/`max_hull` + `hull_changed` signal.
- **Directory layout (M6b §11 reorg):** concrete enemy scenes + their bespoke scripts live under `scenes/enemies/core/` (universals) + `scenes/enemies/factions/<faction>/` (exclusives), mirrored in `scripts/enemies/`. Sub-units (turrets), hazards/mines, bosses, projectiles stay flat in `scenes/enemies/`. `enemy_core`-based scenes keep referencing the shared `scripts/enemies/enemy_core.gd`.

**Enemy convention:** When adding new enemies, prefer extending `enemy_core.gd` and declaring movement/shoot behavior via the `movement` and `shoot_pattern` resource slots over inline bespoke `_process` logic. Check `scripts/enemies/patterns/` and `scripts/enemies/shoot_patterns/` for existing patterns before writing new movement code. Reserve bespoke scripts for behavior that genuinely cannot be expressed as a pattern (complex state machines, multi-phase locomotion, continuous-effect weapons).

### Modular enemy system (M6 — composed enemies)
An enemy = **chassis (size) + behavior (movement) + weapon + components**, with a **faction** overlaid at spawn. The four axes (all live, all on `enemy_core`/`enemy_base`):
- **Behavior** — lane-aware movement. `scripts/enemies/patterns/lane_path.gd` is the production lateral engine (WEAVE=Weaver, HOOK=Shifter/zone-timed Drifter, STEP=synced step-wall). `scripts/systems/lane_traffic.gd` = on-demand lane-occupancy query for lane-changers. Conductor row choreography (crosser stagger, step_wall) in `director.gd`.
- **Component** — `scripts/enemies/components/` (`EnemyComponent` base + `ShieldComponent`, `EmitterComponent`). Optional hooks (on_start/process/hit/death/leave); registry on `enemy_base`, ticked by `enemy_core`, duplicated per-instance. Damage routes through `_components_hit` before hull.
- **Weapon** — `scripts/enemies/shoot_patterns/weapon.gd` (extends `shoot_pattern.gd`): `fire_pattern` (single/aimed/spread/burst/**beam**), payload `BulletVariant`, single-sourced rate, aim, movement axis (homing/wobble live on `base_bullet`). Beams: shared `scripts/enemies/beam_emitter.gd` node (FSM + layered Line2D + width-aware DPS + aim modes + Chase/Lock); Beamer/Burner/Turret are thin configs of it.
- **Faction** — `scripts/levels/factions.gd` (`Factions`, preload-referenced, NOT class_name). 4 factions (supremacy/privateer/corporate/zealot) as data: `ENEMY_TAGS` (per-enemy home + universal), `allowed_in`, `pick_for_level`, `apply` (per-spawn overlay: components + stat/weapon mults). Producer wiring: `WaveGen.build(...,faction)` sets a scoped `Roster` faction filter (universal + home enemies only); `main.gd` picks the level faction → Run meta `active_faction`; `director._spawn_enemy` applies the overlay. Dev: Test Combat → "Faction…" forces one. Design: `docs/m6_modular_enemies_design_2026-06-05.md` + `docs/m6b_faction_tagging_2026-06-06.md`. Gap-unit sprite backlog: `TODO.md`.

### Bosses (`scripts/enemies/bosses/`)
All boss scripts + scenes live under `scripts/enemies/bosses/` + `scenes/enemies/bosses/` (consolidated 2026-06-14). All bosses extend `scripts/enemies/bosses/boss_base.gd` (itself extends `enemy_base.gd`); each is its own variant script — `scripts/enemies/bosses/boss.gd` (Commander) plus `boss_{aegis,conductor,howler,reaver,spinwright,voidmaw}.gd`. Phase state machines use `boss_phase.gd` (a `Resource`). The roster drifts — read `scripts/enemies/bosses/` + `scenes/enemies/bosses/`, don't trust a hardcoded list here. **boss_base has NO class_name (path-based on purpose) — `main.gd`/`base_missile.gd` recognize a boss via `resource_path == "res://scripts/enemies/bosses/boss_base.gd"`; keep those literals in sync if it ever moves again.** **Each boss sets its stats in `_ready()` BEFORE calling `super._ready()` — never via the `<= 0 ? default` pattern (caused a 1-HP bug).** Movement-easing helpers live in `scripts/enemies/patterns/` (e.g. `boss_sweep.gd` — `sin³(t)` X-axis sweep).

### Player (`scripts/game/player.gd`)
All stats start at zero, populated by Parts via `PlayerLoadout`. **Shield = CHARGE pool** — each hit consumes one charge + brief i-frames; empty → hull damage. The `engine_torch` + `damage_smoke_trail` damage tells activate on hull loss (low-hull tell; `scripts/game/player.gd` owns the exact `activate_below` threshold — currently any pip lost). `take_damage()` applies sector scaling `× (1 + 0.05 × sectors_cleared)`. Details: `docs/contributing/04-player-parts-economy.md`.

### Projectiles (`scripts/projectiles/`)
Extend `base_bullet.gd` or `base_missile.gd`. **Spawn as children of `get_tree().root`, never the player or enemy** — must survive spawner's `queue_free`.

### Backdrop (`scripts/parallax/galaxy_backdrop.gd`)
Parallax stack: deep-sky → starfield → nebula → planet → asteroids → warp streaks → vignette. One celestial body per level (weighted pick). Mine-hazard levels add decorative background mines (no collision).

### Effects (`scripts/effects/`)
Static helpers called as `Cls.method(...)`: `hit_flash_fx.flash`, `shadow_fx.attach_shadow`, `explosion_fx.play/.burst`, `impact_fx.spawn`, `burn_fx.apply_burn`, `enemy_engine_fx.attach`, `shield_sfx.play_hit/play_break`, `muzzle_fx.play/play_energy`. Damage tells: `engine_torch.attach_to_player` + `damage_smoke_trail` — both driven off `hull_changed` (activation threshold lives in `player.gd`, see Player above).

### Playfield frame
Three CanvasLayers: **Glass=1** (side gutter panels, x 0–132 and 348–480), **HUD=5**, **Outline=10** (left+right borders only).

### Dev menu (`scripts/dev/dev_menu.gd`)
3-column GridContainer of launch buttons (movement/wave/shipyard/parallax/boss/etc.). The button list drifts — read `scripts/dev/dev_menu.gd` (or `docs/contributing/01-getting-started.md`) for the current set rather than trusting a hardcoded list here.

## Conventions

- **Hitboxes**: enemies = full sprite size. Player = sprite − 2-4 px. Difficulty via HP/damage/spawn rate, never hitbox size.
- **Explosions**: always 1× scale. Big enemies get more blasts (`.burst()`), not stretched sprites. Debris count scales with enemy size, piece scale fixed at 1×.
- **Death VFX**: debris drifts downward from frame 0 — never freeze-then-fall.
- `.uid` files — Godot-generated UIDs; commit them, never edit by hand.
- `.tmp` files in `scenes/player/` — editor autosave, ignore.
- `default_texture_filter=0` (nearest) — intentional for pixel art.
- **Motion-clarity speed scale**: enemy/projectile speeds follow the **1–8 px/frame rung scale** in `scripts/systems/clarity.gd` (rung = multiple of 60 px/s; **8 px/f = 480 px/s is the hard ceiling** — past it objects strobe/ghost at 480×270). Author speeds on a rung (`Clarity.snap_to_rung` / `proposed_speed`); lasers sit at 8, chaff bullets 1–3, fast enemies ~4. `enemy_core` clamps sector-scaled movement to the ceiling. `max_fps=60` (project.godot) is intentional — pixel-art motion reads cleanest at the 60 Hz tick with snap on; do not raise it. Re-audit with `tools/clarity_audit.gd`.
- **New Part**: extend `Part`, set `slot_type` in `_init`, override `apply(ship)` (additive + record delta) and `unapply(ship)` (reverse). Register in `PartFactory`.
- **Weapon stats live in the `.tres`, not the script** (single source of truth, 2026-06-11). A weapon's `_init()` sets ONLY identity (`display_name`/`description`) + behavior (virtual methods, `_mk_knobs()` curve shape) — NEVER `base_damage`/`base_cooldown`/`base_ammo`/etc. Those go in `resources/weapons/<name>.tres` (Godot skips `_init()` on disk-loaded resources, so stat literals there are dead-but-misleading). `_build_weapon` errors if a pooled weapon's `.tres` is missing. Run `tools/validate_weapon_data.gd` after weapon changes (must print `VERDICT: PASS`). Details: `docs/weapon_data_centralization_2026-06-11.md`.
- **PixelPlanets / planetkit placement**: Every PixelPlanets scene placed into any scene (backdrop, sector map, dev tool) MUST use the pixel-parity setup: (1) set `p.scale = Vector2(actual_size / 100.0, actual_size / 100.0)`, (2) call `add_child(p)` FIRST so `_ready()` initializes the ColorRect children, (3) THEN call `_apply_pixel_parity(p, actual_size)`. Skipping step 2 before step 3 silently leaves shader cells mismatched — each cell covers multiple viewport pixels and individual pixels appear larger than they should. See `scripts/parallax/layer_planet.gd` for the canonical implementation and `docs/godot-patterns.md` for the explanation.

## Godot MCP integration

`addons/godot_mcp/` enabled. Editor open + addon WebSocket on port 9080 = live script/scene editing. Bridge: `F:\Programming\Git\Godot-MCP\server\dist\index.js`. Editing `.tscn` on disk while editor has it open prompts reload — accept it.

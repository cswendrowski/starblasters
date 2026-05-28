# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Godot 2D top-down vertical shmup (GDScript). Roguelite with branching sector map, slotted parts, Mk.1–9 upgrade scaling. Renderer: `gl_compatibility`. **Internal viewport 480×270, 4× display = 1920×1080.** Gameplay constrained to **216×270 playfield band (X 132–348)**. Side gutters host glass panels + HUD. **Always import `scripts/playfield.gd` (`Playfield.X_MIN`, `X_MAX`, `CENTER`, `clamp_pos`) for gameplay bounds — never `get_viewport_rect()`** (returns full 480 width). Backdrop/despawn margins may read the viewport directly.

## Engine version

**Godot 4.6.3 standalone** (no Mono) — single binary for editor + web export. Consolidated from a 4.3-Mono editor + 4.4.1-standalone exporter split on 2026-05-26 since the project never used C#. Binary path lives in `tools/parse_check.ps1` and `tools/publish.ps1`; update both if it moves.

## Running / building

- Headless smoke: `godot --path . --headless --quit-after 2`
- Full parse check: `tools/parse_check.ps1`
- Publish: `tools/publish.ps1 -Version "0.1.NN"` — bumps version, runs parse_check, exports the Web preset, mtime-validates pck, then `butler push`. **Never `butler push` directly.** Don't push without explicit user confirmation.

## Workflow: human-iterated, agent-consumed

Context is the scarce resource. Iteration-heavy work belongs in a dev tuner the **human** runs.

**For UI/HUD layout, visual tuning, or numeric balance:**
- Existing tuners: `UI Designer`, `Ship Sizer`, `Parallax Tuner`, `Wave Tester`, `Asteroid Lab`, `Movement Lab`, `Shipyard`, `Maneuver Sim`. Ask Roman to run it and paste the exported values. Do not iterate by edit-capture-look.
- No tuner for a 3+-knob system? Scaffold one first (see `scripts/dev/ui_designer.gd` as reference — JSON persist to `user://tuners/<name>.json`).
- **Tuner contract:** every tuner must have a **Copy GDScript** button emitting a paste-ready snippet. Without it the handoff is broken.

**For visual mechanics:** write `tools/capture_<mechanic>.gd` + `.ps1` → ffmpeg → GIF. Post GIF to Discord; don't read PNG frames yourself unless actively debugging a specific visual bug.

## Input map

`left`/`right`/`up`/`down` (WASD + arrows), `shoot` (Space), `shoot2` (G), `shoot_nose` (Shift), `weapon_previous` (Q), `weapon_next` (E).

## Autoloads (`/root/...`)

- `Run` (`scripts/run_state.gd`) — run state: bounty, hull/shield, loadout snapshot, sector_map_cache, current_node_id/type, current_hazard_subtype, sectors_cleared, run_seed. `Run.new_run()` resets. One-shot config via `Run.set_meta(...)` (e.g. `wave_v2_knobs`, `forced_boss_scene`, `minefield_mine_type`).
- `Dbg` — debug helpers
- `Music` — context-aware BGM (`set_context("menu"|"combat"|"boss"|"sector")`)
- `Settings` — persisted user prefs

## Architecture

### Scene flow
`main_menu.tscn` → `main.tscn` (combat) ↔ `sector_map_v2.tscn` → `outpost.tscn` / `signal_event.tscn` / `cleared_summary.tscn` / `run_summary.tscn`. Sector map: 12-row grid, forward-only edges (`_strip_backward_edges`).

### Combat flow (`scripts/main.gd`)
`new_game()` builds `LevelData` via `WaveGen.build()` (production), `WaveGeneratorV2.build_combat()` (Wave Tester dev), or `Levels.build_minefield/asteroid_field_level()` (hazard nodes). `director.gd` walks `WaveSpec`s, emits `enemy_died`, `wave_started`, `level_cleared`. `level_cleared` → `_run_outro()` → fly-out tween → wipe → `ClearedSummaryScene`.

### Enemies (`scripts/enemies/`)
- `enemy_base.gd` — base (`Area2D`, `class_name EnemyBase`). Health, `take_hit`, `explode`, engine flame + parallax shadow + damage overlay shader (gated by `auto_rotate`), debris on death, offscreen cleanup.
- `enemy_core.gd` — adds `movement: Resource` + `shoot_pattern: Resource` slots.
- `patterns/` — movement Resources; subclass `movement_pattern.gd`, override `compute_step(enemy, delta) -> Vector2`.
- Custom enemies (bomber, bulwark v2) extend `enemy_base.gd` directly, expose `hull`/`max_hull` + `hull_changed` signal.

**Enemy convention:** When adding new enemies, prefer extending `enemy_core.gd` and declaring movement/shoot behavior via the `movement` and `shoot_pattern` resource slots over inline bespoke `_process` logic. Check `scripts/enemies/patterns/` and `scripts/enemies/shoot_patterns/` for existing patterns before writing new movement code. Reserve bespoke scripts for behavior that genuinely cannot be expressed as a pattern (complex state machines, multi-phase locomotion, continuous-effect weapons).

### Bosses (`scripts/boss.gd`, `boss_reaver.gd`, `boss_sentinel.gd`)
Three bosses share `boss.gd`. **Each sets stats in `_ready()` before `super._ready()` — never via `<= 0 ? default` pattern (caused 1-HP bug).** Boss attack: charge → fire → detonate black hole sequence. `boss_sweep.gd` uses `sin³(t)` easing on X-axis.

### Player (`scripts/player.gd`)
All stats start at zero, populated by Parts via `PlayerLoadout`. **Shield = CHARGE pool** — each hit consumes one charge + brief i-frames; empty → hull damage. When hull ≤ 50%: `engine_torch` + `damage_smoke_trail` activate. `take_damage()` applies sector scaling `× (1 + 0.05 × sectors_cleared)`.

### Projectiles (`scripts/projectiles/`)
Extend `base_bullet.gd` or `base_missile.gd`. **Spawn as children of `get_tree().root`, never the player or enemy** — must survive spawner's `queue_free`.

### Backdrop (`scripts/galaxy_backdrop.gd`)
Parallax stack: deep-sky → starfield → nebula → planet → asteroids → warp streaks → vignette. One celestial body per level (weighted pick). Mine-hazard levels add decorative background mines (no collision).

### Effects (`scripts/effects/`)
Static helpers called as `Cls.method(...)`: `hit_flash_fx.flash`, `shadow_fx.attach_shadow`, `explosion_fx.play/.burst`, `impact_fx.spawn`, `burn_fx.apply_burn`, `enemy_engine_fx.attach`, `shield_sfx.play_hit/play_break`, `muzzle_fx.play/play_energy`. Damage tells: `engine_torch.attach_to_player` + `damage_smoke_trail` — both gate on `hull_changed` + 50%-hull threshold.

### Playfield frame
Three CanvasLayers: **Glass=1** (side gutter panels, x 0–132 and 348–480), **HUD=5**, **Outline=10** (left+right borders only).

### Dev menu (`scripts/dev_menu.gd`)
3-column GridContainer, 86×14 buttons. Includes: Movement Lab, Wave Tester, Shipyard, Parallax Tuner, Asteroid Lab, Test Hazard, Boss Fight, Hangar, UI Designer, Ship Sizer, Progression Mockup.

## Conventions

- **Hitboxes**: enemies = full sprite size. Player = sprite − 2-4 px. Difficulty via HP/damage/spawn rate, never hitbox size.
- **Explosions**: always 1× scale. Big enemies get more blasts (`.burst()`), not stretched sprites. Debris count scales with enemy size, piece scale fixed at 1×.
- **Death VFX**: debris drifts downward from frame 0 — never freeze-then-fall.
- `.uid` files — Godot-generated UIDs; commit them, never edit by hand.
- `.tmp` files in `scenes/player/` — editor autosave, ignore.
- `default_texture_filter=0` (nearest) — intentional for pixel art.
- **New Part**: extend `Part`, set `slot_type` in `_init`, override `apply(ship)` (additive + record delta) and `unapply(ship)` (reverse). Register in `PartFactory`.

## Godot MCP integration

`addons/godot_mcp/` enabled. Editor open + addon WebSocket on port 9080 = live script/scene editing. Bridge: `F:\Programming\Git\Godot-MCP\server\dist\index.js`. Editing `.tscn` on disk while editor has it open prompts reload — accept it.

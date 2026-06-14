# File reorg — CHANGE MAP (2026-06-14)

The dependency map built BEFORE moving anything (Roman's step 1). For each planned move
it lists every reference that must update. Orphans are NOT touched (deferred). Checkpoint
before this work: `e070b29` (pushed).

## The load-bearing rule
`godot --import` re-resolves `uid://` references after a move, but does **NOT** fix:
- literal `res://...` strings in `.gd` (`preload`/`load`/`extends`),
- `path=` in `.tscn`/`.tres` `ext_resource` lines that have **no** `uid=` (path-only),
- the 4 autoload paths in `project.godot`,
- **runtime string compares + dictionary keys** keyed on a `res://...` path (these fail
  silently at runtime, never at parse — the most dangerous class).

**Execution per batch:** find/replace every old→new literal across `*.gd/*.tscn/*.tres/
project.godot` → `git mv` the file (+ its `.gd.uid`/`.import` sidecar) → `godot --import`
→ `parse_check` + `compile_check` + boot (+ a boss boot for the boss batch) → commit.

---

## Batch 1 — effects strays → `scripts/effects/`  (LOW)
`burn_fx.gd`, `shadow_fx.gd`, `trail_fx.gd` (3 files). 15 refs, all `.gd` (`preload`/`load`),
no scene refs:
- burn_fx: ship_damage_tells, ship_debris_ember, enemy_base, main, bomblet, mine,
  mine_smart, mine_shielded, gravity_mine, boss_base.
- shadow_fx: enemy_core, player, boss_base.
- trail_fx: weapons/enemy_bullet, projectiles/bullet.

## Batch 2 — autoloads → `scripts/autoload/`  (LOW, but Run is critical)
`run_state.gd`, `dbg.gd`, `music_manager.gd`, `settings.gd` (4). Refs: the 4 `project.godot`
`[autoload]` paths + `tools/sim_outpost_density.gd`, `tools/test_outpost_rules.gd`. The
autoloads are reached via `/root/Run` etc. (NOT file path), so blast radius is tiny — but a
wrong `project.godot` path breaks the whole game, so boot-verify.

## Batch 3 — strings → `scripts/strings/`  (LOW–MED)
`strings.gd`, `armory_strings.gd`, `codex_strings.gd`, `enemy_strings.gd`,
`sector_name_generator.gd` (5). Refs (`.gd` preload): enemy_codex (3), signal_event,
onboarding, outpost, run_state, sector_map_v3, dev/enemy_bench, tools/test_armory_codex,
tools/test_outpost_tasks. (enemy_strings/codex_strings self-comments also rewrite — harmless.)

## Batch 4 — HUD → `scripts/hud/`  (MED — path-only .tscn refs)
`hud_light.gd`, `hull_pips.gd`, `shield_pips_hud.gd`, `hologram_hud.gd`, `score_counter.gd`,
`wave_banner.gd` (6). Refs: `scenes/ui.tscn` (ui.gd, uid+path), `scenes/score_counter.tscn`
(**path-only**), `scenes/hud/wave_banner.tscn` (**path-only**), ui.gd (preloads hologram_hud
+ hud_light), dev/shield_pips_demo (shield_pips_hud). `hull_pips` has no path ref (used via
ui.gd internals/class) — move it, verify boot. NOTE: ui.gd stays at root (it's the combat-UI
root, not a HUD widget) — only the widgets move.

## Batch 5 — bosses → `scripts/enemies/bosses/` + `scenes/enemies/bosses/`  (MED–HIGH)
Scripts: `boss.gd` (root) + `boss_{base,phase,aegis,conductor,howler,reaver,spinwright,
voidmaw}.gd` (from `scripts/enemies/`). Scenes: `boss{,_conductor,_howler,_reaver,_sentinel,
_spinwright,_voidmaw}.tscn`.
- Script refs: 7 `boss_*.tscn` `script=` (uid+path), `boss.tscn` `script=`, 7
  `extends "res://scripts/enemies/boss_base.gd"`, boss_base preload(boss_phase), boss_phase
  self-load.
- **RUNTIME compares (silent-fail):** `main.gd:995` + `base_missile.gd:388`
  `resource_path == "res://scripts/enemies/boss_base.gd"` → MUST update.
- Scene refs (~50): run_state BOSS_* consts, feature_showcase (preload + list),
  **enemy_strings dict KEYS**, dev/enemy_manifest, dev/combat_lab BOSS_PICKS,
  debug_testbed (.gd + .tscn `metadata/scene_path`), **wave_generator boss roster +
  maneuver-tag KEYS**, levels_v2 preload, tools/capture_boss_blackhole.
- **Verify with a boss boot** (parse_check won't spawn a boss). enemy_strings keys +
  wave_generator keys are keyed by scene path, so find/replace keeps key↔lookup consistent.

---

## Deferred to a later phase (mapped target, not executed this turn)
Higher-subjectivity / higher-blast categorization of the remaining `scripts/` root:
- `scripts/game/` ← main, player, ship, enemy_core, run_save
- `scripts/screens/` ← main_menu, outpost, manage_ship, signal_event, cleared_summary,
  run_summary, run_history, sector_map_v3, sector_map_hd, hangar, feature_showcase, credits,
  dev_menu, debug_testbed, pause_menu
- `scripts/systems/` ← playfield, lanes, lane_traffic, zones, clarity, scene_transition(_overlay),
  sector_node, sector_map_route, galaxy_backdrop, black_hole, beat, Camera2D, enemy_codex, ui
- assets: `Sound/` → `assets/audio/` (literal `res://Sound/...` in sfx/music scripts),
  graphics consolidation, `Mini Pixel Pack 3/` → `vendor/`.
These move the high-blast `.tscn`-attached scene scripts (main.tscn, main_menu.tscn, etc.) and
the audio literal-path set — worth their own focused, separately-verified passes.

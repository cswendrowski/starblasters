# Wave Pattern Editor + authored-pattern auto-mix — design

**Status:** designed, not yet implemented (2026-06-15). Captures the agreed approach for a future build.

## Context

The conductor (`scripts/levels/director.gd`) performs only **randomly generated** waves today
(`scripts/levels/wave_generator.gd` `WaveGenerator.build`). We want to **hand-author reusable wave
patterns** — enemies placed precisely on lanes — that the conductor mixes into real levels alongside
the generated ones. This needs (a) a new dev tool to author/preview patterns on a lane grid, and
(b) a small production-side change so the conductor can spawn an *exact* authored lane layout and the
composer can roll authored patterns into generated levels.

Decisions (confirmed with Roman):
- **One saved pattern = a single FORMATION burst** — a group of enemies entering together on specific
  lanes, with optional per-enemy entry stagger. Maps to one `Phrase` of kind FORMATION.
- **Auto-mix into generated levels** — `WaveGenerator.build_score` rolls a seeded chance to splice an
  eligible authored pattern into a generated wave, so they appear in normal play next to random ones.

Key facts established during exploration:
- Lanes are static math in `scripts/systems/lanes.gd` (`Lanes`, 7 lanes, `lane_center(i)` = 150 + 30·i;
  centers 150–330; lane 3 = playfield center). Zones in `scripts/systems/zones.gd`.
- The director performs a `CombatScore` (`combat_score.gd`) → `ScoreWave` (`score_wave.gd`) → `Phrase`
  (`phrase.gd`, kinds FORMATION/FILLER/BREATHER). A FORMATION phrase carries `specs: Array` (of
  `WaveSpec`) + `shape: StringName`; lanes are computed algorithmically from `shape` and **no field
  carries an explicit per-enemy lane layout** (`Phrase.lane_anchor_hint` exists but is unread).
- `director._spawn_enemy(wave, index, lane_override=-1)` already spawns **exactly** at
  `Lanes.lane_center(lane_override)` when `lane_override >= 0` (`director.gd:573,689-690`) — the
  precise-placement primitive exists; only the dispatch path to it for authored layouts is missing.
- `WaveGenerator.build_score` (`wave_generator.gd:147`) is the documented seam for native phrase
  authoring (currently just lifts `build()` via `ScoreAdapter`). The chokepoint that hands the score to
  the director is `main.gd:700-701` / `:759`.
- Tuner conventions: native 480×270 `Control` root, all UI built in code, left/right gutter `Panel`s,
  band 132–348 for the live world, Esc→dev menu; persist JSON to `user://tuners/<name>.json`; a
  **Copy GDScript** button via `DisplayServer.clipboard_set`. Reference: `scripts/dev/ui_designer.gd`,
  `scripts/dev/pattern_eligibility_editor.gd` (the latter's `const DATA` export → committed
  `scripts/levels/pattern_eligibility.gd` is the exact library pattern to mirror). The committed-`DATA`
  + tuner-JSON split is the canonical reusable-data shape.
- Placeable enemies come from `scripts/levels/enemy_roster.gd` (entries: `scene`, `size`, `movement`
  key, faction via `Factions.ENEMY_TAGS`). Movement keys: the 28 in
  `pattern_eligibility_editor.gd:MOVEMENT_KEYS`.
- The dev "Combat Slice" (`scripts/dev/combat_slice.gd`, routed via `Run.set_meta("combat_slice")` →
  `main.gd:756`) is the canonical hand-built `CombatScore` reference and the model for the in-tool live
  preview + a dev force-hook.

## Data model — an authored formation pattern

One pattern (plain Dictionary, JSON-friendly, mirrors `pattern_eligibility.gd:DATA`):
```
{
  "name": "v_pincer_delayed",
  "faction": "any",          # "supremacy"|"privateer"|"corporate"|"zealot"|"any" (auto-mix gate)
  "min_sector": 0,           # eligible from this sector depth up
  "stagger": 0.18,           # seconds between grid rows (entry stagger step)
  "placements": [            # one per filled grid cell
    {"lane": 0, "row": 0, "enemy": "res://scenes/enemies/.../enemy_dart.tscn", "movement": ""},
    {"lane": 6, "row": 0, "enemy": "...", "movement": "lane_hook"},
    ...
  ]
}
```
- Grid axes: **columns = 7 lanes** (Lanes), **rows = entry-stagger beats** (row r enters at
  `r * stagger` s). A cell = one enemy.
- `movement` "" = the enemy's roster-default identity; otherwise an explicit movement key override.

## Production-side changes (small, additive)

1. **`scripts/levels/wave_def.gd` (WaveSpec):** add `var lane: int = -1` (per-spec explicit lane;
   -1 = unset/algorithmic). Reuse existing `spawn_delay` for the per-spec entry stagger.
2. **`scripts/levels/director.gd`:** in `_dispatch_formation` (`:284`) add a branch for
   `phrase.shape == &"authored"` → new `_dispatch_authored(phrase)` that, for each spec, schedules
   `_spawn_enemy(spec, i, spec.lane)` at `spec.spawn_delay` (cap-gated like the others). Pure addition;
   existing shapes untouched.
3. **`scripts/levels/authored_patterns.gd` (new):** `const DATA: Array` (the committed library, initially
   empty/seeded with one example) + `static func build_phrase(pattern: Dictionary) -> Phrase` that
   compiles a pattern dict → a FORMATION `Phrase` (`shape = &"authored"`, `specs` = one count-1
   `WaveSpec` per placement with `lane`, `spawn_delay = row*stagger`, and
   `movement_override = Roster.make_movement({"movement": key})` when set). Also
   `static func eligible(faction, sector) -> Array` for the gate.
4. **`scripts/levels/wave_generator.gd` `build_score` (`:147`):** after lifting the base score, roll a
   **seeded** per-wave chance (reuse `_stable_seed`/run-seed for determinism) to append an eligible
   authored phrase (`AuthoredPatterns.eligible(level_faction, sector)`) into a wave's `phrases`. Modest
   probability + a knob; faction-gated so injected enemies stay coherent with the level roster. No
   downstream change — `build_score` already feeds `main.gd`→`start_score`.

## The dev tool — `scripts/dev/wave_pattern_editor.gd` + `scenes/dev/wave_pattern_editor.tscn`

Native 480×270 `Control` root (mirror `lane_visualizer.gd` / `pattern_eligibility_editor.gd` structure:
gutter `Panel`s, `_draw()` overlay, styled toggle/cycle `Button`s — **no** CheckBox/SpinBox/OptionButton).

- **Center band (132–348):** the 7-lane grid via `Lanes` — reuse the lane-column + center-line `_draw()`
  from `lane_visualizer.gd:141-147`, plus horizontal row dividers for the stagger beats (~6 rows). Filled
  cells draw the enemy's frame-0 sprite (cache via the `pattern_eligibility_editor.gd:_enemy_texture`
  approach) tinted, with a small movement-key tag.
- **Left gutter:** pattern name (cycle/rename), faction + min_sector cyclers, stagger knob (cycle-button),
  Save JSON / **Copy GDScript** / Preview / Clear / Back. New/Prev/Next pattern in the library.
- **Right gutter:** scrollable **enemy palette** (one toggle `Button` per roster entry) = the placement
  brush, plus a movement-override cycler ("(default)" + the 28 keys). Selecting sets the active brush.
- **Interaction (grid-based, drag-drop deferred):** click an empty cell → place the active brush; click a
  filled cell → clear it. (`_gui_input`/`_unhandled_input` hit-test against `Lanes.nearest_lane(x)` + row
  from Y.)
- **Live preview:** mirror `lane_visualizer.gd` CONDUCTOR mode — instantiate the real `director.gd`, build
  a `CombatScore` wrapping `AuthoredPatterns.build_phrase(current_pattern)` in one `ScoreWave`,
  `start_score` it over the overlay so the designer watches the actual conductor perform the exact layout.
- **Persistence/export:** Save/Load JSON to `user://tuners/wave_patterns.json` (the working library);
  **Copy GDScript** emits a paste-ready `const DATA := [ ... ]` block (the whole library) for hand-paste
  into `scripts/levels/authored_patterns.gd` — exactly the `pattern_eligibility_editor._export` pattern.
- **Dev hook:** a "Send to conductor" that sets `Run.set_meta("forced_pattern", name)` (consumed in
  `build_score`/`main.gd` like `combat_slice`) so a pattern can be dropped into a real launched level for
  in-game testing.

## Dev menu registration

Add one button in `scripts/dev/dev_menu.gd` (the `_add_button(...)` block, ~`:86-103`) →
`SceneTransition.change_scene(get_tree(), "res://scenes/dev/wave_pattern_editor.tscn")`.

## Files

- New: `scripts/dev/wave_pattern_editor.gd`, `scenes/dev/wave_pattern_editor.tscn`,
  `scripts/levels/authored_patterns.gd`
- Edit: `scripts/levels/wave_def.gd` (+`lane`), `scripts/levels/director.gd` (`_dispatch_authored`),
  `scripts/levels/wave_generator.gd` (`build_score` injection), `scripts/dev/dev_menu.gd` (button),
  `scenes/dev_menu.tscn` if the menu is data-driven.

## Verification

- `tools/parse_check.ps1` green; headless boot of `scenes/dev/wave_pattern_editor.tscn`
  (`godot --headless <scene> --quit-after 2`) clean.
- Headless harness: build a pattern dict → `AuthoredPatterns.build_phrase` → wrap in `CombatScore` → run
  the real `director` a few seconds; assert enemies spawn at the authored lanes
  (`Lanes.nearest_lane(enemy.position.x)` matches) and stagger order.
- Determinism: `WaveGenerator.build_score(sd, li)` twice with the same run seed → identical
  authored-injection result.
- In-editor: open the tool from the dev menu, place a V-pincer, Preview (watch the conductor spawn it on
  the right lanes), Save JSON, Copy GDScript, paste into `authored_patterns.gd`, relaunch a real
  asteroid/standard level and confirm the pattern can appear.
- Visual confidence GIF of the preview for Roman (capture harness), since lane/timing feel is
  eyeball-gated.

## Notes / scope boundaries

- v1 is **top-entry** formations (vertical lanes); `entry=&"side"` deferred.
- Drag-and-drop deferred — grid click-to-place (Roman accepted grid).
- Faction coherence: auto-mix only injects patterns whose `faction` is `"any"` or matches the level's
  active faction, so injected enemies stay in-roster.

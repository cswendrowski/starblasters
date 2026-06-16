# Wave Pattern Editor + authored-pattern auto-mix — design

**Status:** SCOPED, NOT BUILT (2026-06-15). Captures the agreed approach + an ordered build plan.
Seams re-validated against `main` after the 2026-06-15 codebase-health audit (see "Reconciliation"
below). Flip to `BUILT <date>` when shipped; keep the `docs/README.md` index entry in sync.

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
- **Auto-mix into generated levels** — the composer rolls a **seeded** chance (drawn from the content
  RNG stream) to splice an eligible authored pattern into a generated wave at the producer chokepoint, so
  they appear in normal play next to random ones. (Injection seam corrected post-audit — see
  Reconciliation; `build_score` alone is off the production hot path.)
- **Per-slot wildcards** — each slot independently locks (or leaves to the conductor) its **enemy** and
  its **movement**, which yields the three authoring modes below from one mechanism.

## Authoring modes

A slot's `enemy` and `movement` are each either *specific* or *wildcard* (`""` = "conductor assigns").
The three requested modes are presets over that single mechanism (mixed slots are allowed too):

1. **Enemies, no patterns** — every slot has a specific `enemy`, `movement = ""`. You pin *who* shows up
   and *where*; the conductor assigns each enemy's movement (its normal composer resolution via
   `pattern_eligibility`). Faction-bound (the enemies belong to a faction).
2. **Patterns, no enemies** — every slot has a specific `movement` + lane/row (+ optional `size` hint),
   `enemy = ""`. You pin the *shape/choreography*; the conductor fills faction-appropriate enemies into
   the slots. **Faction-agnostic → reusable in any faction's levels** (the big reuse win).
3. **Specific enemies AND patterns** — both locked. Premade, performed by the conductor as-is.

Wildcards resolve **at level-build time** in `AuthoredPatterns.build_phrase(pattern, faction, sector, rng)`
(seeded → node-retries reproduce), reusing the composer's existing machinery: enemy wildcard → pick a
roster entry matching faction + sector + the slot's `size` hint (the `enemy_roster.gd` / `WaveGenerator`
pick path); movement wildcard → the composer's normal movement resolution for the assigned enemy
(`pattern_eligibility.resolve`). The editor's live Preview resolves wildcards against a chosen preview
faction + fixed seed so the designer sees one concrete realization.

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

## Reconciliation with the 2026-06-15 health audit

The audit/cleanup that landed on `main` (commits `67d97d8`…`5aa6118`) doesn't block this build — most of
it is a **tailwind**. Re-validated seams + the two corrections that matter:

- **Determinism is now wired (use it).** Two seeded streams exist: a **content** stream in
  `wave_generator.gd` (`_stable_seed` folds `run_seed`; the `RandomNumberGenerator` is created at
  `wave_generator.gd:127` and threaded through every `_build_*`/`_pick_*`), and a **dispatch** stream
  `director._rng` (`_seed_dispatch_rng`, `director.gd:137-142`, seeded per combat node in `start_score`).
  The auto-mix roll + wildcard **enemy** pick are *content* decisions → draw them from the **content**
  stream; lane placement is already seeded for free via `director._rng`.
- **CORRECTION — injection seam.** `WaveGenerator.build_score` is **off the production hot path**: real
  runs go `WaveGen.build()` (LevelData) → `ScoreAdapter.from_level_data` (`main.gd:701`) →
  `start_score` (`main.gd:761`); `build_score` is only hit by tools/tests. So the auto-mix must splice at
  the **producer chokepoint in `main.gd`** — right after `ScoreAdapter.from_level_data(_current_level)`,
  before `start_score(_current_score)` — where the active faction + sector + `run_seed` are all known
  (hazards already set `_current_score` directly here, so it's the proven seam). Mirror the splice into
  `build_score`/`ScoreAdapter` too so the tool/test path matches production.
- **Phrase shape default is `&"top_spread"`**, not `&"formation"` — authored phrases must set
  `shape = &"authored"` explicitly (the `ScoreAdapter._shape_id` map never emits `authored`, so the new
  director branch is unambiguous).
- **`director._spawn_enemy` is now 4-arg** (`wave, index, lane_override=-1, step_sync={}`) — the
  `lane_override` precise-placement primitive (`director.gd:715-716`, spawns at `Lanes.lane_center`) is
  unchanged; just call it positionally as before.
- **Movement-variety is NOT run-seed reproducible today.** `EnemyRoster.make_movement` /
  `PatternEligibility.resolve` draw "vary"/mirror rolls from the *unseeded* global RNG. For reproducible
  authored patterns, resolve the wildcard movement **key** from the seeded content stream and pin it;
  accept that intra-pattern mirroring isn't seeded (matches current production behaviour — not a regression).
- **No breakage.** `lanes.gd`, `enemy_roster.gd` (pick path + `make_movement`), `pattern_eligibility.gd`
  (`resolve`/`eligible_for`), `combat_slice.gd`, the `Run.set_meta` dev hooks, and the dev-tool conventions
  (`dev_menu.gd` registration, `ui_designer.gd` JSON+Copy-GDScript) are all intact. Dead-code removed
  (`_build_coda`, etc.) doesn't overlap the new code. `wave_def.gd`/`phrase.gd` have no removed fields
  (`lane_anchor_hint` still present, unused).
- **Doc canon:** this doc is CURRENT and indexed at `docs/README.md:32`; it stays in `docs/` (not
  `docs/archive/`). Keep the `Status:` header in canon form and update the index entry when built.

## Data model — an authored formation pattern

One pattern (plain Dictionary, JSON-friendly, mirrors `pattern_eligibility.gd:DATA`):
```
{
  "name": "v_pincer_delayed",
  "faction": "any",          # auto-mix gate. "any" for enemy-wildcard (faction-agnostic) patterns;
                             # otherwise derived from / matched to the specific enemies' faction.
  "min_sector": 0,           # eligible from this sector depth up
  "stagger": 0.18,           # seconds between grid rows (entry stagger step)
  "placements": [            # one per filled grid cell
    # specific enemy, conductor-assigned movement (mode 1)
    {"lane": 0, "row": 0, "enemy": "res://scenes/enemies/.../enemy_dart.tscn", "movement": "", "size": ""},
    # conductor-assigned enemy, specific movement + size hint (mode 2)
    {"lane": 6, "row": 0, "enemy": "", "movement": "lane_hook", "size": "small"},
    # both specific (mode 3)
    {"lane": 3, "row": 1, "enemy": "res://...enemy_z_s_retro.tscn", "movement": "loiter_mid", "size": ""},
    ...
  ]
}
```
- Grid axes: **columns = 7 lanes** (Lanes), **rows = entry-stagger beats** (row r enters at
  `r * stagger` s). A cell = one slot.
- `enemy` "" = **wildcard** (conductor picks a faction/sector/size-appropriate enemy); else a scene path.
- `movement` "" = **wildcard** (conductor assigns via the composer's normal resolution for the enemy);
  else an explicit movement-key override.
- `size` (optional, enemy-wildcard slots only) = "small"|"medium"|"large"|"huge"|"giant"|"" (any) — a hint
  so the conductor fills an appropriately-sized enemy per position (e.g. big anchor centre, chaff edges).

## Production-side changes (small, additive)

1. **`scripts/levels/wave_def.gd` (WaveSpec):** add `var lane: int = -1` (per-spec explicit lane;
   -1 = unset/algorithmic). Reuse existing `spawn_delay` for the per-spec entry stagger.
2. **`scripts/levels/director.gd`:** in `_dispatch_formation` (`:284`) add a branch for
   `phrase.shape == &"authored"` → new `_dispatch_authored(phrase)` that, for each spec, schedules
   `_spawn_enemy(spec, i, spec.lane)` at `spec.spawn_delay` (cap-gated like the others). Pure addition;
   existing shapes untouched.
3. **`scripts/levels/authored_patterns.gd` (new):** `const DATA: Array` (the committed library, initially
   empty/seeded with one example) + `static func build_phrase(pattern, faction, sector, rng) -> Phrase`
   that compiles a pattern dict → a FORMATION `Phrase` (`shape = &"authored"`, `specs` = one count-1
   `WaveSpec` per placement with `lane`, `spawn_delay = row*stagger`), **resolving wildcards** at this
   point (seeded by `rng`): `enemy == ""` → pick a roster entry matching `faction`+`sector`+`size`
   (reuse the `enemy_roster.gd`/`WaveGenerator` pick path); `movement == ""` → the composer's normal
   movement resolution for the chosen enemy (`pattern_eligibility.resolve`); else honour the authored
   `enemy_scene` / `movement_override = Roster.make_movement({"movement": key})`. Also
   `static func eligible(faction, sector) -> Array` for the gate — a pattern is eligible if
   `min_sector <= sector` AND (`pattern.faction == "any"` OR matches the level faction).
4. **Auto-mix at the producer chokepoint (`scripts/game/main.gd`, right after
   `ScoreAdapter.from_level_data(_current_level)`, before `start_score`):**
   `AuthoredPatterns.maybe_inject(_current_score, faction, sector, rng)` — roll a **seeded** per-wave
   chance (rng seeded from `run_seed` + sector, mirroring `_stable_seed`) to append an eligible authored
   phrase into a wave's `phrases`. Faction-agnostic (enemy-wildcard) patterns are eligible in **any**
   faction level and get filled with that level's roster; enemy-specified patterns gate to their matching
   faction so spawned enemies stay in-roster. Modest probability + a knob. Mirror the same splice into
   `WaveGenerator.build_score` / `ScoreAdapter.from_level_data` so the dev-tool/test path matches
   production. (See Reconciliation — `build_score` alone is off the hot path.)

## The dev tool — `scripts/dev/wave_pattern_editor.gd` + `scenes/dev/wave_pattern_editor.tscn`

Native 480×270 `Control` root (mirror `lane_visualizer.gd` / `pattern_eligibility_editor.gd` structure:
gutter `Panel`s, `_draw()` overlay, styled toggle/cycle `Button`s — **no** CheckBox/SpinBox/OptionButton).

- **Center band (132–348):** the 7-lane grid via `Lanes` — reuse the lane-column + center-line `_draw()`
  from `lane_visualizer.gd:141-147`, plus horizontal row dividers for the stagger beats (~6 rows). Filled
  cells draw the enemy's frame-0 sprite (cache via the `pattern_eligibility_editor.gd:_enemy_texture`
  approach) tinted, with a small movement-key tag.
- **Left gutter:** pattern name (cycle/rename), faction + min_sector cyclers, stagger knob (cycle-button),
  Save JSON / **Copy GDScript** / Preview / Clear / Back. New/Prev/Next pattern in the library.
- **Right gutter:** scrollable **enemy palette** (one toggle `Button` per roster entry, plus an
  "Any (wildcard)" entry) = the enemy brush; a **movement cycler** ("Any (wildcard)" + the 28 keys); and
  a **size-hint cycler** (Any/small/…/giant, used when the enemy is wildcard). Together these set the
  active brush.
- **Authoring-mode presets** (left gutter quick-set): "Enemies only" (lock enemy / movement wildcard),
  "Patterns only" (enemy wildcard / lock movement+size), "Full" (lock both) — these just bias what the
  brush leaves wildcard so a designer can stay in one mode without fiddling each slot. Mixed slots still
  allowed.
- **Interaction (grid-based, drag-drop deferred):** click an empty cell → place the active brush; click a
  filled cell → clear it. (`_gui_input`/`_unhandled_input` hit-test against `Lanes.nearest_lane(x)` + row
  from Y.) Wildcard slots render a faction-neutral placeholder: enemy-wildcard → a "?" silhouette + the
  movement/size tags; movement-wildcard → the enemy sprite + an "auto" movement tag.
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
- Edit: `scripts/levels/wave_def.gd` (+`lane`), `scripts/levels/director.gd` (`&"authored"` branch +
  `_dispatch_authored`), `scripts/game/main.gd` (chokepoint auto-mix call — the real seam),
  `scripts/levels/wave_generator.gd` / `scripts/levels/score_adapter.gd` (mirror the splice for
  tool/test parity), `scripts/dev/dev_menu.gd` (button) + `scenes/dev_menu.tscn` if the menu is
  data-driven, `docs/README.md` (flip the index entry to BUILT on ship).

## Build work plan (ordered phases)

Each phase lands independently and is headless-verifiable. The editor (P3) needs P0+P1 to preview;
the auto-mix (P2) is independent and can land last.

- **P0 — Conductor honours explicit lanes (production primitive).** `wave_def.gd`: add `lane: int = -1`.
  `director.gd`: add the `phrase.shape == &"authored"` branch in `_dispatch_formation` →
  `_dispatch_authored(phrase)` that, for each spec, schedules `_spawn_enemy(spec, i, spec.lane)` at
  `spec.spawn_delay` (cap-gated like the others). *Verify:* headless harness builds a hand-made authored
  phrase → `CombatScore` → real `director`; assert each enemy lands on its authored lane
  (`Lanes.nearest_lane(pos.x)`) in stagger order.
- **P1 — Pattern library + builder (`scripts/levels/authored_patterns.gd`).** `const DATA: Array` (seed
  one example) + `build_phrase(pattern, faction, sector, rng) -> Phrase` (FORMATION, `shape=&"authored"`,
  one count-1 `WaveSpec` per placement with `lane` + `spawn_delay`; resolve wildcards from `rng` — enemy
  via the `enemy_roster.gd` eligible-pick path filtered by faction/sector/size; movement key via
  `pattern_eligibility` then `Roster.make_movement`) + `eligible(faction, sector) -> Array`. *Verify:*
  headless — all three modes resolve (enemy-locked, movement-locked, both); a faction-agnostic pattern
  fills two different factions; same seed → identical result.
- **P2 — Auto-mix at the producer chokepoint (`scripts/game/main.gd`).** Call
  `AuthoredPatterns.maybe_inject(_current_score, faction, sector, rng)` after `from_level_data`; seed `rng`
  from `run_seed`+sector. Mirror into `build_score`/`ScoreAdapter`. Add a probability knob + the
  `Run.set_meta("forced_pattern", name)` one-shot for dev testing. *Verify:* headless — build a level twice
  with the same `run_seed` → identical injection; injected enemies stay in the level's faction roster.
- **P3 — The editor tool (`scripts/dev/wave_pattern_editor.gd` + `scenes/dev/wave_pattern_editor.tscn`).**
  Native-480 `Control`; lane grid (`_draw` from `lane_visualizer.gd`); enemy/movement/size palette + mode
  presets; grid click-to-place with wildcard-slot rendering; live preview via the real `director`
  (mirror `lane_visualizer` CONDUCTOR mode); JSON persist to `user://tuners/wave_patterns.json`;
  Copy-GDScript export of the `const DATA` block; "Send to conductor" (`Run.set_meta`). Register a button
  in `dev_menu.gd`. *Verify:* `parse_check` + headless scene boot; in-editor author a V-pincer, Preview,
  Save, Copy GDScript, paste into `authored_patterns.gd`, launch a real level.
- **P4 — Ship.** `parse_check` + headless boots green; capture a preview GIF for Roman (lane/timing feel
  is eyeball-gated); flip this doc's `Status:` to `BUILT <date>` and update `docs/README.md`.

## Verification

- `tools/parse_check.ps1` green; headless boot of `scenes/dev/wave_pattern_editor.tscn`
  (`godot --headless <scene> --quit-after 2`) clean.
- Headless harness: build a pattern dict → `AuthoredPatterns.build_phrase(pattern, faction, sector, rng)`
  → wrap in `CombatScore` → run the real `director` a few seconds; assert enemies spawn at the authored
  lanes (`Lanes.nearest_lane(enemy.position.x)` matches) and stagger order. Cover all three modes:
  (1) enemy-locked/movement-wildcard → spawned enemy matches, movement is a valid resolved one;
  (2) enemy-wildcard/movement-locked → spawned enemy is from the passed faction's roster (+ size hint),
  movement is the authored one; (3) both-locked → exact. Run a faction-agnostic (enemy-wildcard) pattern
  through two different faction contexts and confirm it fills each faction's roster.
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

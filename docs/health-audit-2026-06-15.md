# Codebase Health Audit — 2026-06-15

Read-only design/code-health pass across six subsystems (six parallel `design-reviewer`
lanes at medium-high effort, HIGH/MED-confidence findings only). No code was changed.

## Verdict

**Healthy.** 315 scripts / 63k lines, clean working tree, ~7 TODO markers, zero FIXME/HACK.
Every lane independently confirmed the load-bearing conventions are correct in production:
per-instance component duplication, faction overlay stacking, boss `_ready()`-before-`super`
stat order (the 1-HP bug class is fully dead), PixelPlanets placement in the live path,
forward_plus `TEXTURE`-inlining, and HUD signal-rebind hygiene. The work below is
*maintenance*, not rescue — sequenced so the genuine bugs land first and the big
decompositions stay opt-in.

Severity = blast radius if it bites. **Urgency ≠ severity**: several HIGH-severity items are
*latent* (no live code triggers them yet) — flagged so they don't ossify, not as emergencies.

---

## Progress — branch `health-audit-fixes-2026-06-15`

**Done + verified** (parse_check 315/0 + clean headless boot, on the branch):
- **Tier-1:** `Run.new_run()` 6-field reset + save-surface symmetry assert; `_on_poi_clicked` outer-break; `outpost.gd:62` weight comment.
- **Tier-2 dead-code:** outpost UPGRADES column (~200 lines); `explosion` `*_unused` fns + texture builders; `wave_generator` `_build_coda`/`_coda_shape`; `sector_map` name-label fns + 3 commented blocks; `layer_planet` dead `ci_mat`; stale gl_compatibility comments (`explosion`/`trail_fx`). Plus the `explosion` O(n²) `find()` fix.
- **Perf:** `muzzle_fx` per-shot texture cache; `layer_stellar` per-frame asteroid-node cache.
- **Safe fixes:** `settings` keybind corruption guard; `music_manager` `Node.name` shadow.
- **Tier-3 duplication:** `sector_map` `_setup_celestial_control` (×5) + `_spawn_one_asteroid` (×3) helpers (RNG order preserved — needs a visual sanity-check since headless can't render the map); `run_state` `_make_default_blaster` dedup + `_seed_super_from_part` (×3) + `_seed_secondary_ammo(part, reset_if_none)` (×2, flag preserves the equip-vs-upgrade behavior difference).
- **Reclassified (no change):** #2 death-bomb — not a bug (`fire_super()` preconditions already match the guard).

**Decisions made (Roman, 2026-06-15/16):**
- **Determinism → "Placement too" + economy** → **DONE**: `director.gd` dispatch (lanes/gaps/filler) + `levels_v2` minefield + outpost charge rolls (`run_state._roll_dice`, now keyed on `run_seed ^ salt`) all reproduce from the seed. The run's **generated structure** (sector map, content, placement, factions, bosses, economy) is now seed-consistent. *Out of scope by design:* per-combat proc RNG (hull shrug/ablative) and cosmetic FX (`enemy_base` burn-UV) stay on the global stream — event-driven by player actions, not generated structure.
- **Resume must NOT reroll the outpost** → **DONE**: `outpost_weapon_offers` now persisted (`_SAVE_FIELDS` + `@export`).
- **Sector modifiers → KEEP** (parked, do not cut). See [[parked-features-keep]].
- **Base hull → 2 is intentional** — comments fixed; behavior unchanged.
- **Soft confirms #3 filler-duration / #4 backup-shield / #5 impact_fx / phase-refund → leave as-is** (intended; no code).
- **`step_wall` + `enemy_sword`→broadside → leave for now.**

**Done (latest round):** placement-determinism seeding; outpost-stock persistence; latent seams (`make_components` per-instance dup + emitter-START recycle guard); `director` dead `ignore_recycling` param; orphaned outpost helpers; base-hull comment. `parallax_shadow` NOT gutted (parked feature, kept for consistency).

**Open / deferred:** Tier-4 architecture (player.gd god-object, sector_map stellar split, sector_map_hd coupling — deferred by Roman); the FULLY-seeded economy-RNG pass (outpost charges + cosmetic UV).

**Needs in-game verification (headless can't cover):** determinism reproducibility (two same-seed runs); outpost resume round-trip (Array-of-Dict-with-Part save); sector-map Tier-3 visual.

**Branch is PR-ready.**

---

## Cross-cutting themes (fix the theme, not the instance)

These span multiple lanes and are the highest-leverage work:

### T1 — RNG determinism is half-wired
The producer (`wave_generator.gd`) is correctly seeded from `run_seed`, but **dispatch-time
and hazard RNG draw from the unseeded global stream**, so same-seed runs get identical wave
*content* but divergent *placement*:
- `director.gd:193,449,472,501,551` — lane / wall-gap / filler picks via bare `randi()`/`shuffle()`
- `levels_v2.gd:321` — `build_minefield_score()` calls `rng.randomize()`
- `run_state.gd:447-461` — outpost repair/ammo charges via `randi()`
- `enemy_base.gd:495` — burn-origin UV marker (cosmetic)

**Decision needed from Roman first:** is placement-level determinism actually part of the
"reproducible runs" contract, or only content? If only content, the `_stable_seed` comment in
the director overclaims and should be corrected; if placement too, thread a per-level seeded
`RandomNumberGenerator` from `run_seed` into the director on `start_score`.

### T2 — Retired-but-resident dead state
Save-compat zombie fields/functions accumulate across the hot files, multiplying the live-state
surface a reader must reason about:
- `player.gd:206-207,230-232,2986,2993` — `shield_recharge_seconds`, `hull_damage_reduction`, `_self_repair_amount()` stub
- `run_state.gd:165-170,387-391,1343-1344` — five retired Mk fields (mirrored in `_SAVE_FIELDS` + `run_save.gd`)
- `enemy_base.gd:29-32,67-71,957-961` — retired `max_shield`/`_shield_ring`/`SHIELD_SHADER` scaffolding kept alive **solely** by the unwired `enemy_bomber_wing.gd`

**Action:** one dead-code sweep. If no save predating the retirement dates needs migrating,
delete; otherwise group each under a single `# RETIRED — load-only` block. Relocating
`enemy_bomber_wing.gd` out of the live tree lets `enemy_base` shed its shield scaffolding.

### T3 — PixelPlanets setup is copy-pasted, and the guard isn't everywhere
The fragile pixel-parity / anchor-normalize setup CLAUDE.md calls out is duplicated and
partially un-guarded:
- `sector_map_v3.gd:933,979,1024,1065,1344` — the 7-line Control parity block, verbatim ×5
- `galaxy_backdrop.gd:1099` + `galaxy_backdrop_v2.gd:197` — **missing** the `_normalize_colorrect_anchors`
  SIGSEGV guard that `layer_planet.gd:223` added today (only reachable via `tools/capture_*.gd`, so
  dev-tool crash risk, not shipping)

**Action:** one `_setup_celestial_control(node, px, center)` helper shared by the map; port the
anchor guard into (or retire) the capture-tool backdrops. The live combat path
(`layer_planet.gd`) is already correct.

---

## Tier 1 — Real bugs, low effort (do these first)

| # | Finding | File:line | Sev | Notes |
|---|---|---|---|---|
| 1 | `new_run()` doesn't reset 6 member fields (`current_node_type`, `current_hazard_subtype`, `current_stellar`, `asteroid_bonus_bounty`, `combat_intro`, `forced_boss_scene`) — code comments *promise* they're cleared | `run_state.gd:341-418` | HIGH | **Cleanest real cross-run leak.** Best single fix: drive `new_run()` off `_SAVE_FIELDS` defaults so the reset list can't drift again. |
| 2 | Death-bomb survival gates on `SHIELD_INVULN_SECONDS > 0` (a const), not on `fire_super()` actually consuming a charge — player can survive a lethal hit having spent nothing | `player.gd:1390-1404` | HIGH | Narrow trigger, but a correctness hole. Gate on `fire_super()` returning success. |
| 3 | `_dispatch_filler` accrues `elapsed` twice in duration mode (cap-wait + outer) → cap-saturated filler waves exit their window early | `director.gd:541-557` | MED | Track duration off a start timestamp instead of summing sleeps. |
| 4 | Backup Shield Capacitor refill calls `set_shield` a second time, re-firing the shield-hit SFX/anim and restarting the regen timer | `player.gd:1372-1375,1453-1456` | MED | Write clamped target once, or suppress side-effects on the refill write. |
| 5 | `impact_fx._spawn_explosive` instantiates a full death-`explosion.tscn` (own light + sparks) per EXPLOSIVE-bullet hit — heavier than an impact warrants | `impact_fx.gd:70` | MED | Confirm intended; if not, use a small `play_config` cfg. |
| 6 | `_on_poi_clicked` row-lookup `break`s only the inner loop; harmless today but misreads and would pick the *last* matching row on a duplicate id | `sector_map_v3.gd:2122-2128` | MED | Early-return / flag-break the outer loop. |

## Tier 2 — Dead-code sweep (low risk, cumulative clarity)

Mostly delete-or-document. Verify no `.tres`/save/scene references before removing.
- **Outpost UPGRADES column is fully dead** (~120 lines): `outpost.gd:32,89,429-500,1355-1387` — `UPGRADES:=[]`, `_upgrades_box` never assigned, only survives behind null-guards. Plus 5 never-assigned status labels (`outpost.gd:125-129,1652-1682`) and an unwired `_on_shield_refill` (`outpost.gd:1478-1487`). **Bundle into this same PR:** the stale weight-table comment at `outpost.gd:62` says `= 9 weights` but `WEAPON_SLOT_WEIGHTS` has **11** (missing MODULE ×2) — one-line fix, already caused a downstream doc miscount (code_followups #4).
- **Three orphan backdrop implementations**: `galaxy_backdrop{,_v2,_v3}.gd` referenced by zero `.tscn` (live path is `backdrop_coordinator` → `layer_*`). ~2.5k lines diverging from the live one.
- `explosion.gd:135,196` — `_spawn_sparks_unused()`/`_spawn_debris_unused()` (~90 lines) + their only-caller texture builders.
- `parallax_shadow.gd:22` — `SHADOWS_ENABLED:=false` parks a live `class_name` + per-frame system that never runs.
- `wave_generator.gd:291-334` — `_build_coda`/`_coda_shape` abandoned by the active producer.
- `director.gd:419-440,842-856` — `_dispatch_step_wall`/`_step_wall_layout` (production-unreachable) + unreachable `ignore_recycling` param.
- `sector_map_v3.gd:1883-1924` — `_spawn_celestial_name_label`/`_spawn_poi_name_label` only referenced from commented-out blocks.
- `layer_planet.gd:347` — dead `ci_mat` local; the additive blend the comment promises is silently never applied (BlackHole pulse glow renders MIX not ADD — **also a minor visual bug**).
- Stale `gl_compatibility` rationale comments post-forward_plus pivot: `explosion.gd:360`, `trail_fx.gd:4`.

## Tier 3 — Duplication consolidation (medium effort)

- **T3 theme above** — PixelPlanets setup helper.
- `sector_map_v3.gd:975-1091` — asteroid spawn pipeline copy-pasted ×3 (differ only in count/size/offset) → `_spawn_asteroid(center, px, speed_range)`.
- `run_state.gd:994-1034,1132-1136,1281-1300` — CANNON/HARDPOINT ammo+super reseed implemented 3× → extract `_seed_secondary_ammo`/`_seed_super`.
- `run_state.gd:951-955,1197-1201` — default-blaster construction duplicated → have one call the other.
- `outpost.gd:173-174,1693-1694` — `bounty_changed` + `materials_changed` both trigger a full column teardown/rebuild; a multi-currency purchase rebuilds the whole card tree twice → split a light status refresh from the heavy rebuild, or `call_deferred` debounce.
- `enemy_sword.gd:24-42` — bespoke `_process` broadside loop duplicates `Weapon.FirePattern.BROADSIDE`; hand to data-author to re-express as a `"broadside"` shoot key (convention drift).

## Tier 4 — Architecture / decompositions (opt-in, bigger)

These are judgment calls, not obligations. Do them when a file's size next gets in your way.
- **`player.gd` (3073 lines) god-object** `player.gd:1-3074` — owns ~9 cohesive subsystems. Cleanest extractions: `WeaponAudioController`, `SmartMountController`, `ParticleBeamController`, a `ShieldDamage` component — each already a self-contained `var _*` block + tick fn. `_process` is ~265 lines (`player.gd:866-1131`) with per-frame `/root/Run` lookups that should route through the existing `_run_ref()` cache.
- **`sector_map_v3.gd` (2196) god-object** — the cleanest seam is the pure-deterministic stellar-descriptor block (`_compute_poi_stellar`/`_compute_row_system`/`_compute_boss_stellar`, `sector_map_v3.gd:662-925`) which is *combat-backdrop data derivation*, not map UI — lift into a standalone `sector_stellar.gd`.
- **`sector_map_hd.gd` stringly-typed coupling** `sector_map_hd.gd:218,365,478,521` — host reaches into the embedded map's private state via `.get("_poi_hits")` etc.; renaming any private var silently breaks the host with no compile error. Expose a typed accessor API.
- **`run_state.gd` disabled sector-modifier subsystem** `run_state.gd:739-749` — a large dormant feature (`SECTOR_MODIFIERS_ENABLED=false`) with live vocabulary, rolling, query helpers, and two no-op RNG calls kept only to hold seed-stability. **Keep/cut decision for Roman** before it ossifies further.
- `make_components()` returns roster component instances **by reference** (`director.gd:806,817` + `enemy_roster.gd:1335-1342`) — latent shared-state seam the moment any roster row sets `"components"`; should `.duplicate()` like `Factions.build_components` does.
- `emitter_component.gd:31-35` — a `Trigger.START` emitter re-fires on every parallax recycle (`enemy_core.gd:359`); latent (no live START emitter) but the docstring advertises the mode.

## Performance micro-wins (hand to perf-runner to confirm churn)

- `muzzle_fx.gd:393,414` — rebuilds a fresh `GradientTexture2D` **per shot** (per-shot at autofire/minigun rates); cache statically like `glow_fx._dot_tex`/`trail_fx`.
- `layer_stellar.gd:251` — `_process` does a string `get_node_or_null("Asteroid")` + dict-with-default reads per spinning asteroid per frame across 3 layers; cache the node/material into the `_objects` entry on spawn.
- `explosion.gd:380,386` — `_apply_frame_to_all` calls `_sprites.find(entry)` inside the per-frame loop → O(n²); iterate with the index already in hand.
- `director.gd:662-680` — `_spawn_enemy` re-resolves the `Run` node + modifiers per spawn; cache once per `start_score`.

## Design clarifications for Roman (not code bugs)

The player lane surfaced behavior that may be intended but contradicts comments/docs:
- **Base hull is 2 pips, not 3** (`player.gd:225,2993` set base 2; comments at 222 still say 3). Downstream: **De-Limiter** reaches full bonus after a single pip lost on a base ship (`player.gd:1899-1905`), and the **second damage-tell** at 0.78 lost-hull (`player.gd:627`) can *never* fire on a 2-pip hull (only living damaged state is 0.5). Confirm base = 2 is intended and update the comments + tell logic.
- **Phase mode refunds +1 shield per absorbed bullet** before the i-frame gate (`player.gd:1342-1349`) — a dense volley can top the shield off in one frame. Intended reward, or cap per-frame?
- **Outpost offers** reset to `[]` on Resume (not just app restart) — a run resumed mid-session shows a re-rolled/empty stock (`run_state.gd:122-123`). Confirm the outpost re-rolls on entry when empty.
- **Outpost charges** use non-deterministic `randi()` so they differ on a seed replay (`run_state.gd:447-461`) — fine if charges are deliberately outside the determinism envelope.

## Save-surface hardening (one-time, high value)

`save_to_disk`/`load_from_disk` mirror only `_SAVE_FIELDS`, with no compile-time link to the
`@export`s in `run_save.gd` — adding a field that needs persistence requires remembering both
sides (`run_state.gd:1357-1391`). **Add a `_ready()` assert** that every `RunSave` `@export` has a
matching `_SAVE_FIELDS` entry; pairs naturally with the Tier-1 #1 `new_run()` fix (drive both off
the field list). Minor: `settings.gd:70-73` keybind load has no corruption guard (a non-numeric
value silently `int()`-coerces to 0, clearing a binding); `music_manager.gd:123` shadows `Node.name`.

---

## What's working well (don't "fix" these)

- **Weapon part snapshot/restore** (`weapon_part.gd:57-99`) auto-unions `_mk_knobs()` keys into the
  snapshot set and `push_warning`s on missing ship fields — exactly the no-silent-fallback discipline.
- **Module parts** round-trip cleanly (additive apply / subtractive unapply, default-safe).
- **All seven bosses** set stats before `super._ready()` with no `<=0?default` fallback — 1-HP class dead.
- **Component per-instance** dup + **faction overlay** stacking are correct by construction.
- **`beam_emitter`** host-state guard + child-of-host parenting → no invisible lethal beams, no FSM/tween leak.
- **HUD signal hygiene** (`ui.gd`): every `bind_player` connect is `is_connected`-guarded + disconnected on rebind.
- **`backdrop_coordinator`** flag-gating defaults OFF so it can't leak minefield decor into menu backdrops.
- **`signal_event`** gates lethal/no-op choices *out* of the list rather than silently absorbing them.
- The **`_SAVE_FIELDS` mirror** and **seed-stability discipline** (even around dead code) show the right instincts.

---

## Evaluated from `code_followups_2026-06-15.md`

Triaged the four code-level items the doc-staleness task surfaced:
- **#4 — stale `outpost.gd:62` weight comment** (`9`→`11`, add MODULE ×2): worth it; **folded into the
  Tier-2 outpost cleanup above** (same file, same PR). Confirmed against the working tree.
- **#1 — `row`→`route` rename: declined.** Phantom rename from an *archived* doc; `row` is internally
  consistent and the change touches `run_state` + `sector_map_v3` for zero behavioral gain.
- **#2 — boss filenames ≠ display names (Lash=`boss_reaver`, Aegis=`boss_sentinel`): declined.**
  `.gd`/`.tscn` moves are uid-fragile and sit next to the `boss_base.gd` path-literal landmine; grep
  convenience doesn't justify the regression surface. Keep the alias documented (already is).
- **#3 — Manage-Ship modal: no action** (already removed; the `_ms_`-prefixed residual is live shared
  code, not dead).

## Suggested sequencing

1. **Decide T1 (RNG determinism) + the two keep/cut calls** (sector-modifier subsystem, outpost-offer-on-resume) — these gate later work and are yours, not mine.
2. **Tier 1 bugs** as small individual PRs (#1 `new_run()` reset is the cleanest start; pairs with the save-surface assert).
3. **Tier 2 dead-code sweep** as one PR (cheap, big readability win, low review burden).
4. **Tier 3 duplication** opportunistically — the PixelPlanets helper (T3) first since it's also a correctness guard.
5. **Tier 4 decompositions** only when a file's size next blocks a feature — never as a standalone "refactor sprint."

_Generated from six `design-reviewer` lanes. Findings are point-in-time; verify file:line before acting (active branch may have moved)._

# Work Doc: Two New "Intercept" Signal Events

> **Status:** DRAFT for Roman to review/edit. Not yet implemented.
> **Author:** Claude (from Roman's spec + a codebase investigation). Date: 2026-05-31.
> **Scope:** Two new unknown-signal events that escalate into bespoke combat and can mutate the sector map on failure/ignore.

This doc is the design + implementation plan. The **Open Design Decisions** section near the bottom is the part most in need of Roman's edits — everything else hangs off those answers. Proposed defaults are marked _(proposed)_; change them inline.

---

## 1. Overview

Two new events join the signal-event pool. Both follow the same spine as the existing **Freespace Miner** event: a signal choice escalates into a combat level and pays out on success. New ground these break:

- A **mission objective** inside combat (kill ≥ a quota of a specific enemy), with a **success/fail** outcome — the game currently treats every cleared level as a flat success.
- A **sector-map consequence on failure/ignore** — destroying an outpost (Event A) or converting a node into a minefield (Event B).
- **Eligibility gating** — each event only appears if a valid target node exists on the map; otherwise it's silently omitted and another event rolls.

| | Event A — Intercept Bomber Squadron | Event B — Intercept Minelayers |
|---|---|---|
| Fiction | Corpo bombers are running on a friendly outpost | Supremacy flotilla mining the lane to disable ships |
| Accept → | Combat level w/ bomber runs between waves | Hybrid minefield + minelayer + chaff level |
| Objective | Kill ≥ half the bombers | Destroy ≥ X minelayers |
| Fail/Ignore | An unvisited **outpost** is destroyed/deactivated | An unvisited **signal or asteroid** node becomes a **minefield** |
| Eligibility | Only if an unvisited outpost exists | Only if an unvisited signal/asteroid node exists |

---

## 2. Event A — Intercept Bomber Squadron

### Player-facing flow
1. Player enters an unknown signal node → this event may roll (only if an unvisited outpost exists elsewhere in the sector).
2. Text: a Corpo bomber squadron is making a run on a nearby friendly outpost. Choices:
   - **Intercept** → launches a combat level.
   - **Ignore** → an unvisited outpost is destroyed; back to map.
3. In combat: normal waves play, with **3 bomber runs** interspersed between waves. Player must destroy **≥ half** the bombers to break the run.
4. Outcome:
   - **Succeed** (quota met): outpost saved, bounty payout, post-combat banner ("Outpost saved").
   - **Fail** (quota missed) OR **Ignore**: an unvisited outpost on the map is destroyed/deactivated.

### Mechanics
- **Bombers:** reuse `enemy_bomber.tscn` (16 HP, 2 shield charges, exists but currently unused). ⚠️ See Risk #1 — the bomber currently never leaves the screen; for this event the bombers must **traverse and exit** so unkilled ones "escape to the outpost."
- **Bomber runs:** 3 `silent` sub-waves injected between the normal combat waves (the wave system chains `silent` waves under one banner — see §5). Each run = a small formation of bombers traversing through.
- **Quota:** total bombers across the 3 runs; need ≥ ceil(total/2) killed. Tracked via `main.gd`'s existing per-scene `_enemy_stats` (spawned/killed).

---

## 3. Event B — Intercept Minelayers

### Player-facing flow
1. Player enters an unknown signal node → may roll (only if an unvisited signal or asteroid-hazard node exists elsewhere).
2. Text: a Supremacy flotilla is running mining ops to disable passing ships. Choices:
   - **Intercept** → launches a hybrid minefield combat level.
   - **Ignore** → an unvisited signal/asteroid node converts to a minefield; back to map.
3. In combat: waves of **mines** interleaved with **minelayer** runs and **other enemies mixed in**. Player must destroy **≥ X minelayers**.
4. Outcome:
   - **Succeed:** mining op stopped, payout, banner.
   - **Fail / Ignore:** an unvisited signal or asteroid node becomes a **minefield** node.

### Mechanics
- **Minelayers:** reuse `enemy_minelayer.tscn` (already exists — RARE roster enemy, 12 HP, traverses horizontally dropping smart bomblets, exits cleanly). **No new enemy needed**, and it's already compatible with a kill-quota since it traverses/exits.
- **Level:** a new `Levels.build_minelayer_hybrid_level()` composing: mine waves (reuse the minefield builder's mine patterns) + minelayer runs + light chaff waves, mixed.
- **Quota:** destroy ≥ X minelayers (tracked the same way).

---

## 4. Shared design

- **Escalation spine:** signal choice → set `Run.current_node_type` / `current_hazard_subtype` + a `Run.set_meta("intercept_*", cfg)` flag → `SceneTransition.change_scene(get_tree(), "res://scenes/main.tscn")`. `main.gd::new_game()` reads the meta to build the bespoke level. (Mirrors `_do_freespace_miner()`.)
- **Quota → outcome:** at level-clear, `main.gd` computes killed/spawned for the bomber/minelayer scene path, branches success/fail, and writes a result meta. The map-mutation step reads it on return.
- **Ignore path:** the choice's `action` mutates the map cache directly, then `_finish_to_sector_map(text)`.
- **Eligibility gating:** the event dict is only appended to `_events()` when a valid target node exists (precedent: the `is_asteroid_field` conditional append in `signal_event.gd`). When absent, another event rolls — this is the "something else appears" behavior, free.
- **Payout / banner:** reuse the Freespace Miner payout + `Run.set_meta("post_combat_banner", text)` shown by `sector_map_v3._show_post_combat_banner()`.

---

## 5. Integration map (where it plugs in)

Citations from the codebase investigation (2026-05-31).

**Signal events** — `scripts/signal_event.gd`
- Event = `{ title, body, choices: [{ label, action: Callable(self) }] }` (header `:7-11`).
- Pool: `_events() -> Array` (`:48`), built fresh each `_ready()`; conditional append is the gating seam (`:114-128`, the `is_asteroid_field` precedent).
- Combat escalation precedents: `_do_freespace_miner()` (`:784`, hazard combat + meta), `_do_ambush_combat()` (`:443`), `_do_inspection_fight()` (`:277`).
- Choice-only exit: `_finish_to_sector_map(text)` (`:891`), which calls `Run.mark_node_completed(Run.current_node_id)` (`:909`).
- `scenes/signal_event.tscn` is a passive shell (buttons built in code) — **no scene change needed**.

**Combat / waves**
- `main.gd::new_game()` level dispatch (`:346-445`): boss → `WaveGen.build`; hazard → `Levels.build_*` by `current_hazard_subtype`; **custom → `Run.get_meta("custom_level_path")` loads a `.tres`** (`:413-420`); default combat appends `extra_combat_waves` from meta (`:433-444`, the inject-extra-waves precedent).
- `WaveSpec` (`scripts/levels/wave_def.gd`): `enemy_scene`, `count`, `spawn_interval`, `spawn_delay`, `formation`, `silent`, `announce_text`, per-wave overrides (`max_health`, `movement_override`, etc.).
- `LevelData` (`scripts/levels/level_def.gd`): `waves: Array`, `level_name`.
- `director.gd`: walks `level.waves`; **`silent` waves chain immediately** (no banner/clear-wait, `:77-83`); announced waves wait for clear; level clears when all waves spawned AND no live combatants (`:280-297`). Signals `enemy_died`, `enemy_spawned`, `wave_started`, `level_cleared`.
- Minefield builder: `levels_v2.gd::build_minefield_score()` — a phrase-native `CombatScore` (lane-shaped mine drops + breathers); reads `Run.get_meta("minefield_mine_type")`. Model for the hybrid level.

**Sector map** — `scripts/run_state.gd`, `scripts/sector_map_v3.gd`, `scripts/sector_node.gd`
- POI = `{ id, node_type: int, hazard_subtype: String, pos, completed: bool, modifiers }` (`run_state.gd:128-159`).
- `NodeType { COMBAT, OUTPOST, SIGNAL, BOSS, START, HAZARD }` (`sector_node.gd:5`); hazard subtypes `"minefield"` / `"asteroid_field"` (`run_state.gd:412`).
- **"Unvisited" = `poi.completed == false`** (the live V3 truth; `Run.visited_nodes` is dead V2 code). Set by `Run.mark_node_completed(id)` (`:531`).
- **Mutation is supported in place** — the cache is a mutable Dictionary; the map rebuilds from it on every `_ready()` (`sector_map_v3.gd:179` `_build_pois_from_cache`). Precedent: `run_state.gd:360 _clamp_outpost_density` rewrites `node_type`/`hazard_subtype` in place.
  - **Event B (→ minefield): fully supported** — set `node_type = HAZARD`, `hazard_subtype = "minefield"`; rendering already handles it (`sector_map_v3.gd:450-452`).
  - **Event A (destroy outpost): needs a new state** — there's no "destroyed" state, only `completed`. See Open Decision #4.
- Query unvisited targets: iterate `Run.sector_map_cache.rows[*].pois`, filter `node_type` + `completed == false` (+ `hazard_subtype` for B).

**Enemies**
- Bomber: `scripts/enemies/enemy_bomber.gd` + `scenes/enemies/enemy_bomber.tscn` — exists, 16 HP, V-formation, **not in any roster/wave** (orphaned). ⚠️ `offscreen_mode = NONE`, never exits (`enemy_bomber.gd:62`).
- Minelayer: `scripts/enemies/minelayer.gd` + `scenes/enemies/enemy_minelayer.tscn` — exists, RARE roster (`enemy_roster.gd:273-280`), 12 HP, traverses + drops `enemy_smart_bomblet.tscn`, `FREE_OPPOSITE_SIDE` (exits cleanly). **Wave-ready as-is.**
- `main.gd` already tracks `_enemy_stats[scene_path]` spawned/killed (`:244-248`) and does per-scene-path matching for bounty bonuses (`:262`) — the hook for the kill-quota.

---

## 6. Risks / technical notes

1. **Bomber never exits → blocks level-clear.** `enemy_bomber` parks and never leaves, and `director._live_combatants_present()` counts it, so the level can't clear while any bomber lives — incompatible with "kill half, rest escape." **Fix:** give the event's bombers traversing/exiting movement (like the minelayer's `FREE_OPPOSITE_SIDE`), OR evaluate the quota when bomber waves finish spawning and despawn survivors. (Resolved by Open Decision #1.) The minelayer already exits, so Event B is unaffected.
2. **No "mission failed but survived" outcome exists.** `main.gd::_on_level_cleared` (`:280`) always = success. This needs a new quota-eval + success/fail branch writing a result meta — new code, but the per-scene kill tracking already exists.
3. **No "destroyed outpost" node state.** Only `completed` exists (renders as "spent," not "destroyed"). A true destroyed look needs a new POI field + render branch (Open Decision #4).
4. **Quota tuning is gameplay-sensitive** — counts/quotas (Open Decision #2) should be playtested; keep them as named constants.

---

## 7. Implementation plan (once decisions are locked)

Phased; each phase is independently testable and committable.

- **Phase 1 — Eligibility + event shells.** Add both event dicts to `_events()`, gated on a scan for a valid unvisited target node. Wire the Ignore/decline path: mutate the map cache (A: mark an unvisited outpost destroyed; B: convert an unvisited signal/asteroid to minefield) → `_finish_to_sector_map`. Verify the events appear only when eligible and the map mutates on ignore.
- **Phase 2 — Combat hand-off + bespoke levels.** Accept path sets node type/subtype + `Run.set_meta("intercept_bombers"/"intercept_minelayers", cfg)` → `change_scene(main.tscn)`. Add `main.gd` dispatch for the meta. Author the bomber-run level (normal waves + 3 silent bomber sub-waves; bombers traverse) and `Levels.build_minelayer_hybrid_level()`.
- **Phase 3 — Quota + outcome.** In `main.gd::_on_level_cleared`, compute kills vs quota for the bomber/minelayer scene path, branch success/fail, write result meta. On map return, apply consequence on fail (same as ignore) or payout+banner on success.
- **Phase 4 — Map consequence visuals.** Event B reuses existing minefield rendering. Event A: implement the destroyed/deactivated outpost look per Open Decision #4.
- **Phase 5 — Polish + balance pass.** Banners/strings (in `strings.gd`), tune counts/quotas, verify eligibility edge cases (no targets → event absent), headless + playtest.

---

## 8. Open Design Decisions (Roman — edit here)

1. **Bomber behavior.** _(proposed)_ Bombers **traverse** down through the playfield toward the outpost and exit; unkilled ones "escape." Alternative: keep them parked and evaluate the quota when the runs finish spawning, then despawn survivors. → **Decision:**
2. **Counts / quotas.** _(proposed)_ Bombers: **3 runs × 3 = 9**, need **≥ 5** killed. Minelayers: destroy **≥ 4** (out of ~6 across the level). → **Decision:**
3. **Accept-but-fail outcome.** _(proposed)_ Failing the mission == ignoring it (the consequence fires). → **Decision:**
4. **Destroyed-outpost visual (Event A).** _(proposed)_ v1: mark the lost outpost **deactivated** — greyed + a distinct tint/X — reusing a new `destroyed` POI flag + a small render branch. Alternative: a bespoke destroyed sprite (more art). → **Decision:**
5. **Rewards.** Bounty payout on success — match Freespace Miner, or a custom amount? Any reward for the harder mission? → **Decision:**
6. **Frequency / sector gating.** Should these be rarer than normal signal events, or gated to later sectors? → **Decision:**
7. **Anything I mis-modeled** in the fiction or flow above — correct inline.

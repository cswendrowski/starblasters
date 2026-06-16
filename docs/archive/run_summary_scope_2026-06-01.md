> **✅ ARCHIVED 2026-06-15 — this shipped; historical design doc.** Current behavior: scripts/screens/run_summary.gd + run_history.gd (stats, dated history index, run timer).
> The victory / "patrol complete" path also shipped — cleared_summary.gd routes a final-sector clear to run_summary as outcome "victory". Do not cite as a to-do.

# End-of-Run Summary + Run History — Scoping Report

**Date:** 2026-06-01 (re-audited 2026-06-05, added Run Timer section)
**Status:** Scoped, not built. Decisions captured below; implementation deferred.

> **Re-audit 2026-06-05:** Re-verified every hook claim against the current branch. **No new stats instrumentation has landed** — all Tier-1/2/3 gaps below are still open (no fire signal on `player.gd`, no hit signal on `enemy_base.gd`, no bounty-spend choke-point, no node-visit fix, no `RunStats` object). Only drift: death flow moved `main.gd:370` → `:373`. Note: `enemy_base.gd:96` carries a comment referencing "a future RunStats accumulator" — intent is acknowledged in-code but nothing is wired. If hooks were built, they are on an unmerged branch not visible here. A **Run Timer** section has been appended (see below).

## Goal

An end-of-run summary stats screen shown when the player **completes a patrol or dies**, surfacing interesting per-run stats. Plus a **dated run-history index** reachable from the main menu so players can review past runs.

Candidate stats: total kills, boss kills, unique enemy types encountered, unique weapons used, shots fired / shots hit (accuracy), total damage taken (shield + hull), total bounty gained and spent, asteroids destroyed, mines cleared, locations visited, stations visited, signals investigated.

## TL;DR

Moderate effort, not a quick win — but it splits cleanly into a cheap core and an expensive long tail.

- A solid summary covering ~half the stat list is **fairly straightforward (~½–1 day)** because much of it is already half-tracked on the `Run` autoload.
- The *full* list (accuracy, bounty spent, per-weapon usage, locations visited) needs **new instrumentation in several systems that have no hooks today**.
- The **dated run-history index** is its own self-contained chunk (~½–1 day) and is the cleanest part of the whole thing.

The core architectural decision driving the effort: **a run-wide stats accumulator** (`RunStats` on the `Run` autoload). Today stats are scattered — some accumulate on `Run`, some live per-combat on `main.gd` and get wiped every level, and many don't exist at all.

## What already exists (cheap to surface)

These accumulate on the `Run` autoload right now:

| Stat | Status |
|---|---|
| Total kills | ✅ `Run.enemies_killed` |
| Boss kills | ✅ `Run.bosses_defeated` |
| Sectors cleared | ✅ `Run.sectors_cleared` |
| Max bounty earned | ✅ `Run.max_bounty_earned` |
| Distance | ✅ `Run.run_distance` |
| Unique enemy types | ✅ `Run.encountered_enemies` (codex dict — already persisted to disk) |

The existing death screen (`scripts/run_summary.gd`) already reads four of these. And `scripts/cleared_summary.gd` already has a per-enemy-type tally with live sprite previews — but it's per-combat and thrown away each level (`main.gd` `_enemy_stats`, cleared on `new_game()`). **That UI work is reusable** for the run summary.

## What needs new tracking (the real work)

Three difficulty tiers, none with run-wide accumulation today.

### Tier 1 — signal exists, just needs a counter (easy)
- **Damage taken (shield vs hull)** — `Player.damaged` already fires with `0`=shield-absorb, `1`=hull-loss. Just tally it.
- **Bounty gained** — flows through `Run.record_kill()`; add an accumulator.
- **Asteroids destroyed** — per-level counter exists (`_asteroids_killed_this_level`), just needs to roll up instead of reset.

### Tier 2 — needs a new hook in a hot path (medium)
- **Shots fired** — `player.gd` `fire_primary()` / `fire_secondary()` emit no signal today. Needs instrumentation (hot path — don't allocate per-shot).
- **Shots hit / accuracy** — `enemy_base.gd take_hit()` returns a bool but emits nothing. Needs a hit counter.
- **Bounty spent** — outpost does bare `run.bounty -= cost` subtractions in several places; needs a single choke-point to total.
- **Mines cleared** — no dedicated counter; currently indistinguishable from other kills except by scene_path. Doable via the kill path.

### Tier 3 — flow gap, needs care (medium-annoying)
- **Locations / stations / signals visited** — the **V3 sector map bypasses `mark_node_visited`** (sets `current_node_id` directly), so `Run.visited_nodes` is unreliable. Track via `mark_node_completed` (which *is* reliable) plus node-type counting.
- **Unique weapons used** — zero tracking today. Needs a hook when the active cannon changes / fires.

## Two structural gaps worth flagging

1. **There is no victory / "patrol complete" screen.** `run_summary.tscn` is reached *only on death* (`main.gd:370`). Final-sector clear currently funnels through the endless-mode prompt on the cleared-summary screen. So "when the player completes a patrol" is a **net-new code path**, not just a new screen. (`TOTAL_SECTORS = 3` exists but only drives a header label.)
2. **Stats reset boundaries.** A `RunStats` object must reset in `Run.new_run()` alongside the other run-scoped fields, and be snapshotted into the history index at *both* exit points (death **and** victory) **before** reset.

## Run-history index (the cleanest part)

Well-supported by existing patterns. `run_state.gd` already writes `user://enemy_codex.json` via plain `FileAccess` + `JSON.stringify`. A dated run-history index is the same pattern: append a record `{date, outcome, kills, bounty, sectors, ...}` to a JSON array on each run-end. The main-menu entry follows the existing `_install_codex_button()` injection pattern in `scripts/main_menu.gd` exactly. The only real work here is the history-list UI scene.

## Decisions locked in

- **Accuracy counting:** **per-projectile spawned** — 1 shot = 1 projectile spawned (hook `player.gd` fire functions), 1 hit = 1 enemy contact (hook `enemy_base.gd take_hit`). Piercing / AoE / multi-hit can push accuracy past 100%; that's accepted as the simplest model.

## Effort estimate

| Phase | Scope | Rough effort |
|---|---|---|
| **1. `RunStats` core** | Accumulator on `Run`, reset wiring, Tier-1 stats, redo death summary to show them | ~½–1 day |
| **2. New instrumentation** | Tier-2 + Tier-3 hooks (shots/accuracy, spent, visits, weapons, mines) | ~1–1.5 days |
| **3. Victory path** | Net-new "patrol complete" summary screen + flow wiring | ~½ day |
| **4. History index** | JSON persistence + main-menu entry + history-list UI | ~½–1 day |
| **Total** | Full feature as described | **~3–4 focused days** |

## Recommended order

Ship **Phase 1 first** as a standalone improvement — it makes the existing death screen genuinely interesting using data you already have, and proves out the `RunStats` pattern before instrumenting hot paths. Then **Phase 4** (history index, cleanly self-contained). Then **Phases 2 / 3** as appetite allows.

## Run Timer (added 2026-06-05)

A run timer is part of this summary scope. Good news: the timing infrastructure makes this **one of the cheapest pieces** — most of the "when does it run / pause" logic falls out of existing scene boundaries for free.

### Design: what time do we count?

Two philosophies for the headline "run time":

- **(A) Active combat time** *(recommended)* — sum of per-level combat timers only. Excludes the sector map, outpost/shop, signal events, summaries, scene-transition fades, combat intro/outro, and pause. Reproducible, speedrun-friendly, and doesn't punish the player for deliberating in shops. This is the natural fit for a roguelite shmup.
- **(B) Wall-clock total** — everything from `new_run()` to death/victory, including shopping and map navigation. Simpler conceptually but penalizes thinking time and is dominated by how long the player browses the outpost.

**Recommendation: (A) as the headline stat.** Optionally also surface (B) as a secondary "total elapsed" line if it's interesting, but (A) is the one worth optimizing the UI around. The decision of whether to show (B) at all is the one open call here.

### Why (A) is nearly free

The "active" boundaries already exist and auto-exclude all dead time:

- **Per-level timer** = a delta-accumulator that runs only while `playing == true` (`main.gd:563` start / `main.gd:309` `_on_level_cleared` stop / `main.gd:353` `_on_player_died` stop). Keying on `playing` automatically excludes the ~3.4s intro (`_run_intro`) and ~2.35s outro (`_run_outro`) dead time.
- **Pause auto-excludes itself.** The pause menu sets `get_tree().paused = true` (`pause_menu.gd:44`). An accumulator node left at the default `PROCESS_MODE_PAUSABLE` stops ticking while paused — no manual pause-handling code needed. (Use a delta-accumulator on a pausable node, **not** `Time.get_ticks_msec()`, precisely because the latter does *not* auto-pause and would need manual interval subtraction.)
- **Map / shop / signal / transitions auto-excluded.** Those are separate scenes where the combat accumulator doesn't exist. Since overall run time = sum of committed per-level times, non-combat scenes contribute nothing by construction. The ~0.95s `SceneTransition` fades are likewise excluded (`playing == false` during them).

### Anchor points

**Overall run timer** — store `run_time_seconds: float` on the `Run` autoload (survives all scene changes for free, since `Run` is an autoload):
- **Zero:** in `new_run()` (`run_state.gd:235` reset block), alongside `run_distance`.
- **Accumulate:** add the just-finished level's time in `_on_level_cleared` (`main.gd:309–349`) — the same handler that already snapshots hull/shield back into `Run`. Also flush on death in `_on_player_died` (`main.gd:353`) so the final partial level counts.
- **Stop / display:** death → `run_summary.tscn` (`main.gd:373`). **Victory stop point does not exist yet** — there's no patrol-complete path (see "structural gaps" above), so the overall timer's "stop on victory" must be wired whenever that screen is built.

**Per-level timer** — bracket a local accumulator:
- **Start:** `playing = true` (`main.gd:563`).
- **Stop:** `_on_level_cleared` (`main.gd:309`) or `_on_player_died` (`main.gd:353`).
- Optionally store each level's time in a `RunStats` list so the summary can show a per-level breakdown (and `cleared_summary` could show "cleared in 1:23"). If per-level breakdown isn't wanted, only the running total on `Run` is needed.

### Persistence (save / resume)

To survive mid-run save/quit/resume, `run_time_seconds` must round-trip through `RunSave`:
- Add `run_time_seconds` to `_SAVE_FIELDS` (`run_state.gd:874`) **and** add a matching `@export var run_time_seconds: float = 0.0` to `run_save.gd` (mirror the existing `run_distance` export). Adding to only one side silently drops it.
- Saves fire only at sector-map entry (`sector_map_v3.gd:195`, gated to "between map visits"). Because level time is committed to `Run` in `_on_level_cleared` *before* the next map's save, a resumed run keeps time up to the **last completed level**.
- **Edge case (accepted):** time in a level abandoned via pause-menu "Leave to Menu" (`pause_menu.gd:98`) or a mid-combat quit is lost — that level never reached `_on_level_cleared`. This matches how in-progress bounty already behaves, so it's consistent.

### Display

- **v1 (recommended): summary-only.** Show run time on the death/victory summary and in the history index. No HUD work.
- **Optional later: live HUD clock.** No clock widget exists today (`ui.gd` has `_process` but no run clock); a HUD label would be greenfield. Defer unless wanted.

### Verify-before-building flags (from the timer audit)

1. The live sector map is `sector_map_hd.tscn` (per `sector_map_route.gd:4`), a deferred-native wrapper — the canonical `save_to_disk()` logic was read in `sector_map_v3.gd:195`. Confirm where the save actually fires in the HD path before wiring persistence.
2. No victory transition exists, so the overall timer's stop-on-victory point is net-new (shared with the summary feature's "no victory screen" gap).

### Effort

**~½ day.** One pausable accumulator node in the combat scene, a few-line commit in `_on_level_cleared` / `_on_player_died`, the `new_run()` reset, and the 2-line persistence wiring. The per-level breakdown (if wanted) folds into the same `RunStats` object the summary feature already needs — so building the timer alongside Phase 1 shares almost all the plumbing. Effectively **near-zero marginal cost if done with Phase 1.**

## Key file references

- `scripts/run_state.gd` — `Run` autoload; existing accumulators, `new_run()` reset, codex JSON persistence, `mark_node_completed` / `mark_node_visited`.
- `scripts/run_summary.gd` + `scenes/run_summary.tscn` — current death screen (reached only via `main.gd:370`).
- `scripts/cleared_summary.gd` — per-enemy-type tally UI with sprite previews (reusable).
- `scripts/main.gd` — `_enemy_stats` per-combat tally; death flow (`:370`); level-clear / `_run_outro`.
- `scripts/player.gd` — `fire_primary` / `fire_secondary` (no signal yet); `damaged` signal (0=shield, 1=hull).
- `scripts/enemies/enemy_base.gd` — `take_hit()` (returns bool, emits nothing).
- `scripts/main_menu.gd` — `_install_codex_button()` injection pattern for a new "Run History" entry.

**Run-timer-specific:**
- `scripts/main.gd` — `playing` flag (`:563` set true / `:353` false); `_on_level_cleared` (`:309`, commit site); `_on_player_died` (`:353`); `_run_intro`/`_run_outro` dead-time brackets.
- `scripts/pause_menu.gd` — `get_tree().paused = true` (`:44`); pausable accumulator auto-excludes paused time.
- `scripts/run_save.gd` — `@export` mirror; add `run_time_seconds` here (template: `run_distance`).
- `scripts/run_state.gd` — `_SAVE_FIELDS` list (`:874`); `new_run()` reset block (`:235`).
- `scripts/sector_map_v3.gd` — `save_to_disk()` trigger (`:195`); verify against live `sector_map_hd.gd` (`sector_map_route.gd:4`).
- `scripts/ui.gd` — HUD; no run clock today (optional live-display site).

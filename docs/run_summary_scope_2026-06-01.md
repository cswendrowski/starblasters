# End-of-Run Summary + Run History — Scoping Report

**Date:** 2026-06-01
**Status:** Scoped, not built. Decisions captured below; implementation deferred.

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

## Key file references

- `scripts/run_state.gd` — `Run` autoload; existing accumulators, `new_run()` reset, codex JSON persistence, `mark_node_completed` / `mark_node_visited`.
- `scripts/run_summary.gd` + `scenes/run_summary.tscn` — current death screen (reached only via `main.gd:370`).
- `scripts/cleared_summary.gd` — per-enemy-type tally UI with sprite previews (reusable).
- `scripts/main.gd` — `_enemy_stats` per-combat tally; death flow (`:370`); level-clear / `_run_outro`.
- `scripts/player.gd` — `fire_primary` / `fire_secondary` (no signal yet); `damaged` signal (0=shield, 1=hull).
- `scripts/enemies/enemy_base.gd` — `take_hit()` (returns bool, emits nothing).
- `scripts/main_menu.gd` — `_install_codex_button()` injection pattern for a new "Run History" entry.

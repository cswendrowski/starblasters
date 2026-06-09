# Autonomous Work Log — Lead Session

**Branch:** `lead-autonomous-2026-06-08` (off `pattern-eligibility` @ `09e614a`)
**Mandate (Roman, 2026-06-08):** work the TODO down autonomously from design docs/specs; reuse
existing systems; defer anything needing Roman's input/eyeball/art; verify headless; commit clean;
keep this timestamped worklog + a test/review tracker. No pushes (Roman unavailable).

---

## 🧪 For Roman to test / review when back
_(things verified headless but wanting an in-game eyeball or a design call)_

- **Swarm Launcher (new secondary)** — equip it (it's in the outpost HARDPOINT_WING pool) +
  fire with C. Verify the FEEL: 6px/f close speed, the tight homing arc, distinct-target fan-out,
  re-acquire on kill, 3s cooldown / 6 ammo. **Art is a placeholder** — reused `energy_bolt_small.png`
  (8px) tinted yellow-orange + a glow + trail; swap for dedicated art if you want. The "tight turn
  arc" has no explicit knob (it's homing_accel-vs-speed) — tell me if it should turn tighter/looser.
- **Run Summary Phase 1 + Run Timer** — the death screen now shows Time / Bosses / Bounty earned /
  Damage taken (shield·hull) / Asteroids. Verify the numbers read right after a real run, and that
  the **timer** (active-combat only — excludes map/shop/pause/intro/outro) feels right. Stats also
  land in the run-history record (the per-run detail).
- **Armory tab (Codex)** — open Codex from the main menu; the 4 new categories (Primary / Secondaries /
  Super / Shift Modes) list your kit with a rotating projectile preview + a codex blurb. Verify the
  blurbs read well + the layout. **Icon gap:** modes / super / particle-beam / drones have no
  projectile sprite, so they show name + blurb only — want little icons commissioned for those?

## 🔧 Bug-hunt fixes applied (2026-06-09)
Three parallel design-reviewer sweeps → triaged → **8 safe high-value fixes applied & verified**
(parse-check clean, regression suite green: run_stats / swarm_launcher / shift_mode_phase2 /
outpost_hub_services all PASS, combat boot exit 0). Full triage incl. 18 deferred items +
verified-clean list in `reports/code_review_findings_2026-06-09.md`. Fixes:
1. `main.gd` — minelayer no longer miscounted as a cleared mine (precise basename match).
2. `player.gd` — Hyper keeps a dry replacement primary firing (unlimited-ammo gap).
3. `player.gd` — death-bomb guarantees its own survival i-frame (latent fragility).
4. `base_missile.gd` — drop `and "hull" in area` silent-fallthrough; gate on method only.
5. `swarm_launcher.gd` — clear stale `secondary_bullet_scene` on apply.
6. `player.gd` — `die()` frees the Phase glow node.
7. `signal_event.gd` — `_apply_bounty` routes spends through `spend_bounty` (run-summary accuracy).
8. `main.gd` — corrected misleading run-timer comment + flagged latent double-count trap.
Deferred (in the report, NOT touched): run-gen seed determinism (combat lane / design call),
perf items (→ perf-runner), beam-SFX leak, sell-back tally, Mk-reseed-ammo, manage_ship dead rows,
outpost aliasing, swarm `.tres` parity, equip_part lint.

## 📊 Status (2026-06-09)
Completed the cleanly-buildable, no-decision, lead-lane items: **Swarm Launcher**, **Run Summary
Phase 1+2(partial)**, **Armory tab**, + verified/closed several stale TODOs (Heavy Blaster, boss
never-pair, Mk-cap, planet drift, etc.). The TODO's remaining items now need **Roman** (passive-module
architecture + reify decision, cannon Mk-flattening), **art** (faction sprites, item icons),
**playtest/feel** (s_s_rush, tracer, chaff walls, fire_offset), or are the **combat session's active
lane** (conductor no-repeat, wave-pattern composition — leaving to them to avoid stepping on their
in-flight work). → **Pivoted to the code-review + bug-hunt** per Roman's fallback instruction; report
at `reports/code_review_findings_2026-06-09.md`.

### Big item explicitly deferred — Passive-Module layer
The marquee remaining lead-lane feature, BUT blocked on design/architecture calls I shouldn't make
blind: (1) the slot model — the doc's "4 reserved-enum slots" (DEVICE_BAY_2/SHIELD/wings) conflicts
with "pick any 4 modules" (typed slots ≠ a free bay); needs a `Run.modules: Array` vs typed-slots
call. (2) reify-vs-present Shield (a deep, playtest-heavy refactor of the damage pipeline). (3) the
roster magnitudes are all feel-tuning. Recommend Roman settle (1)+(2) then I build it in phases.

## ⏸️ Deferred (need Roman) — not blocking other work
- **RecycleController (Pillar 2)** — playtest-heavy (regression surface = whole roster); needs the
  RecycleTuner + Roman's feel pass. Building the tuner is fine; the controller tuning is his.
- **s_s_rush facing / tracer-art doubling / cohesive-chaff feel** — eyeball bugs.
- **Cannon Mk flattening (#1)** — awaiting Roman's go (per-cannon re-key, feel-defining).
- **Faction gap-unit sprites, Shipyard stat editor, gamepad in-app rebind** — art / big-tool / his input.

---

## Worklog

### 2026-06-09 — Swarm Launcher secondary ✅ (`4405b29`)
Built the new secondary end-to-end from `docs/swarm_launcher_secondary_2026-06-08.md`. Reused
`base_missile` (extracted a `_resolve_player_target` virtual, behavior-preserving, so the swarm
subclasses it for assigned-target + re-acquire-on-death), the secondary pipeline (added a clean
`SecondaryMode.SALVO` + `_tick_salvo` rather than abusing DEPLOY's drone-shutdown path), `GlowShaderFx`,
the shared missile trail, and existing projectile art. Distinct-target round-robin + re-acquire are
the only net-new logic. Headless-verified (registration, Mk 4/6/20, mode/ammo/cooldown, distinct
targeting + round-robin, ammo/cooldown via input). Combat + parse clean. → flagged for Roman's feel/art pass.

### 2026-06-09 — Run Summary Phase 1 + Run Timer ✅ (`aedc7a1`)
Built the cheap Tier-1 core from `docs/run_summary_scope_2026-06-01.md`: a `run_stats` accumulator +
`run_time_seconds` on Run (reset/persisted), tallying off signals that ALREADY exist (Player.damaged
0/1, Run.record_kill, the asteroid counter) — no hot-path allocation. Active-combat timer keyed on
`playing` (pausable node auto-excludes dead time). Death screen + run-history record show the stats.
Headless-verified end to end. Phases 2 (shots/accuracy/spent/visits) + 3 (victory path) remain.

### 2026-06-09 — Armory tab + item codex strings ✅ (`518443a`)
Centralized the genuinely-missing content: codex BLURBS for all ~21 player items in a new
`armory_strings.gd` (mirror approach — names stay on the parts), and folded an **Armory** into the
existing enemy codex (4 categories: Primary / Secondary / Super / Modes) reusing its nav + rotating-
sprite preview + blurb machinery. Items with a projectile sprite show it; modes/super/beam show name
+ blurb (icons TBD — art). Headless-verified. → flagged for Roman's eyeball + the icon-art gap.

### 2026-06-09 — Run Summary Phase 2 (partial) ✅ (`74aba2f`)
The clean, well-defined Phase 2 stats: a `Run.spend_bounty()` choke-point (routed all 7 outpost +
signal purchase sites) → exact **bounty spent**, and **mines cleared** off the kill scene_path. Both
on the death screen + history record. Deferred the murky ones (shots/accuracy — ambiguous model +
riskiest hot-path hook; visited; unique-weapons) + Phase 3 (victory path). Headless-verified.

### 2026-06-09 — small reconciliations
- **Boss conflict_tags never-pair** — was already fully built (`_BOSS_CONFLICTS` + `_pick_row_bosses`
  greedy skip); VERIFIED via `tools/test_boss_pairing.gd` (0 forbidden pairs, sectors 2/3). Closed.
  Noted the sector-1 pool-size caveat (3 bosses / 3 slots → unavoidable pairs by design) for Roman.
- **Heavy Blaster cooldown** TODO closed as STALE (the 0.28→0.18 Mk scaling is by-design now, not the
  drift the item described — no change). _(TODO-only.)_


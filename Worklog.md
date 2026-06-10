# Worklog — Worklist execution (started 2026-06-10)

Lead-dev pass over `Worklist.md`. Operating unattended once Roman says "go": no pushes/publishes
until approved, log everything that needs his eyeball/test, reuse + extend existing systems over
bespoke, build dev tools he'll need to review. This file is the living log.

---

## Operating rules (from Roman's brief)
- **Hold all pushes + publishes** until explicit approval. Local commits/branches only.
- Roman is **unavailable during execution** — no live eyeball, GIF review, or playtest. Anything
  needing his eyes goes in the **Needs-Roman** log below, built with "test to follow" expected.
- **Reuse/extend existing systems**; bespoke only when unavoidable, and flagged if so.
- Stay organized in branches/commits.
- Extend/build dev tools Roman will want for review/testing.

## Branch strategy (proposed)
- One integration branch off `main`: `worklist-2026-06-10`.
- Logical, self-contained commits per task; risky/large items (renderer pivot, recycler) on their
  own sub-branches merged in when green. Nothing pushed.

---

## New asset inventory (to import — Worklist "numerous new files")
Counts from `git status`. **Step 0** once greenlit = headless `--import` pass + sidecar/commit hygiene.
- **Enemy weapon SFX (wav→ogg):** `enemy_blaster_1-8.ogg`, `enemy_mg_1-6.ogg` (old `.wav` + `.import` deleted).
- **New player weapon SFX:** `autocannon_start/stop` + `autocannon_shoot_01-09`; `minigun_shoot_01-12` +
  `minigun_stop`; `autolaser_shoot_1-7`; `spread_shoot_1-6`; `smart_bomb_sweetener_1-2`.
- **Reworked SFX:** `rotary_laser_shoot_1-6` (modified; `rotary_laser_loop` retired);
  `wave_shoot_1-6` (modified; `wave_big_shoot_*` retired — wave gun no longer swaps at Mk5).
- **Outpost SFX:** `Sound/outpost/{equip,unequip,upgrade,repair_1,repair_2}.ogg`.
- **Explosion SFX:** `Sound/weapons/explosions/` ~84 files, `Close/Medium/Distant_NN` — **need renaming**
  (`TomWinandySFX_Explosions Volume I_CloseExplosion_01` → `CloseExplosion_01`).
- **Sprite:** `graphics/projectiles/minigun_tracer.png` (new Minigun hitscan beam art).
- **Cruft:** `Sound/desktop.ini` → gitignore.
- NOTE: many `*.import` sidecars were deleted across `Sound/` — `--import` regenerates them; verify no
  dangling `.import`-less tracked audio and no broken `uid://` refs after.

---

## Task clusters, scope & reuse notes

Legend: ⮕ reuse/extend target. ⚠ risk/needs-eyeball. 🔧 dev-tool opportunity.

### P0 — Import & housekeeping  *(unblocks audio + weapons)*
- `--import` all new assets; rename explosion SFX to short names; gitignore `desktop.ini`; resolve the
  deleted-`.import` churn. Verify parse + boot clean.

### A — Audio rewire  *(after P0)*  ⮕ `weapon_sfx.gd`, `enemy_sfx.gd`, `mine_sfx.gd`, `sfx.gd`, WS.FireSfxKind
- Enemy fire `.wav`→`.ogg` swap (enemy_sfx + per-enemy refs: gunship/turret/rocket/bomber_wing/firecore).
- Wire new player weapon SFX: autolaser, spread, wave (single set, drop Mk5 swap), rotary (new set, drop loop).
- Smart-bomb detonation SFX (`smart_bomb_sweetener_*`).
- Outpost action SFX (equip/unequip/upgrade/repair) — hook outpost interactions.
- **Explosion distance system:** new helper picking Close/Medium/Distant by explosion→player distance;
  retire old explosion sound; wire from `explosion_fx.play`. ⮕ extend `sfx.gd`/new `explosion_sfx.gd`.
- "New incoming-weapon sounds" — needs mapping (which files → which incoming weapons). ❓ see Q.

### B — New & fixed weapons  ⮕ `Part`/`weapon_part.gd`/`metered_primary.gd`, `Weapon`/`BulletVariant`, `PartFactory`/`part_catalog`
- **Minigun (primary):** hitscan/beam dealing to first enemy hit; machinegun ammo+Mk model; rotary rate of
  fire; `minigun_tracer` beam (no anim); mg muzzleflash + small-shell eject; minigun_stop sound (interruptible).
  ⮕ reuse `BeamEmitter` (enemy beams) adapted for the player, + `metered_primary`. ⚠ beam-as-player-primary is new.
- **Autocannon (primary):** reworks Machinegun — 1.5s spin-up (start sound), stop sound on last shot,
  same projectiles/damage/scaling/muzzleflash as Machinegun; interruptible stop, must re-spin.
  **DECIDED (Q2): REPLACES Machinegun** in the weapon pool — Machinegun retired from `part_catalog`
  roll/shop pool; its `.tres`/projectile/muzzle/shell assets stay for Autocannon + Minigun reuse.
- **Rotary Laser Mk5+ projectile swap:** from Mk5 use the auto-laser projectile/sprite; damage/RoF unchanged.
  ⮕ `rotary_laser_cannon.gd` `_apply_visuals` swaps `bullet_scene` by mark.
- **Enemy "Cannons still wrong" (re-listed):** re-investigate — last session set `random_frame=false`; Roman still
  reports not-animated + glow-on-whole-sprite. Deep-dive the cannon scene + GlowShaderFx frame crop in COMBAT (not bench). ⚠

### C — EM Torpedo (secondary) + wreck_layer  ⮕ `base_missile.gd`, secondary/HARDPOINT_WING pattern, `damage_smoke_trail`
- **wreck_layer:** near-parallax-depth layer enemies "fall" into on death; testbed = EM Torpedo. ⮕ parallax stack
  (`backdrop_coordinator`/near layer) for depth/grade. ⚠ new layer.
- **EM Torpedo:** rocket flies 2s → blue-yellow lightning burst, multi-hit, strips/ignores shields, detonates
  missiles/rockets; alt kill: 25% explode / 75% inert drift (rand rotation) toward bottom + smoke (player smoke,
  respecting parent motion) into wreck_layer. ❓ Q3 scope (depends on recycler/wreck decisions).

### D — Phase Mode + Hyper Mode  ⮕ `shift_mode_system` parts (`phase_shift`, `hyper_mode`), `player.gd`, `outline_fx`
- **Phase:** turn blue + fading blue after-images; invuln; can't hit enemies; absorb enemy bullets → +1 shield each;
  3s window; disable shooting. ⮕ extend the existing shift-mode hooks in `player.gd`.
- **Hyper:** player outline pulses orange, speeding up as it runs out. ⮕ `_rebuild_outline`/outline material pulse.

### E — Outpost UX overhaul  ⮕ `outpost.gd`, `armory_strings.gd` (docs/armory_string_expansion), `ui_color_reference.md`
- Blaster vs Primary disambiguation ("Blaster" / "Primary Weapons"); item label rarity color; drop "Tier" → type;
  "Defeat boss to restock" label; one-of-each equipped safeguard (keep higher Mk, stow rest); no-dupe/own-better roll
  filter; **dynamic item cards** showing the Mk's stats/improvement w/o 9 strings per item (compute from Part curves).

### F — Music ramping  ⮕ `music_manager.gd` (intensity walk I1/I2/Main), `director.gd` signals
- I1→I2 on first waves; I2→Main past wave 4; boss→Main always; ramp down to I1 on clear; **+1 permanent step on boss
  beat** (Sector Map). ⮕ wire director wave/boss/clear events to `Music.set_context`/intensity API. 🔧 music-ramp dev probe.

### G — HUD  ⮕ `scenes/ui.tscn`/HUD script, weapon-light widget
- Flash weapon light while regenerating ammo (autolaser/rotary); darken when no ammo; always show ammo (even 0);
  fix out-of-ammo glyph (missing font char).

### H — Patterns & enemy waves  ⮕ `patterns/`, `director.gd`, `wave_generator.gd`
- Omni movement: stay in firing zone, respect bottom no-fly unless exiting; Lane Hook: leave play area properly;
  Supremacy Push: controlled numbers (one/lane or /crossing, no overlap globs).

### I — Play Area / Recycler  ⮕ `docs/recycling_system_pillar2_2026-06-04.md`, `MidDepthPresentation`, `enemy_base/core`
- Off-screen enemies not killed by bullets/bomb waves (guard offscreen hits).
- **Pillar 2 Recycler — DECIDED (Q3): FULL SEND.** Build order per the doc: RecycleTuner dev scene (prereq) →
  `RecycleController` helper (one timing budget; fly-back ghost via `MidDepthPresentation`) → formation-aware
  re-entry via the conductor → **merge the missile-cruiser bespoke recycle + migrate the whole roster** onto it.
  ⚠ Regression surface = entire roster, **playtest-only verification** → I'll build + headless-smoke each step and
  log a detailed playtest checklist in Needs-Roman (can't verify recycle feel/visuals unattended). 🔧 RecycleTuner.

### J — Visual Effects  ⮕ existing "ball explosion" variant, firecore drop logic, zealot faction
- Zealot enemies → ball explosion **only if they die without dropping a firecore**; firecore gets ball explosion;
  normal explosion if a core drops. ⮕ `explosion_fx` variant routing in zealot death path.

### K — Enemy Bench (dev)  ⮕ `scripts/dev/enemy_bench.gd`
- Tag per enemy: can-recycle, how many times, chance to recycle vs flee. 🔧 extend bench UI + write to recycle fields.

### L — Sector Map  ⮕ `manage_ship.gd`
- Manage Ship: view/manage shift-mode items (currently no shift-mode slot UI).

### M — Onboarding  ⮕ `onboarding.gd`
- Refresh stale text, cover missing gameplay; reuse existing pages, add only if necessary.

### N — DEV: Hangar deep-dive  ⮕ `hangar.gd` SubViewport
- Muzzle flashes green + bullets missing → diagnose + **rebuild the SubViewport** so the live-fire bench works. ⚠🔧
  (re-listed from last session — my parent-routing fix was insufficient; needs a real rebuild.)

### O — CORE: Forward+ / Windows-only renderer pivot  ⏸ HELD (DECIDED Q1)
- **Deferred to an attended session** — can't be visually validated unattended. Everything else this run
  stays on gl_compatibility. (When tackled: Forward+, drop web→Windows export, new itch channel, update
  `project.godot` / `export_presets.cfg` / `publish.ps1`.)

---

## TODO.md cross-references
- Recycler Pillar 2 ↔ TODO "Recycling — Pillar 2" (RecycleTuner prereq + RecycleController + formation re-entry) — same work.
- Patterns (Omni/Lane Hook/Push) ↔ TODO pattern/wave backlog (cohesive chaff, conductor no-repeat).
- "Cannons still wrong" ↔ prior-session cannon fix (insufficient) — re-investigate.
- Music ramp is **new** vs TODO "Music must keep cycling" (done) — different issue.

## Dev tools to build/extend for Roman's review
- **RecycleTuner** (recycler prereq; JSON persist + Copy-GDScript).
- **Enemy Bench** recycle-tagging (cluster K).
- **Weapon test** — extend the (fixed) Hangar to audition Minigun/Autocannon/EM Torpedo + new SFX.
- **Music-ramp probe** — trigger wave/boss/clear events to hear ramp.
- **Explosion-SFX-by-distance** auditor (small dev scene/button).

---

## Needs-Roman (eyeball / playtest / decisions) — running
- _(to be filled during execution)_

## Locked execution sequence (Q4: follow proposed order)
1. **P0** Import & housekeeping (rename explosion SFX, gitignore desktop.ini, sidecar hygiene).
2. **A** Audio rewire (enemy ogg swap, player weapon SFX, smart-bomb, outpost, explosion-by-distance).
3. **B** Weapons — Minigun (new), Autocannon (replaces Machinegun), Rotary Mk5+ projectile swap, enemy-cannon re-investigation.
4. **D** Phase Mode + Hyper Mode.
5. **E** Outpost UX overhaul.
6. **F+G** Music ramp + HUD weapon-light/ammo/glyph.
7. **H** Patterns/enemies (Omni, Lane Hook, Supremacy Push).
8. **I+C** Recycler FULL SEND (RecycleTuner → controller → roster merge) + wreck_layer + EM Torpedo.
9. **J,K,L,M,N** Zealot ball-explosion VFX, Enemy-Bench recycle tags, Manage-Ship shift modes, Onboarding refresh, Hangar SubViewport rebuild.
- **O** Renderer pivot — HELD for attended session.

## Running log
- 2026-06-10: Reviewed Worklist + TODO + docs + new-asset set. Authored plan. Decisions: renderer **held**;
  Autocannon **replaces** Machinegun; recycler **full send**; **proposed sequence** confirmed. Sequence locked
  above. Awaiting Roman's explicit "go" before touching code/assets.

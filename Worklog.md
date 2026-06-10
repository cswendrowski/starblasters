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

## REMAINING WORK (not started / partial) — handoff
Completed this session: P0 import, A audio, B weapons, D phase/hyper, E outpost, F+G music/HUD,
H-Omni + off-screen-hit-guard, J zealot-VFX, K enemy-bench-recycle-tags, L manage-ship-modes, M onboarding.

**Still open (large / playtest-dependent — recommend an ATTENDED session):**
1. **Recycler "full send" (cluster I core)** — NOT started. This is the highest-risk item: its regression
   surface is the WHOLE roster and the design doc (`docs/recycling_system_pillar2_2026-06-04.md`) calls for
   playtest-only verification, which I can't do unattended. Build order per the doc + TODO:
   (a) **RecycleTuner** dev scene (prereq — 3+ live knobs: recycle budget / fly-back scale / tint / hold;
   JSON persist + Copy-GDScript per the tuner contract; register in `dev_menu.gd`).
   (b) **`RecycleController`** preload-const helper owning offscreen→recycle decisioning + ONE timing budget
   (replaces scattered 0.4–0.9 holds + fixed 1.8s tween); fly-back ghost reuses `MidDepthPresentation`.
   `enemy_base._offscreen_cleanup_check` + `enemy_core._start_cycle` delegate to it; preserve
   `is_recycling()` / `recycle_passes` / `fleeing`.
   (c) Formation-aware re-entry via the conductor; (d) merge missile-cruiser bespoke recycle + migrate the
   roster. **Lead recommendation:** build (a)+(b) additively (no behavior change until wired), then do the
   roster migration WITH Roman able to playtest — a blind roster-wide migration risks breaking every enemy's
   offscreen behavior with no way to catch it before you return. (K already added bench recycle-tagging knobs.)
2. **wreck_layer + EM Torpedo (cluster C)** — NOT started. Additive (low regression risk) but visually
   complex + needs your eyeball. wreck_layer = near-parallax-depth layer enemies "fall" into on death (testbed
   = EM Torpedo). EM Torpedo (secondary/HARDPOINT_WING): rocket flies 2s → blue-yellow lightning burst,
   multi-hit, strips/ignores shields, detonates missiles/rockets; alt kill: 25% explode / 75% inert drift
   (rand rotation) toward bottom + player-style smoke into the wreck_layer. Reuse: `base_missile.gd`, the
   secondary SALVO/BURST modes, `damage_smoke_trail`, the parallax near-layer for depth/grade.
3. **Hangar rebuild (cluster N / DEV)** — NOT started. "Muzzle flashes green, bullets missing — deep dive +
   rebuild the SubViewport." A prior session's parent-routing fix was insufficient. Needs a real SubViewport
   rebuild; I have prior context on `hangar.gd` (HD scope + `_world` SubViewport + `bullet_parent` routing).
4. **Lane Hook + Supremacy Push (cluster H)** — need your repro (see Needs-Roman) to fix safely.
5. **Core renderer pivot (Forward+/Windows)** — HELD by your decision (attended session).

## Needs-Roman (eyeball / playtest / decisions) — running
**Polish (cluster J/K/L/M) — eyeball:**
- **J Zealot ball-explosion:** zealot deaths play the "ball" explosion when NO firecore drops, "default"
  when one does; firecore hazard uses ball. ("ball" currently aliases `explosion_small_circle` — point me
  at a distinct ball-explosion scene if you have one.) Gated on a per-scene `may_drop_firecore` meta so
  non-zealot enemies are untouched. Eyeball the explosion read + confirm the right zealots are tagged.
- **K Enemy-Bench recycle tags:** new bench controls (can-recycle / passes / recycle-vs-flee chance) — note
  it may have added `recycle_chance`/`flee_chance` fields to enemy_core; confirm defaults preserve behavior.
- **L Manage-Ship shift modes:** SHIFT_MODE slot now shown + equippable from owned kit. Eyeball the layout.
- **M Onboarding:** refreshed copy (economy, outpost hub, shift modes, Q/C/X, parts/Mk). Read-through review.

**Patterns (cluster H) — 1 fixed, 2 need your repro:**
- **Omni movement — FIXED.** Now bounds its bottom to the no-fly line (`Zones.DEPARTURE_START` = 195,
  the engagement band's departure edge) instead of the screen bottom (270), so it stays in the firing
  zone and never sinks into the dead space below the player. Eyeball that it harasses well within the band.
- **Lane Hook — needs your repro.** "lane_hook" = the DIVE_RETURN shape; I verified its exit IS configured
  correctly (sets `OffscreenMode.FREE_ANY_EDGE`, dives to band-midpoint, smooth U-turn, climbs out the TOP,
  frees). I couldn't reproduce a failure in code. **What's the symptom** — stalls mid-climb? exits the wrong
  edge? recycles instead of leaving? — and I'll fix it precisely (didn't want to blind-edit working code).
- **Supremacy Push globbing — needs your repro / a steer.** The director HAS lane-spread (`_pick_lane`) +
  crosser height-stagger (`_crosser_travel_y`), but the push "anchor" heavy enemies appear to bypass them.
  The proper fix (route push descenders through one-per-lane + crossers through the latitude stagger) is in
  complex shared director code where a blind change risks roster-wide regressions. Confirm it's the
  side_traverse (crossing) variant globbing vs the descenders, and I'll route just those through the spread.

**Music + HUD (cluster F+G):**
- **Music ramp** logic tested (PASS): I1 open → I2 first wave → Main past wave 4 → ramp down on clear;
  +1 permanent step per boss (via Run.bosses_defeated floor). Eyeball/ear: confirm it ramps in real
  combat (the prompt-crossfade is new) and the per-boss escalation feels right.
- **HUD weapon light** flash-on-regen / darken-on-empty — eyeball (logic sound, can't see it).
- **HUD ∞ glyph fix:** the missing-char "out of ammo" box was the ∞ infinity symbol (not in the pixel
  font). Infinite ammo now shows **blank**. Tell me if you want an explicit infinite indicator (I'd add
  a small sprite glyph or a font with ∞).

**Outpost (cluster E) — eyeball card layout/copy:** All 7 done (subagent + my safeguard fix). Eyeball:
the dynamic stat line format on cards (computed from part curves, e.g. "dmg 5 · 1.5/s"), the rarity-
colored name + type subtitle ("Blaster"/"Primary Weapon"/"Secondary Weapon"/"Super"/"Mode"), and the
"Defeat boss to restock." header label. Logic (own-better roll filter, dup-equipped move-to-hold) is
unit-tested.

**Phase / Hyper (cluster D) — eyeball the visuals:**
- **Phase** now: 3s, invuln, offense locked, **absorbs enemy bullets → +1 shield each** (mechanics
  tested PASS), blue aura + **fading blue after-image ghosts** (new). Eyeball the after-image look
  (interval 0.06s / fade 0.34s — tunable). Note: take_damage treats ALL incoming damage while phased
  as absorption (+1 shield), not just bullets — fine thematically, flag if you want bullets-only.
- **Hyper**: **pulsing orange outline** that speeds up as the bar empties (SLOW 2Hz → FAST 9Hz).
  The orange outline is built from the ship's frame at hyper-start and doesn't rebuild on banking, so
  its silhouette can be slightly stale mid-bank — minor; tell me if it reads wrong and I'll rebuild it
  per-frame like the black outline.

**New weapons (cluster B) — playtest the FEEL (can't verify unattended):**
- **Autocannon** (replaces Machinegun in the pool): 1.5s spin-up (start sound) before it fires, stop
  sound on release; re-press = full re-spin. `AC_SPIN_TIME` in player.gd is the tunable. Same bullets/
  damage/scaling/orange-muzzle/shell as the old MG. _Edge: if ammo hits 0 while held, the stop sound
  waits until you release — minor._
- **Minigun** (new): hitscan, ~20/s (rotary rate), hits the FIRST enemy in a **±6px column** straight up,
  flat 5 dmg, MG muzzle/shell + minigun_tracer. **Two tuning items I flagged (not blind-tweaked):**
  (1) the tracer only draws when it HITS something — you may want the bullet-stream tracer to always
  show while firing; (2) the ±6px column tests enemy *center* (ignores enemy width) so it can feel like
  it misses wide enemies — widening to `±6 + enemy_half_width` would help. Say the word and I'll adjust.
- Machinegun Cannon is **retired from the roll/shop pool** (its assets remain for Autocannon/Minigun).

**Weapons (cluster B) — cannon/rotary:**
- **Enemy cannon "glow on entire sprite" — needs your eyeball.** Hard numbers from `test_cannon_render`:
  both cannon bullets (burst_round + heavy_slug) now ANIMATE (playing=true), slice to 16×16, and the
  ShaderGlow node's texture is **16×16 = one frame, NOT the 32px whole sheet**. So in code the glow IS
  the chosen frame. If you still see "whole sprite," it's likely the diffuse HALO (HALO_PX=7 → ~30px
  glow around a 16px bullet, ~2× sprite size) reading as oversized — easy to shrink `HALO_PX` or add a
  per-bullet `halo_mult` if you confirm. The "not animated / random frame" symptoms are fixed.
- **Rotary Mk.5+** swaps to the Auto Laser bolt sprite — verify the visual at Mk.5 in-game.

**Audio (cluster A) — listen-test:**
- Explosion distance bands are tunable consts in `explosion_sfx.gd`: `NEAR_DIST=62`, `FAR_DIST=168` px
  (close/medium/distant), plus per-band volume. Tune by ear.
- **Silenced on purpose** (flag if you want them back): boot warmup blast, smart-bomb per-kill
  mini-explosions (smart bomb has its own detonation cue), and bomblet swarm pops (4–8 at once would
  wall up close booms). Bomblets currently make NO explosion sound — say if they need a quiet pop.
- Outpost: shield/primary-ammo/secondary-ammo/super **refills reuse the `repair` cue** as a generic
  "service rendered" sound (only equip/unequip/upgrade/repair clips exist). Free shield refill is silent.
- `mine_sfx.gd` is now a **no-op** (old SFX_explosion1.wav retired); the redundant `MineSfx.play_at`
  call sites (mine/mine_shielded/mine_smart/gravity_mine/firecore/bomblet) are dead — sweep later.
- "Incoming weapon sounds": interpreted as the enemy `enemy_blaster_*` / `enemy_mg_*` ogg (enemy fire,
  wired via `enemy_sfx`). If you meant a distinct player "incoming" alert set, point me at the files.

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
- 2026-06-10 — **wreck_layer + EM Torpedo BUILT (test-gated)** (`9d99405`, local on main, unpushed).
  World-space wreck layer (graded to the near parallax band, created empty every combat) + a new
  HARDPOINT_WING secondary, the EM Torpedo: large dumb-fire rocket → blue-yellow chain-lightning
  burst that strips/ignores shields, chain-detonates enemy ordnance, and routes 75% of kills to
  inert wreck-drift (gravity fall + slight tumble + world-space smoke), 25% normal explosion.
  Shipped behind **Test Combat → "EM Torpedo + Wreck Test"** (NOT in the shop pool). Fire with C.
  Verified headless (new test_em_torpedo + firecore/fire-primary regressions). **NEEDS ROMAN
  EYEBALL:** lightning burst look, inert-drift fall/tumble feel, wreck-layer depth/grading vs the
  near parallax, and the burst point (detonate_y=50 → bursts near the top among the front line).
  **Tunables:** exports on `player_em_torpedo.tscn` (burst_radius 72, burst_max_targets 8, detonate_y
  50, fuse 2.0) + consts in `wreck_drift.gd` (fall/gravity/spin/lifetime) and `em_burst_fx.gd` (arc
  colors). Built directly on main (HEAD was on main post-renderer-merge) — say if you want it branched.
- 2026-06-10 — **MERGED + PUSHED**: `worklist-2026-06-10` merged into main (`0927c83`), both pushed
  to origin. **Renderer pivot built** on branch `renderer-pivot` (`8f7a941`): forward_plus,
  Windows-only publish pipeline (preset → `../Starblaster_win/Starblaster.exe`, butler channel
  `:windows`), CLAUDE.md updated, bogus custom-template field cleared. Verified: gate 266/266, boot
  clean, LOCAL test export produced a working 152MB exe. NOT pushed to itch. **Roman: restart the
  editor** (renderer changes need a relaunch) and eyeball — glow first (main.tscn Environment
  intensity 0.6 was tuned under GL; Forward+ usually renders glow stronger), then particles,
  additive effects, outlines, and a full combat. Merge `renderer-pivot` when it looks right.
- 2026-06-10 — **Playtest round 2 fixes** (`15b60b0`/`57c00e2`/`51d4313`):
  (1) **Frozen/unkillable firecores** — task J's `var scene :=` off an untyped load() killed the
  whole firecore script at runtime. Fixed; `test_firecore_repro` proves both spawn paths move + die.
  **The bigger find:** the parse gate was a FALSE PASS (win64 GUI exe drops console output under
  redirection + load() returns non-null for broken scripts) — hardened to a fail-closed result-file
  VERDICT + can_instantiate(). The strict gate then exposed 2 more hidden compile failures (bare
  `Run.` identifiers, mine) — fixed to the /root convention; also patched 4 stale ogg UIDs.
  (2) **Outpost dupes at different marks** — dedup key was slot:mk:name; now item NAME alone.
  (3) **Sector modifiers PULLED** — `Run.SECTOR_MODIFIERS_ENABLED = false` kill-switch gates
  generation (rng-stream-stable, so re-enabling won't reshuffle maps) AND node-entry application
  (stale-save-proof). Vocabulary + effect wiring kept for the re-eval. **FLAGGED FOR RE-EVAL /
  REIMPLEMENT LATER** per Roman. `test_modifiers_off` PASS.
- 2026-06-10 — **Playtest hotfixes** (`1c229a4`, from Roman's first hands-on): (1) primary fire was
  broken for every style except Autocannon/Minigun — the weapons rework folded the per-frame
  fire_primary() into the style branches; restored the unconditional call (fire_primary self-gates),
  spin-up stays the only suppression, and added `test_fire_primary` (boots combat, holds shoot,
  asserts the blaster spawns bullets) as a permanent guard. (2) "old explosion sounds on death" =
  the legacy per-scene `$EnemyDie` clip, still played by enemy_base/boss_base over the new distance
  system — both play sites retired; deaths now sound only via Close/Medium/Distant. The inert
  EnemyDie nodes remain in 54 enemy scenes — **cleanup candidate**.
- 2026-06-10 — **Post-session code review (7 finder angles × verify) + fixes** (`bcd6e18`/`f874d74`/`2337c87`).
  7 confirmed correctness bugs in the overnight work, all fixed: (1) Autocannon per-shot SFX never
  played (gate excluded the MG family wholesale); (2) zealot firecore routing missed the faction-
  overlay drop path (untagged emitter → wrong explosion; detection now keys off the tagged component,
  scene meta removed); (3) Autocannon spin-state leaked across Q-swaps (reset now in
  _reapply_active_cannon + release); (4) minigun hitscan targeted immune recycling/off-screen enemies
  (now skipped, + hot-path cleanup: preloads, single-pass select, shared ghost material); (5) outpost
  CANNON roll filter ignored the hold (weapon_storage now scanned); (6) onboarding falsely claimed
  bounty persists across runs (rewritten); (7) two tools null-dereffed on the retired _make_machinegun
  (→ _make_minigun; armory blurbs re-keyed; stale 1.5s phase assertion → 3.0s). test_shift_mode_phase2
  now runs ALL PASS (was crashing). **Deferred cleanups (flagged, not fixed — refactor-class):**
  outpost `_stats_display_for_part` duplicates hangar `_stats_for_part` (extract one shared helper);
  player.gd is accreting per-weapon firing/audio state machines (5 now — consider a per-style handler
  the Part owns); outpost part identity rides display_name string compares (consider an is_permanent
  flag). Verified-clean during review: music ramp, smart-bomb audio (no doubling), safeguard pool
  edges, outline name-collision.
- 2026-06-10 — **Cluster F+G Music+HUD DONE** (`3760e89`). Music ramp rewired (prompt crossfade + per-boss floor, test PASS); HUD weapon-light flash/darken + ∞-glyph fix. See Needs-Roman.
- 2026-06-10 — **Cluster E Outpost UX DONE** (`e224405` subagent + `be986fa` my safeguard-bug fix).
  7 tasks: Blaster/Primary disambiguation, rarity-colored name, type subtitle (drop "Tier"), one-of-each
  move-to-hold safeguard, "Defeat boss to restock" label, own-better no-dupe roll filter, dynamic stat
  cards. Caught + fixed a copy-not-move inventory bug in the safeguard. Tests PASS.
- 2026-06-10 — **Cluster D Phase/Hyper DONE** (`77d4356`). Phase: 3s + bullet-absorb→shield +
  after-images; Hyper: pulsing orange outline (outline_fx now supports a colour). Mechanics tested
  (`test_phase_hyper` PASS); visuals → Needs-Roman.
- 2026-06-10 — **Cluster B weapons DONE**. Rotary Mk.5+ bolt swap + gunship heavy_slug frame_count fix
  (`7eb22da`, me). Minigun (hitscan) + Autocannon (spin-up, replaces MG) built by code-editor subagent
  (`4cf8ef7`/`d2fc258`/`4d6e4b3`/`44ec2af`), reviewed + verified: parse-clean, boot exit 0, all weapon
  tests PASS. Firing-state review confirmed spin-up gate + hitscan are structurally correct. Feel/timing
  + the two minigun tuning items in Needs-Roman await playtest.
- 2026-06-10 — **Cluster A audio rewire DONE** (`09229a7`). New SFX wired: Auto Laser + Spread Cannon
  fire sounds; smart-bomb sweetener; outpost equip/unequip/upgrade/repair (new `outpost_sfx.gd`);
  distance-based explosion system (new `explosion_sfx.gd`, Close/Medium/Distant → `ExplosionFx`).
  Retired SFX_explosion1.wav. `test_audio_sfx` PASS. See Needs-Roman for listen-test tuning.
  _(Note for self: commit multi-line messages via Bash `git commit -F -` heredoc — PowerShell mangles them.)_
- 2026-06-10 — **P0 import DONE** (`3272c0e`, branch `worklist-2026-06-10`). Renamed 80 explosion clips
  (vendor prefix stripped), imported all new `.ogg` + `minigun_tracer.png`, gitignored `desktop.ini`.
  Un-broke the build: enemy fire SFX `.wav`→`.ogg`; retired dead `PULSE` pool + `WAVE_BIG` (wave gun
  drops the Mk.5 *audio* swap, keeps the projectile swap). parse_check clean, boot exit 0.
- 2026-06-10: Reviewed Worklist + TODO + docs + new-asset set. Authored plan. Decisions: renderer **held**;
  Autocannon **replaces** Machinegun; recycler **full send**; **proposed sequence** confirmed. Sequence locked
  above. Awaiting Roman's explicit "go" before touching code/assets.

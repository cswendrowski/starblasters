# Lead Session Report

**Started:** 2026-06-08
**Lead model:** Opus 4.8
**Scope:** Everything in `TODO.md` EXCEPT the combat arena. The parallel session ("combat level
playable area") owns **Enemies + patterns/director/waves** and **Bullets/weapons library** — I
stay clear of those. My buckets:

- **Sector map** — randomization, boss-ring progress, retire old map, signal-event randomization
- **Background / backdrop** — per-row varied planets, debris sprite, wrap-desync, dead preloads
- **Audio** — music cycling, intensity ramp, same-frame sound overrun
- **Economy / balance** — Mk-scaling, bounty share, outpost density, hull formula, resale, POI mults
- **Cleanup / dead-code** — retire prototype shaders, orphan scenes, dev-tool removal, GDScript warnings
- **Isolated player/boss items** — sprite rotation, supers no-op, enrage VFX, conflict_tags (only where
  they don't touch waves/director)

---

## Decisions I need from you

1. **`main.gd:802` old-sector-map round-trip** — the asteroid-hazard exit loads the raw
   `sector_map_v3.tscn` instead of the HD-hosted version (the "old UI" you flagged). The fix is a
   one-line route change, but `main.gd` is the *other* session's territory (combat controller). Want
   me to (a) make the one-liner now and risk a trivial conflict, (b) hand it to the other session, or
   (c) wait until they're done?
2. **Legacy `scenes/sector_map.tscn` deletion** — still referenced by `feature_showcase.gd` (a live
   dev capture target) + `tools/parse_check.ps1`. Deleting it means dropping two showcase panels.
   Worth it, or leave the V1 scene as a harmless dev-only reference? (Low priority.)
3. **Player supers — two findings that are YOUR call, not bugs:**
   - **"Focus super" doesn't exist** — there's no Focus super module; "Focus" is the held-Shift
     focus *mode*. The TODO line conflates them. Do you want a Focus *super* built, or should I just
     correct the TODO?
   - **Phase Shift "feels like a no-op"** — its `activate()` is wired correctly and identical to the
     working Smart Bomb path; it's just *invisible by design* (pure defensive: i-frames + bullet
     clear, no enemy damage, no fire boost). Triggered with no incoming hit it shows only a brief
     flash. Want me to add a stronger activation tell (screen-edge phase shimmer / tint while
     invuln) so it reads as "working"? That's a VFX add, your call on whether it's worth it.
   - **Sprite banking (Bug C) is already live** (`player.gd:569-578`, 3-frame strip swap on
     horizontal input). If it's not visibly banking in-game, the regression is in the *art* (the 3
     frames may be visually identical), not the code. Can you confirm the `Ship` sprite strip has
     distinct left/forward/right frames?

4. **Economy balance calls (concrete proposals from the economy-sim pass — pick numbers):**
   - **Several doc items are STALE / already shipped** — no action needed: hull Mk-9 formula (now
     `2 + min(hull_mk,8)`, ratio 3.3×, in-band — the doc's `10+2*hull_mk` would make Mk9 = 28 pips,
     do NOT apply); Smart-Bomb refill now costs 120 (not free); `wanted` +20% bounty is wired;
     boss-clear Mk-cap bump shipped. I'll mark these resolved in TODO.
   - **#2 Mk power asymmetry** — weapons scale ~9× vs hull ~3.3×/shield 2.5×. The real lever is the
     per-cannon additive `base_damage + (mk-1)*per_mark` path, NOT `mark_multiplier()` (they're
     separate systems — the doc conflates them). Proposal: re-key cannons to ~3× ceiling
     (e.g. Energy Blaster base 6, +1.5/mk → Mk1≈6, Mk9≈18). **Want this flattening pass?** It's a
     feel-defining change — needs your sign-off before I hand it to part-author.
   - **#3 Boss bounty share = 72%** — +20 combat / +25 hazard clear bonuses alone only move it to
     ~68%. To hit the ~30% target you'd need a boss nerf (~40%, e.g. Conductor 600→360) **plus** the
     clear bonuses → ~55-60% share. **Decision: nerf bosses, add clear bonuses, or both?** (The clear
     bonus hooks are in `main.gd` — other session's file — so I'd coordinate that part.)
   - **#4 Asteroid/hazard 0-bounty** — normal asteroid fields pay 0. Proposal: flat +25 hazard-clear
     bonus (shares the `main.gd` hook with #3). Approve the +25?
   - **#7 Outpost density** — currently hard-clamped to [2,4]/sector (0 and 1 impossible). For your
     "rarely 1, super-rarely 0" tail I'd drop `OUTPOST_MIN_PER_SECTOR` to 0 and add a probabilistic
     floor targeting ~{0:3%, 1:12%, 2:45%, 3:28%, 4:12%}. Approve that curve (or give me your own)?
   - **#9 Mk-cap split** — cannons + upgrades share `min(9, sector+3+bosses)`. Proposal: upgrades
     `min(9, 2+sector*2)`, cannons `min(9, sector*3)` so Mk9 cannons become the late-run identity
     moment. Approve the split?
   - **#6 `dangerous` bounty multiplier** — `wanted` is wired (+20%); `dangerous` only does ×2 damage,
     no bounty reward. One-case add in `director.gd` (other session's file) — what % (+50%)? I'll
     coordinate the hook with them.

   I've already shipped the one unambiguous economy **bug**: resale arbitrage (see log).

## Testing I need you to do

These changes are verified parse-clean + headless-boot-clean, but the following are visual/feel and
need your eyeball in-game (I can't exercise sector-map transitions or audio ramps headless):

1. **Music cycling** — play a long level (≥5 waves) to the end; confirm music never falls silent and
   the **Main theme kicks in on the last 2 waves**. Also pause mid-track (freeze) and confirm audio
   keeps playing.
2. **Smart-bomb loudness** — trigger a smart bomb into a dense wave; the mass-death SFX should no
   longer blow out (attenuated past 4 simultaneous voices). Tell me if it now feels *too* quiet.
3. **Sector map** — across a few runs: planets/decoration should **vary run-to-run**; nodes should
   **not cluster left**; the **boss ring should show a partial fill** as you complete a row's nodes.
   Critical: confirm the planet shown on a map node still **matches** the planet in that node's combat.
4. **Signal events** — different signal nodes in one run should now roll **different outcomes** (not
   all identical).

---

## Chronological log

### 2026-06-08 — Intake
- Read `TODO.md`, confirmed scope split with the other session (it owns enemies/patterns/waves +
  bullets/weapons). Taking the complement.
- Uncommitted `tools/_*_result.txt` files are just headless-test PASS markers (cruft) — will fold
  into a cleanup commit, not touch the other session's territory.
- Fanning out read-only explorers to build precise, file:line work lists per bucket before editing.

### 2026-06-08 — Work lists built (4 explorers), dispatching implementation
Explorers returned precise file:line maps. Dispatching 4 parallel implementation agents on
**disjoint file sets** (so they can't collide with each other or the other session):

- **A. Audio** (`scripts/music_manager.gd`, `scripts/effects/sfx.gd`)
  - Music keeps cycling (harden the `finished` safety-net so it re-arms even while crossfading/frozen)
  - Intensity ramp: Main theme on final 2 waves when level has ≥5 waves (pipe already exists in main.gd)
  - Same-frame SFX overrun: per-frame voice cap / volume-scale at the `Sfx.play_one_shot` chokepoint
- **B. Sector map** (`scripts/sector_map_v3.gd`, `scripts/sector_map_hd.gd`, `scripts/signal_event.gd`)
  - Planet-kit variety: mix `run_seed` into per-POI deco seed at ALL sites (parity-critical)
  - Node placement: stop the fixed-marker override clustering POIs left; trust randomized cache pos
  - Boss-ring progress: HD rehost draws partial arc from POI completion instead of a solid full ring
  - Signal events: re-seed off `current_node_id` (the `visited_nodes` counter is dead → always 0)
- **C. Backdrop** (`scripts/parallax/backdrop_coordinator.gd`, `galaxy_backdrop_v3.gd`, `galaxy_backdrop.gd`)
  - Live planet variety: fold `poi.id` into the coordinator RNG seed
  - Remove dead `NEBULA_SHADER`/`TINT_SHADER` consts (V3) + unused `STARSTUFF_SHADER` const (V1);
    delete the two now-orphaned shaders
- **D. Cleanup deletes** (zero-ref shaders, capture_shadow prototype cluster, `tools/_*_result.txt`)

**Deferred (shared-file / coordinate with other session):**
- `main.gd:802` asteroid-hazard route still loads raw `sector_map_v3.tscn` instead of the HD host
  (the "old sector map" round-trip). One-line fix but `main.gd` is the other session's territory.
- Deleting legacy `scenes/sector_map.tscn` (needs `feature_showcase.gd` + `parse_check.ps1` surgery).
- `tools/_*_result.txt` are also untracked cruft with no `.gitignore` rule (will add a rule).

### 2026-06-08 — Batch 1 committed (`c36a044`)
All four agents landed; parse_check PASS; headless boot clean (only Godot's benign "2 resources
still in use at exit" leak warning, exit 0). Reviewed the two parity-critical diffs (sector-map seed
lockstep, music finished-handler) by hand — sound. Committed to `main` (NOT branched: branching the
shared working tree would yank the other session's context). Staged my files explicitly to exclude
the other session's in-progress `scripts/enemies/patterns/lane_charge.gd.uid`.

**Landed:** audio (cycling/ramp/voice-cap), sector-map (variety/node-placement/boss-ring/signal-seed),
backdrop node-variety seed, dead-code cull (8 shaders + capture_shadow cluster + 24 result dumps).

**Next:** economy audit + supers-no-op root cause (parallel, read-first), then implement safe fixes.

### 2026-06-08 — Batch 2: player/economy safe fixes (parse-clean, pending commit)
Ran the economy-sim audit + a supers-no-op root-cause pass. Implemented only the unambiguous,
in-my-territory fixes; everything requiring a designer number is in the Decisions section above.
- **Drone Swarm emit point** (`scripts/parts/drone_swarm.gd`) — drones now spawn at the player
  center instead of a 16px ring; `angle_seed` still seeds the boids fan-out.
- **Resale arbitrage** (`scripts/signal_event.gd` + `scripts/outpost.gd`) — signal-event sell-back
  was 20% while the outpost pays 10% (the 2026-06-01 cannon-price bump dropped outpost to 0.1 but
  missed the signal site). Realigned signal to 0.1 so neither venue is the better dump spot; fixed
  the stale "20%" comment in outpost too.
- **Supers Bug A + Bug C** — not code bugs (see Decisions #3); left as designer calls.

Testing for you: confirm Drone Swarm drones now emerge from the ship center on deploy.

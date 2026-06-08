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

## ⭐ Isolated merge candidate — ready for you (2026-06-08)

Per your call, my 4 commits are cherry-picked onto a **clean branch off `origin/main`**, isolated from
the other session's 7 commits. Built in a **separate git worktree** so it didn't disturb the shared
tree / the live other session.

- **Worktree:** `../sb-noncombat-wt`  (sibling of the repo, i.e. `E:\Godot-Projects\sb-noncombat-wt`)
- **Branch:** `m6c-noncombat-polish` (= `origin/main` + my 4 commits, **conflict-free**, upstream
  unset so a push can't accidentally target `main`)
- **Commits:** `c1b74e7` audio/sector-map/backdrop/dead-code · `71127d6` economy+drone · `50b7b63`
  backlog annotate · `70588f2` docs roll-in
- **Verified:** content-identical to my shared-branch work (the only diff vs the shared tip is the
  *absence* of the other session's files); **headless boot exit 0, zero script/parse errors** on the
  clean base (after a one-time asset import — a fresh worktree has no `.godot/imported/` cache).

**When you've playtested the eyeball items and want it in `main`:**
```
# from the main repo (E:\Godot-Projects\starblasters), when YOU'RE on/ready to update main:
git merge --ff-only m6c-noncombat-polish      # fast-forwards main onto my 4 commits
# then push main yourself, and clean up:
git worktree remove ../sb-noncombat-wt
git branch -d m6c-noncombat-polish
```
(Or push the branch as its own remote: `git push -u origin m6c-noncombat-polish` — won't touch main.)
I did **not** push anything. The other session's 7 commits stay on `m6c-polish-r2`, untouched.

### 2026-06-08 — Smart Bomb rework (`f38653e`)
Reworked Smart Bomb from an instant screen-wide damage loop into a released **traveling shockwave**
per your spec: player white-flash → expanding radial ring from the player at 8 px/f (480 px/s) that
sweeps fully off-screen. New `scripts/projectiles/smart_bomb_shockwave.gd` + reworked
`smart_bomb.gd activate()`. Ignores shields (zeros simple-shield + ShieldComponent charges then
`take_hit`); one-shots any large non-tough enemy (16 HP) or smaller incl. shielded chaff; tough/huge/
bosses survive; bosses bitten through the normal path so phase gates hold. Death-bomb auto-fire
preserved (`_invuln_t`). **Visual confirmed in-game by you.**

- Damage tuning (18 + 5/Mk, kill-≤16hp, shield-ignore) is mine — visual's confirmed, but if you want,
  confirm the **kill thresholds feel right in play** (does it spare tough-large as intended, clear
  shielded chaff, etc.). Easy to retune the number.
- This is a **5th commit on `m6c-polish-r2` not yet in the isolated `m6c-noncombat-polish` branch**
  (which I froze at the docs commit). Say the word and I'll cherry-pick it into that branch too.
- Your `tools/capture_smart_bomb.{gd,ps1}` are still untracked — left them for you to keep or commit.

### 2026-06-08 — Smart Bomb: crystal "ignores bomb" → shield-strip bug (`bf462c6`)
Roman: the crystal ignores the smart bomb. Root-caused via a headless behavioral test (booted real
project, spawned crystal + control + shielded enemy, fired the wave):
- The crystal at 8 HP **dies** fine — no crystal-specific immunity. Real cause: my shockwave's
  shield-strip zeroed `_charges` on `enemy.components` (the **authored template**), but `enemy_base`
  duplicates that into a per-instance **runtime** array `_components` in `_ready`, and the damage
  pipeline reads `_components`. So the live `ShieldComponent` kept its charges and absorbed the bomb.
- **Class of affected enemies** (the "find others with the same issue"): everything with a
  `ShieldComponent` — corporate-faction units, bulwark, sapper, shielded bosses, and the crystal
  (it's `universal:true`, so it spawns in corporate levels and gets the corporate shield overlay).
  Simple per-pip chaff shields (`enemy_base.shield`) were already stripped; only the component shield
  was missed.
- **Fix** (contained to my `smart_bomb_shockwave.gd`): zero `_charges` on the runtime `_components`.
  Verified headless — a 3-charge shielded enemy now dies to one pass; unshielded enemies still die.
- **Minor note (no action):** privateer-overlaid enemies are 2× HP, so a privateer large-non-tough
  (32 HP) survives the 18-dmg wave — arguably correct since the overlay makes it "tough." If you want
  the wave to ignore the privateer HP buff too, that's a small tuning change; say the word.

### 2026-06-08 — Shield unification (foundation + spec) (`b5c9adf`)
Roman: unify the enemy shield systems. Investigation found **four** split systems (simple
`max_shield`, ShieldComponent, bespoke bulwark/bomber regen, one-off mine/Aegis). The three you named
were split: sector-modifier + roster "shielded" tag → **simple** shield; corporate faction →
**ShieldComponent** (they can even stack on one enemy). Decisions: **spec it, combat session builds**
the cross-file migration; **chaff shields don't regen**.
- **Built (cleanly mine, verified headless):** `ShieldComponent` gains CHARGE (per-hit; `regen_interval
  <= 0` = no regen) + POOL (the sapper's banked **damage** pool — absorbs an amount, grows via
  `bank()`, never regens) modes, backward-compatible. Smart bomb is POOL-aware: strips CHARGE shields
  (ignore-shields), but chews the sapper's POOL and bypasses its `take_hit` redirect — so a well-fed
  sapper (pool ≥ 18) survives, a starved one dies. Test: fed sapper(22) lives, starved(10/8hp) dies,
  3-charge shield stripped+dies.
- **Handed to combat session** (`docs/shield_unification_2026-06-08.md`): rewire `director.gd` spawn
  paths + retire `enemy_base` simple shield + migrate bulwark/bomber/mine/sapper onto ShieldComponent.
  Their files (enemy_base/director/roster/enemy scripts), so it's their build per the spec.

### 2026-06-08 — Tackled items 1–4 (`1c86ba2`, `85bf63c`)
- **#4 Run-history index** (`1c86ba2`) — dated past-runs list off the main menu, using stats `Run`
  already tracks (no new instrumentation). JSON persistence in `run_state` (mirrors codex channel),
  death-flow record hook in `run_summary` (guarded vs showcase captures), `run_history.gd`/`.tscn`
  list scene, main-menu button. Verified headless (record→load round-trips; scene boots clean).
- **#1 Weapon-Part fixes** (`85bf63c`) — `drone_bits` apply/unapply made symmetric. The
  basic_blaster/spread_cannon "asymmetry" was STALE (the `weapon_part` base already
  snapshots/restores `weapon_style`+`fire_sfx_kind`) — no bug.
- **#3 Dead `visited_nodes` read** (`85bf63c`) — removed from `galaxy_backdrop.gd` (always 0); seed
  formula arithmetically identical.
- **#2 Economy doc re-audit** (`85bf63c`) — status note flagging the items that have since shipped so
  triage doesn't re-litigate them.

### 2026-06-08 — Codex rebuild + Credits + a git mishap to flag
- **Codex rebuilt** (faction-organized, game-data-driven). Left nav = 4 factions + Bosses +
  Starblaster (placeholder). Faction → codex entry + roster (discovered named, rest "???", X/Y
  count). Enemy → slowly-rotating sprite (hull + glowmap + dropshadow, NO other shaders) + name +
  classification + blurb. Pulls 100% from game data (Factions/EnemyStrings/EnemyRoster/Run/scene
  sprites). New `codex_strings.gd` holds faction display names + faction/Starblaster codex
  PLACEHOLDERS for you to fill. Repointed `shipyard.gd` off the removed `EnemyCodex.ENTRIES`.
- **Credits screen** built + wired (`_on_credits` was an empty stub): Design — Roman & Cody;
  Testers — Stacey, Cody, Nath, Pao, Kyle, Doug, Ellen.
- Verified headless: codex/credits/menu boot clean; faction grouping (7/11/10/10), 7 bosses,
  enemy + Starblaster previews build, classification reads e.g. "Crimson Supremacy / Common / Small".
- **NOTE — enemy names/blurbs are placeholders** in `enemy_strings.gd` (mostly "TBD" + scene-stem
  names like "p_s_green"). The codex pulls those verbatim per your "from the game" directive — fill
  `enemy_strings.gd` (and the faction/Starblaster text in `codex_strings.gd`) and the codex updates
  automatically. **Needs your eyeball in-game** (rotation feel, layout, glow read).

## ⚠️ Decisions I need from you

**Git: a commit got mislabeled (my mistake).** My first run-history commit's `git add` aborted on a
non-existent `.uid` pathspec (silenced by `2>/dev/null`), so the commit captured the **other session's
already-staged bullet renames** under my "Run history" message (`1c86ba2`). My run-history files were
never committed then — I've now committed them properly (new commit). The other session has since built
3 more commits on top of `1c86ba2`, so:
- **Recommendation: leave `1c86ba2` as-is.** The bullet renames ARE correctly committed (just under a
  wrong message); rewriting shared-branch history with the other session active + commits stacked on
  top would be far more disruptive than a cosmetically-wrong message. Want me to leave it (rec) or do
  something? I've switched to pathspec-limited commits (`git commit -- <paths>`) so it can't recur.

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

5. **Moon/planet drift on long combats (>~226s)** — the TODO calls this a "desync," but in the live
   V4 backdrop the planet and its moons are both children of `LayerPlanet` sharing one `offset.y`
   scroll, so they *can't* desync. The real behavior: the whole planet+moons group drifts off the
   bottom and never wraps, emptying the sky on long fights (now more common with ≥5-wave levels).
   **Your call:** (a) wrap/re-enter from top, (b) hold at the bottom edge, or (c) leave as-is
   (you've "passed" the planet). I didn't guess — tell me which and I'll implement.

### Items I'm treating as the OTHER session's / blocked (not touching):
- `director.gd`, `main.gd`, `wave_generator.gd`, `enemy_*`, bosses, `projectiles/`, enemy
  shoot-patterns — the combat-arena + bullets/weapons scope. Economy hooks that live in `main.gd`
  (combat/hazard clear bonus) and `director.gd` (`dangerous` bounty) I'll hand over or coordinate.
- **385 editor GDScript warnings** — I can't see the editor's analyzer output headless. If you paste
  the recurring list from the Output/Debugger panel, I'll fix per-site or demote noise categories in
  `project.godot [debug] gdscript/warnings`.
- **Tuner-driven items** (dynamic animated nebula, V3 parallax color sliders + blend-mode dropdown)
  — these want the parallax tuner + your eye per the human-iterated workflow; ready when you are.

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

### 2026-06-08 — Batch 2 committed (`024a117`) + backlog annotated
Committed the economy/player fixes. Annotated `TODO.md` (my sections only) to reflect reality:
checked off the 11 items I completed, marked 4 stale/already-shipped doc items, and re-diagnosed 3
(moon "desync", Phase Shift "no-op", sprite banking) that turned out not to be code bugs.

**Session status — where things stand:**
- **Shipped + verified (parse-clean, headless-clean):** audio cycling/ramp/voice-cap; sector-map
  planet variety + node placement + boss-ring progress + signal-event randomization; live-backdrop
  node variety; resale-arbitrage fix; Drone Swarm emit point; dead-code cull (8 shaders +
  capture_shadow cluster + 24 result dumps). Two commits: `c36a044`, `024a117`.
- **Needs your eyeball in-game:** everything in "Testing I need you to do" above (audio + sector map
  are visual/feel — I can't exercise them headless).
- **Needs your decision:** the Decisions list above (sector-map route one-liner, economy balance
  numbers, supers design calls, moon-drift behavior). I'll implement immediately once you call them.
- **Blocked on you / other session:** the 385-warning list (needs editor output), tuner-driven
  visual items (nebula, parallax sliders), and the combat-arena/bullets files the other session owns.

I've worked through the unambiguous, in-my-lane backlog. The remaining items are decision-blocked or
need your editor/tuner — so I'm pausing here for your input rather than guessing at design intent.
Nothing is pushed (per your note, pushes are yours to approve). Ready to pick up whatever you greenlight.

### 2026-06-08 — Rolled two design specs into TODO + ACE hold noted
Per your ask, read `docs/run_summary_scope_2026-06-01.md` and `docs/supers_modes_modules_2026-06-05.md`
and added both as new TODO sections (neither was present as actionable items before):
- **End-of-run summary + run history + run timer** — phased (RunStats core → instrumentation →
  victory path → history index), with the note that most hooks live in `player.gd`/`enemy_base.gd`/
  `main.gd` (shared/combat-arena files — coordinate before instrumenting).
- **Supers/Modes/Modules taxonomy refactor** — the 4-bucket restructure, stance triangle, Mode Energy
  spine, focus-save dual-hitbox, bay UI/HUD, outpost economy, the defensive-systems reify refactor,
  and the ~10-module passive roster.
- **ACE combo system — HELD per your directive.** It only surfaces as the *preferred* recharge driver
  (Driver A) for the supers stances; the spec is explicitly built to ship on Driver B (self-contained
  kill-streak) without it. I marked the ace-chain coupling ON HOLD in the supers section and did NOT
  scope it as actionable. No standalone "ACE combo" TODO item existed to flip (it lives in
  `economy_spec_2026-06-03.md` §2.2 as a locked-but-unbuilt model).

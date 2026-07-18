# Ship Unlock System — scoping (2026-07-11)

**Status: PROPOSAL — nothing built.** Hulls beyond the Reaver unlock by destroying N of a
specific enemy, counted ACROSS ALL RUNS. Locked hulls still appear in the patrol-start
hangar — maxed damage shader, selectable (codex readable), but not readyable, with a
"destroy X more to unlock" progress line. Companion: `docs/ship_starting_loadouts_2026-07-11.md`.

## Unlock mapping (Roman 2026-07-11)

| Hull | Unlocked by killing | Roster source | Notes |
|---|---|---|---|
| Reaver | — always available | — | default hull |
| Stiletto | **Shiv** | `enemy_z_s_shiv.tscn` (charger + straight variants share the scene) | zealot |
| Pilgrim | **Pilgrim** | `enemy_z_s_pilgrim.tscn` | zealot, uncommon |
| Cobra | **Cobra** | `enemy_core_s_cobra.tscn` | universal core |
| Falchion | **Falchion** | `enemy_core_s_falchion.tscn` (weave/drift/straight variants share the scene) | universal core |
| Wraith | **Skirmisher** | hold (skirmish) + retro (skirmish) roster entries — see D1 | corporate |
| Weaver | **Weaver** (namesake — CONFIRMED Roman 2026-07-11) | corp weaver scene | corporate |
| Mongoose | **Lash** (Roman 2026-07-11) | `enemy_s_s_hotrod.tscn` (display name "Lash"; 3 roster variants share the scene) | supremacy |
| Piercer | **Piercer** (namesake) | `enemy_s_s_piercer.tscn` | supremacy |
| Hive | **30 BOSSES (any)** — a different criterion KIND: cross-run boss-kill count, not an enemy tag | any boss death (Run.bosses_defeated increments per kill — Progression aggregates the same event) | prestige |

Hive pacing: 3 row-bosses per full victorious patrol → 30 bosses = **minimum 10 flawless
runs** (realistically 12–15 with losses; endless adds more). THE prestige hull — which is
also why its above-par kit is acceptable (see the loadout doc's budget exception).
Data schema gains a `kind`: `"unlock": {"kind": "bosses", "count": 30}` vs the default
`{"tag": "shiv", "count": 500, "enemy": "Shiv"}` (kind absent = enemy-tag count).
Progression stores it as `{"kills": {...}, "bosses": int}`.

## Pacing data (tools/sim_unlock_pacing.gd, 2026-07-11)

Simulated with REAL WaveGen builds over the patrol shape (3 rows × avg 4 POIs, combat
5/9 → ~6.7 combat nodes/patrol at uniform 25% faction odds, + 3 unfiltered boss lead-ins;
sd=1 for a standard single-sector run). Avg initial spawns/level ≈ 300 — matches the
3-stretch design number, so initial spawns ≈ full exposure. "Kills/run" assumes the
player kills ~70% of what spawns (leavers/recycle exits).

| Hull (namesake) | Exposure/run | ~Kills/run | @500 | Suggested threshold → runs |
|---|---|---|---|---|
| Stiletto (Shiv) | ~165 | ~115 | ~4.3 runs | **500 → ~4.3** ✓ |
| Cobra (Cobra, corpo+priv) | ~173 | ~120 | ~4.1 runs | **500 → ~4.1** ✓ |
| Falchion (Falchion) | ~91 | ~64 | ~7.8 runs | **300 → ~4.7** (see F1) |
| Weaver (corp Weaver/curve) | ~17 | ~12 | — | **50 → ~4.2** |
| Wraith (Skirmisher) | **0** (see F2) | 0 | never | hold-hull total: **75 → ~4.4** |
| Pilgrim (Pilgrim) | **0** (see F3) | 0 | never | blocked — needs roster fix |
| Mongoose (Lash) | ~58 | ~40 | — | **175 → ~4.4** |
| Piercer (Piercer) | ~14 | ~10 | — | **45 → ~4.5** |

Status 2026-07-11: **Falchion 300 + Weaver 50 APPROVED (Roman)**. The F2/F3 spawn
blockers (skirmisher + pilgrim) are being investigated separately; re-evaluate their
thresholds — and re-run this sim — once fixed. Mongoose/Piercer numbers above are from
the same sim run (supremacy = 25% of combat nodes like every faction; both namesakes are
supremacy-only, Lash is high-count chaff, Piercer is a low-weight uncommon-tier unit).

Findings:
- **Roman's hypothesis half-confirmed:** Cobra IS fastest (rolls in corpo AND privateer
  levels), but the **Falchion is privateer-only** in `Factions.ENEMY_TAGS`
  (`allowed_in: [PRIVATEER]`, comment says "for now") — one faction, so ~half the Shiv's
  rate. The Shiv scores high because zealot levels lean hard on its two chaff variants.
- **F1 — Falchion:** either threshold 300, or widen its `allowed_in` to corpo+priv (like
  Cobra/Caltrop/Jet); at two factions, 500 lands ~4 runs.
- **F2 — Skirmisher never spawns in a standard run:** the hold(skirmish)/retro(skirmish)
  roster entries are `unlock_sector: 2` — unreachable at sd=1 (single-sector). Fix: count
  ALL hold-hull kills (loiter included, ~24 exposure/run → threshold 75), or drop the
  skirmish entries to `unlock_sector: 1`.
- **F3 — Pilgrim never spawns AT ALL**, even at sd 2/3 where it's roster-eligible (80
  zealot levels: helix/bloom/sword uncommons roll, pilgrim never does). It's part of the
  2026-06-16 "Enemy-Bench-configurable, not yet in the wave roll" zealot cohort
  (crook/censer/cross/rebuker/spear also absent). The Pilgrim HULL is unlockable only
  after the pilgrim ENEMY joins the production roll (its own task) — or gets a different
  unlock enemy meanwhile.
- Boss lead-ins are included; hazard-node combats (asteroid strongholds) and endless mode
  would only add kills, so these estimates are floors.

Thresholds + display names live per-ship in the ShipCatalog `unlock` entry (see Data
below); target ≈ 4-5 full patrols per hull for consistent pacing.

## Decisions / flags

- **D1 — Skirmisher identity.** The Skirmisher scene was retired; its behavior lives as
  the "hold (skirmish)" variant on `enemy_c_s_hold.tscn` (plus "retro (skirmish)").
  Scene-path counting can't split skirmish from loiter on the shared hold hull. Fix: bind a
  roster-entry `kill_tag` at spawn (director already binds `scene_path` into the `died`
  connect — bind the tag the same way, director.gd:1568). Entries default their tag from
  the scene filename; the skirmish entries override with `"skirmisher"`.
- ~~D2 — Weaver unlock enemy~~ RESOLVED (Roman 2026-07-11): namesake corp weaver.
- **D3 — kills = player kills only.** Hook the counter into `main._on_enemy_died` (the
  bounty-award hook player.gd:1620 already documents as "only player-caused kills count"),
  NOT raw despawn/leave events. Recycled/despawned enemies don't count.

## Architecture

1. **Persistent store:** new small autoload `Progression` (`scripts/autoload/progression.gd`)
   → `user://progression.json`: `{"kills": {"shiv": 1234, ...}, "version": 1}`. In-memory
   increments; flush on `level_cleared`, run end, and app quit (NOT per kill — no disk IO in
   the combat hot path). Survives run resets by definition (Run is per-run state; Settings is
   prefs — meta-progression deserves its own file, same load-at-boot pattern).
2. **Counting:** roster entries get `kill_tag` (default = hull name derived from scene
   filename at roster-build time, explicit override for the skirmish entries). Director binds
   it through the `died` connect alongside `scene_path`; `main._on_enemy_died` calls
   `Progression.add_kill(tag)`.
3. **Unlock data:** ShipCatalog entry gains
   `"unlock": {"tag": "shiv", "count": 500, "enemy": "Shiv"}` — absent = always unlocked
   (Reaver). Query helper: `Progression.is_unlocked(ship)` / `progress(ship) -> [have, need]`.
4. **Patrol-start presentation (Roman-adjusted 2026-07-11):**
   - Locked hulls park in their slots with the damage-overlay shader (the same overlay
     enemies/player use; apply to the ShipVisual composite sprites) — **starting MAXED and
     REDUCING with kill progress** (overlay strength ≈ 1 − kills/needed), so the wreck
     visibly gets rebuilt as the player earns it. Fully-earned = overlay 0 = pristine.
   - Locked hulls render with **NO livery layer at all** (a bare unfinished airframe), and
     the **livery swatch picker is disabled** alongside Ready Ship.
   - Still CLICKABLE: left panel shows the codex entry plus the rebuild line, e.g.
     **"Destroy 368 more Shivs to rebuild"** (with the running count, e.g. "132/500").
   - **Ready Ship** disabled while a locked hull is selected (lifter never dispatched);
     status line explains why. Begin Patrol is naturally safe (requires a readied ship).
   - Live-launch default pre-ready (`_preready_default_ship`) uses the Reaver — always
     unlocked, so the fast path never trips the gate.
   - Dev launch bypass: dev-menu launches ignore locks (tuner/replay stays useful);
     optionally a Dbg "unlock all" toggle for testing the real gate.
5. **Save compat:** clamp a loaded `Run.ship_variant` to unlocked hulls (a save can't
   normally hold a locked variant, but the file is hand-editable).
6. **Later (optional):** codex Ships category shows lock progress; run summary shows
   "progress toward next hull" as a retention beat.

## Verify plan

- Unit-ish: `tools/` script seeds a progression file at N−1 kills, boots patrol-start
  headless, asserts locked/unlocked state + progress string; kills one more, asserts flip.
- Manual: fresh profile → all but Reaver locked w/ damage shader; kill Shivs across two
  separate runs → count persists; hit threshold → Stiletto readyable.

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
| Weaver | **Weaver** (namesake, ASSUMED — confirm) | corp weaver scene | corporate |

Thresholds: Roman's example is ~500. Spawn rates differ wildly by tier — chaff (Shiv,
Cobra, Falchion) can carry ~500; uncommons (Pilgrim, Skirmisher, Weaver) spawn far less
and want lower bars (~150–250). Tune with `tools/sim_wave_density.gd` data → target
"unlocks in roughly R full runs" for consistent pacing. Threshold + display name live in
the ShipCatalog entry (see Data below).

## Decisions / flags

- **D1 — Skirmisher identity.** The Skirmisher scene was retired; its behavior lives as
  the "hold (skirmish)" variant on `enemy_c_s_hold.tscn` (plus "retro (skirmish)").
  Scene-path counting can't split skirmish from loiter on the shared hold hull. Fix: bind a
  roster-entry `kill_tag` at spawn (director already binds `scene_path` into the `died`
  connect — bind the tag the same way, director.gd:1568). Entries default their tag from
  the scene filename; the skirmish entries override with `"skirmisher"`.
- **D2 — Weaver unlock enemy** is assumed namesake (corp weaver) — Roman didn't specify.
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
4. **Patrol-start presentation:**
   - Locked hulls park in their slots with the damage-overlay shader at max (the same
     overlay enemies/player use; apply to the ShipVisual composite sprites). Livery picker
     disabled for locked hulls.
   - Still CLICKABLE: left panel shows the codex entry plus a lock line, e.g.
     "SALVAGE LOCKED — destroy 368 more Shivs to unlock (132/500)".
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

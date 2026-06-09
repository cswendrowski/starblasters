# Code Review + Bug Hunt — Findings (2026-06-09)

Three parallel read-only reviewers swept (1) the recent session changes (Shift modes, Swarm Launcher,
outpost-hub, run-stats, Armory), (2) the combat hot paths (player/main/projectiles/director), and
(3) the run-state/save/meta-scene layer. Findings triaged below. **8 fixed this pass** (clear, safe,
mostly lead-lane); the rest are deferred with reasons.

---

## ✅ FIXED this pass (verified: parse + regression suite + combat boot clean)

| # | Sev | Bug | Fix |
|---|---|---|---|
| 1 | HIGH | **Minelayer miscounted as a cleared mine** — `scene_path.contains("mine")` also matches `enemy_minelayer` (a ship), inflating the "Mines cleared" run stat. | `main.gd` now matches the mine basenames precisely (`enemy_mine*` excluding `enemy_minelayer`, + `tether_mine`). |
| 2 | MED | **Hyper unlimited-ammo gap** — a dry replacement primary still snapped back to the blaster at the top of `fire_primary` while Hyper was active, contradicting "unlimited ammo." | Bypass the `ammo==0` snap-out while `_hyper_active`. |
| 3 | HIGH* | **Death-bomb could burn a charge AND still kill** — `take_damage` fired the super on a lethal hit then depended on the *part* to set `_invuln_t`. (Live super = Smart Bomb, which does set it, so not a live bug today — but fragile.) | `take_damage` now guarantees a survival i-frame itself when it fires the death-bomb (`max()` keeps Smart Bomb's longer window). |
| 4 | HIGH | **base_missile silent fallthrough** — enemy missile no-op'd on any player-group target exposing `take_damage` but not a `hull` property (violates the no-silent-fallback rule). | Drop the `and "hull" in area` clause — gate on the method only, matching base_bullet. |
| 5 | LOW | **SwarmLauncher left a stale `secondary_bullet_scene`** from a prior secondary (inert under SALVO, but stale state). | Clear `secondary_bullet_scene = null` in its `_apply_visuals`. |
| 6 | LOW | **Phase glow node not freed if the player dies mid-blink.** | `die()` now calls `_set_phase_glow(false)`. |
| 7 | MED | **Run-summary "bounty spent" under-counted** — signal-event fines / derelict IFF buys mutate `run.bounty` directly via `_apply_bounty`, bypassing the `spend_bounty` choke-point. | `_apply_bounty` routes negative deltas through `spend_bounty`. |
| 8 | LOW | **Misleading run-timer comment** ("playing is false during outro" — it isn't; outro time is excluded by the discard-on-reset). | Corrected the comment + flagged the latent double-count trap. |

\*#3 rated HIGH for the latent failure mode; not currently reachable since the lone super sets `_invuln_t`.

---

## ⏸️ DEFERRED — need Roman / the combat session / perf measurement (NOT fixed)

### Run-generation determinism (combat session's run-gen lane — design-intent calls)
- **`run_seed` is overwritten with `randi()` mid-run** (`sector_map_v3.gd:305`) on sector advance,
  contradicting the "reproducible run" contract (`run_seed` salts every per-POI decoration/stellar
  derivation + is saved). **Is mid-run reseed intentional (endless variety) or a bug?** If intentional,
  the reproducible-run comment is stale. Suggested: derive new-sector seed from immutable `run_seed`
  (e.g. `run_seed + sectors_cleared`, the convention already at `:291`).
- **`start_new_sector` seeds differ between its two `_ready` call sites** (`:291` uses
  `run_seed + sectors_cleared`, `:306` uses bare `run_seed`) — same sector can generate two layouts.
- **`start_new_sector` mutates `used_boss_scenes` as a side effect** (`run_state.gd:494`); a regen for
  the same sector re-appends, permanently shrinking the boss pool and eventually forcing the
  conflict-ignoring fallback (re-introducing cross-sector repeats). Make it idempotent per `(sector, seed)`.
→ These three are interrelated + nuanced; they touch the combat session's active run-gen. **Recommend
they own the fix** (or Roman confirms the reseed intent).

### Perf-shaped (route to `perf-runner`, don't optimize blind)
- Homing bullets/missiles re-scan the entire enemies group every frame, unbounded (`base_bullet.gd`
  `_homing_target`, `base_missile.gd` `_find_homing_target*` — the latter also `is_boss` script-walks
  per enemy per missile). With a swarm salvo in a dense wave this is O(missiles × enemies) + chain-walks.
- `main.gd` `node_added` hook stays connected all level and walks the script chain on **every** node
  added (every bullet/debris/FX) on non-boss levels (`_boss_hooked` never set). Clean win: only connect
  on boss levels, or disconnect after hooking.
- Focus trail rebuilds two `PackedVector2Array`s every focused frame (`player.gd` focus branch).
→ Hand to `perf-runner` to quantify before acting.

### Combat-session-lane edge cases (note, low live impact)
- **Beam loop SFX** can outlive the beam if released during the one-frame WARMUP→HOLD window before
  `_beam_active` is set (`player.gd` `_tick_beam` release branch gates the stop on `_beam_active`).
  Fix: stop `_pb_loop_player` unconditionally on release. (Death already covers it.)
- **Drone Bits** add free shots on a metered cannon (no ammo cost, carry `drone_bits_damage` not the
  cannon's scaling) — likely intentional, but undocumented.
- **Player-death enemy wipe** frees enemies but not their in-flight bullets/missiles (parented to root);
  harmless (player is `is_alive=false`) but visible during the death hold.

### Economy / stat polish (Roman's call)
- **Sell-backs** add bounty directly (`outpost._on_sell_stored`), not tracked in `bounty_gained`.
- **Experimental event** can downgrade the permanent Energy Blaster below its purchased Mk (probably the
  intended "chance" downside — confirm).
- **Nano-cloud / experimental Mk changes** don't reseed ammo, so a metered cannon's bigger magazine
  doesn't materialize until a re-equip.
- **Manage Ship** still lists `armor_mk` / `shield_recharge_mk` upgrade rows the outpost no longer sells.
- **Outpost bought-part aliasing** — a bought cannon offer's part instance is the same object later
  mutated in `cannon_pool`; harmless today (offers are in-memory, `sold` blocks re-buy) but a trap if
  offers are ever serialized. Suggest `equip_part(part.duplicate())`.
- **`swarm_launcher.tres`** doesn't exist (code-only authorship, like the mode parts) — fine, but it's
  the only secondary without weapon-editor `.tres` parity. Author one if designer tuning is wanted.
- ~~**Lint:** `run_state.equip_part` shadows the member `ammo` + the builtin `seed()`.~~ **FIXED**
  (`e2a8ff9`) — renamed to `sec_ammo` / `seed_ammo`.

---

## Investigated, NOT done — too risky to do blind (no playtester / no push)
- **`scripts/bullet.gd` + `scripts/bullet_wave.gd` root-misplacement** (TODO §Weapons/Architecture):
  these belong in `scripts/projectiles/`, BUT they're load-bearing — referenced by `player.tscn`, the
  whole `bullet*.tscn` / `bullet_wave*.tscn` family, and many shoot `.tres`. Relocating means rewriting
  dozens of `.tscn`/`.uid` paths; a single missed UID silently breaks the core projectile spawn, with
  no playtester to catch it. Defer to a session that can push + playtest.

---

## ✔️ VERIFIED CLEAN (checked, NOT bugs — don't re-chase)
- Save/load field mirror (`_SAVE_FIELDS` ↔ `run_save.gd` exports) is **exact** — all ~40 fields incl.
  the new `run_time_seconds`/`run_stats`/`repair_charges`/`ammo_restock_charges`/`outpost_needs_refresh`.
- Boss kill counts exactly once (`boss_base` `_dying` guard); never-pair enforced (sectors 2/3, 0 pairs).
- `_resolve_player_target` extract is behavior-preserving for the regular seeking/anti-ship missiles.
- Focus-regen-clobbers-Hyper/Phase guard present + correct; UI mode enum matches the player's.
- `ev_meta` positional index alignment in signal_event is correct (verified entry-by-entry).
- HD-scope teardown ordering sound across outpost/manage_ship/sector_map_hd (no zoomed-leave frame).
- Cannon-swap re-syncs `GunCooldown` on apply/unapply; `damaged`/`died` signal wiring is leak-free.
- Outpost charges can't go negative; `_on_leave` correctly no longer marks nodes.
- Armory null-part + `bullet_scene` guards solid; all factory names resolve in `part_catalog`.

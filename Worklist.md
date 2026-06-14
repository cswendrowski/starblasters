# Worklist

_Refreshed 2026-06-12 (round 2): the nebula / glow-halo / renderer / ship-dmg work is committed
(`3af593d`, `4f862fd`) — moved to "Done" and pruned the stale nebula appendix. Only genuinely-open
items remain below. Deep specs live in `TODO.md` / `docs/` — this is the scannable index._

---

## Done this session (committed — awaiting in-game eyeball)
- ✅ **VFX batch** (`3af593d`) — centralized tunable explosions (+ editor ember/spark scenes), ship
  damage-tell suite, smoke/spark/burning-trail rebuild (fire-comet scrapped), Sequence Lab, Enemy
  Bench full roster + faction tabs + mines disarmed, glow_effect_2d/ember/debris/smoke tuners.
- ✅ **Nebula rework** (`4f862fd`) — `swirl_speed` (dynamic filament churn) + per-POI re-enable
  (sector map → coordinator → layer) + Shader Lab Nebula page. *(glitch fix + A/B alts uncommitted, below.)*
- ✅ **Glow-halo → bloom** (`4f862fd`) — pulled all 5 projectile halos (resolves the bullet glow-ghost
  residuals); HDR-bright bolts (`BULLET_HDR_GAIN`) so the live threshold-1.0 bloom glows them. Engine
  flame already gone; player GlowMask kept.
- ✅ **`outline_1px` Forward+ crash fix** (`4f862fd`) — removed the sampler-as-function-param.
- ✅ **Ship-Dmg progressive burn trails + torch precursors** + **size-filter fix** (`4f862fd`).
- ✅ **Renderer levers A + B** confirmed already live (`glow_hdr_threshold = 1.0` + color grade);
  **lever C** partial (muzzle/explosion/bullets HDR-bright).

### Eyeball / tune (your call — can't verify headless)
- **Nebula** — flip the Shader Lab → Nebula A/B (nebula2 vs the 2 godotshaders alts), pick a direction;
  then set live per-band alpha/density + `nebula_swirl` + `NEBULA_NODE_CHANCE`.
- **Bullet bloom gain** (`base_bullet.BULLET_HDR_GAIN = 1.8`) — fire shots, tune.
- **Burn trails / torch** — Shader Lab → Ship Dmg. **Ship-Dmg size filter** — confirm bands.
- **outline crash** — confirm an asteroid hazard + normal combat boot clean.

## Uncommitted (current)
- **Nebula glitch fix** (square native-aligned pixelation + precision-robust integer hash) + **A/B alt
  shaders** (`nebula_alt1` / `nebula_alt2`, godotshaders CC0) + tab selector. One cohesive nebula
  batch — commit once a direction's picked.

## Renderer (`docs/renderer_audit_2026-06-11.md`)
- ◑ **Lever C remainder** — >1.0 additive pass on **shield ring / beam cores / super flashes / engine
  GlowMask** so they bloom too (only if wanted).
- ☐ **Lever D** — screen-space sweeteners (heat-haze behind exhaust, explosion ripple, damage CA).
- ☐ **Nebula parallax blend-mode dropdown** — tuner color/brightness/contrast sliders VERIFIED WORKING
  (old "not working" note was stale); remaining = a Mix/Add/Mul/Screen option (non-trivial:
  `CanvasModulate` is multiply-only → needs a per-layer overlay/grade shader).

## Audio
- ~~**Corpo-wave audio restart**~~ — PARKED 2026-06-13 (Roman: drop for now, reopen if it bites in
  playtesting later). Symptom: music stops then restarts when a round begins (`music_manager.gd`).

## Weapons / data
> **Wave 1 sweep DONE 2026-06-13** (uncommitted, parse + headless-boot clean): relocated
> `bullet.gd`/`bullet_wave.gd` → `projectiles/` (+ UID-cache reimport); re-saved drone_bits/drone_swarm
> `.tres` — **Intercept Drones was spawning 1 drone not 3** (stale Gradius-era `base_drones=1`), fixed to
> 3/3; wired a per-pattern `bullet_speed` override (`shoot_pattern.gd` honors it pre-mult, `make_shoot`
> exposes a `"bullet_speed"` entry key); wired `AimedShot.lead_factor` through `make_shoot` + gave the corp
> aimed-sniper skirmisher (`enemy_c_s_hold` advance/retreat) a 0.15 lead; **fixed the hunter-drone kamikaze
> bounty leak** (awarded bounty on contact via BOTH the self-destruct and the player-ram path — now 0).
> Codex rename + boss `bullet_variant` were already done (stale items). 👁 playtest: skirmisher lead feel +
> Intercept-Drones count.
- **Weapons 3b** — ◑ **PRODUCERS DONE 2026-06-13** (uncommitted): `make_shoot` + `levels_v2` + `wave_generator`
  now build the unified `Weapon` (the bulk of enemy firing routes through one resource). Verified
  dir+speed-equivalent to the legacy classes via `tools/test_weapon_3b_equivalence.gd` (PASS) + fixed a latent
  `Weapon.TOWARD_CENTER` sign bug (aimed away from center; unused until now). `burst_shot.tres` is moot (folded
  into Weapon BURST). Also de-flaked `test_weapon_intake.gd` (chaff-only RNG rolls now SKIP, not false-FAIL).
  **REMAINING TAIL** (playtest-gated, separable): the legacy classes can't be deleted yet — still embedded in ~6
  designer `.tres` (enemy_blaster/cannon/diamond_gun/laser_cannon/wave_cannon/mg) + ~5 enemy scenes
  (cutter/drifter/hover/weaver/skirmisher) + `test_wave_darts.tres`. Migrate those to `Weapon`, then delete the classes.
- **Dev bullet-speed editor** — absolute rungs (1–8 = 60–480 px/s), save to `data/bullets/*.tres`.
- **DPS report + `weapon_stats.csv`** — ◑ **REPORT DONE 2026-06-13** (uncommitted): reproducible generator
  `tools/weapon_dps_report.gd` regenerates the CSV from live Part data; added **Shredder** (30→50) + **Pulse
  Laser** (33 flat); caught the **Spread→Scatter-Blaster, now-infinite-ammo** drift; fixed the `.import`
  (`importer="keep"` → no more `.translation` regen). Full table + findings: `docs/weapon_dps_report_2026-06-13.md`.
  REMAINING = the **rebalance** itself (Energy trim / Minigun buff / Autocannon curve / Pulse-flat? / Scatter-∞?)
  — surfaced, NOT applied (your call).
- Smaller knobs (remaining): wave-gen `bullet_variant` override, chaff-speed sector scaling.
- Cleanup (remaining): muzzle-flash-as-scenes (opt), per-Part `fire_offset`.
- **Manage Ship modal** — ✅ **SELL UI DONE 2026-06-13** (branch `manage-ship-sell-ui-2026-06-13`): spare
  parts (weapon_storage + inventory) now show **Equip + Sell** buttons; Sell credits the **10%** resale
  (TODO said 20% — stale; aligned to the outpost/signal-event 0.1 rate). PartTier badges already existed.
  Equipped/permanent-blaster aren't sellable (matches outpost). 👁 eyeball the two-button row layout.
  Optional follow-up: mirror the outpost's rarity-name/type/stat-line card treatment (`e224405`).

## Big features (unbuilt)
- **Passive-Module bay** — ◑ **BUILT 2026-06-13** (branch `passive-module-bay-2026-06-13`, local/unpushed;
  spec `docs/passive_module_bay_2026-06-13.md`). List-backed (`Run.modules` ≤5 + one `MODULE` tag, NOT the
  pegboard) + one apply loop alongside the loadout. **Reified Shield Core** (default; drop it = glass cannon,
  `max_shield 0`; default-safe + old-save migration) + new **Overcharge Core** (+10→30% dmg, −1 charge) +
  **Siphon Core** (kills restore shield), plus defensive reifies **Repair Nanites** (in-combat hull regen,
  gated to max−1) + **Ablative Plating** (deterministic every-Nth-hull-hit absorb, no RNG). 5 modules (1
  default + 4 roll). Modules roll in the **outpost** (item-gen rules; purchase → bay, cargo if full) and are
  managed in **Manage Ship** (a MODULE BAY row, Equip-from-cargo / Remove). 23-assert `tools/test_module_bay.gd`
  PASS; parse-clean (297/0); outpost/manage_ship/main boot clean.
  **Retired the overlapping upgrades** (2026-06-13): `self_repair_mk` + `hull_plating_mk` are gone from the
  shop / salvage event / Manage-Ship display + their effects (between-node heal, RNG shrug) — those mechanics
  are now solely the Repair Nanites / Ablative Plating modules. Fields kept in run_state/RunSave for save compat
  (the `armor_mk` precedent); also pruned the already-stale `armor_mk`/`shield_recharge_mk` from the salvage
  list so it never grants a dud. The in-combat HUD module-strip was **declined** (Roman 2026-06-13). Modules
  also have **codex entries + armory_strings blurbs** (a "Modules" codex tab). **8 modules built**: Shield Core,
  Overcharge, Siphon, Repair Nanites, Ablative Plating, **Targeting Computer** (crit + purple bolts),
  **Overclock Core** (sustained-fire ramp), **Critical System De-Limiter** (fire/dmg scale as hull drops).
  Tractor Coil cut (no pickup system). **Upgrades→modules (2026-06-13):** ALL shop upgrades are now modules —
  Shield Core's Mk drives shield capacity (folded the shield-cap upgrade), + new **Reinforced Hull**, **Thrusters**,
  **Shield Capacitor** (regen rate + delay). Outpost UPGRADES column removed (parts column widened, renamed "PARTS");
  Manage-Ship upgrade display emptied; Salvage Cache grants a module now. Bay bumped to **6**. **11 modules total.**
  Only **Intercept Drones** remains designed-not-built. **Bay complete.** Module *feel/balance* + purple-crit look +
  the new shop layout are playtest/eyeball-gated — don't tune unprompted.
- **Run summary Phases 2–3 + timer** — ✅ **DONE 2026-06-13** (branch `run-summary-2026-06-13`, local/unpushed):
  Phase 2 stats instrumented — **shots fired/hit + accuracy** (per-projectile: `player.fire_primary/secondary`
  + `enemy_base.take_hit`), **locations/signals visited** (`mark_node_completed`), **outpost visits**
  (`outpost._ready`), **unique weapons** (`note_weapon_used` set off the active cannon). **Victory path**:
  `cleared_summary` detects the final-sector clear → routes to a **"PATROL COMPLETE"** run-summary (was
  death-only; final clear used to loop into the endless map). `run_summary` + `run_history` now show all of
  it; `test_run_stats.gd` extended (30 asserts PASS). Timer was already built. Phase 1+4 were already done
  (the scope doc was stale).
- **Sector modifiers** — pulled (kill-switched); re-eval + reimplement.
- **Recycler — Pillar 2** — controller + tuner + roster migration (playtest-gated).

## Enemies / waves  *(playtest-gated)*
- Cohesive chaff / bomb-drone walls + minefield real numerics. Conductor no-repeat + mix lane patterns.
  Speed audit to the 1–8 rungs (partial). Supremacy Push globbing. s_s_rush facing. Tracer doubled-glow.
  480-speed "Sprint Dart". Mine hazards → 300-enemy density.

## Bosses
- Biome reskins per boss. Shared enrage-VFX helper. Bosses with omni-strafe.

## Art-gated (need sprites first)
- **Faction gap units** — supremacy (drifter/crosser/elite), zealot (medium anchor / large capital),
  privateer (small holder/skirmisher, large capital, elite), corporate (slider + elite).
- **Overhaul Asteroid Hazard** — structural pass (bg asteroids overlapping playspace).

## Cleanup
- `scenes/sector_map.tscn` orphan. `SmokeTrail.new(palette)` factory (not urgent). Shipyard stat
  editor / sprite picker. Gamepad rebind in-app. Backdrop V3 missing debris sprite.

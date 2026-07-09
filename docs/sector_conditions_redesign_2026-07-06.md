# Sector Conditions — redesign (rename of "Sector Modifiers")

**Status: BUILT (v1, 2026-07-09) — unplaytested.** The pipe, all effect sites, and the Wildcard
front-end shipped; see **Build status** below. This doc remains the design reference; the code is
the source of truth for exact numbers.

Rev 3 (2026-07-06): Roman resolved the two damage-rule conflicts (Glass Patrol + Heavy Ordnance are
now defined) and added a large player-weapon / loadout-restriction / bounty-grant batch. Vocabulary
reorganized into functional buckets with a signed **Threat** column (§4), reward model is one signed
Threat budget (§5). Supersedes the modifier notes in the archived `economy_2026-05-24.md` §1.3.

## Build status (v1 shipped 2026-07-09)

- **Core** — `scripts/systems/conditions.gd` (`class_name Conditions`): 45-entry declarative
  CATALOG (label/blurb/threat/mutex-group/mods), generic aggregators (scalar=product, sum, flag,
  union), `net_threat`/`bounty_mult`/`materials_mult` (K_BOUNTY 0.08 / K_MATERIALS 0.06,
  tuner-bound), deterministic mutex-respecting `roll(count, seed)`, `validate()`. Run integration:
  `Run.active_conditions` (+ save whitelist + run_save mirror), `cond_*` delegates, and
  **`Run.apply_conditions(ids)`** — the ONE front-end entry (sets list → re-seeds loadout snapshot
  so start.no_* gates fire → awards `grant.start_bounty`). Effects read ONLY via aggregators — no
  per-id match statements anywhere.
- **Combat sites** — director `_apply_conditions` (replaces the legacy `_apply_sector_modifiers`;
  `armed` arm deleted) with one `_is_heavy_enemy` predicate (reuses ANCHOR_MIN_HEIGHT);
  `_resolve_shields` Condition read (heavy-scoped); `Clarity.step_rung` ladder-walker (creep-aware);
  `ProjectileMods` (NEW — centralizes the 3× copy-pasted bullet scaling + the twice-defined
  damage cap; launcher path gets Condition speed only); player `take_damage`: Heavy Ordnance mult
  (sanctioned flat-damage break) + Glass Patrol instant death (pip branch; the super death-bomb
  save IS respected — Roman 2026-07-09).
- **Player kit** — `_wpn_dmg()` choke point wrapping **10** damage-write sites (incl. Echo ghost,
  Reflect bounce, burst rockets, Particle Beam DPS; ram excluded); fire-rate into `_fire_bonus` +
  blaster + secondary (+ burst cadence via follow-up); mode duration; hull bonus; shield charges
  ×mult + regen delay/interval (floored 1.0s/0.25s); ammo caps scaled once per flow (Run seeds +
  part-apply caps); No-X filters INSIDE `part_catalog.roll_for_slot/roll_random_part` (covers
  outpost + all signal-event grants; codex unfiltered); starting-kit gates in both
  `default_starting_loadout` and `_seed_default_loadout_snapshot`.
- **Economy** — `Run.award_bounty`/`award_combat_materials` choke points (record_kill routes
  through; miner payout + hazard +25 no longer bypass); grants in `_on_level_cleared` (Hazard Pay
  non-boss, Salvage Rights level/boss split; grant-then-mult stacking documented);
  `mine_bonus_bounty` field + per-mine reads (5 mines) + asteroid `grant.asteroid_bounty`; outpost:
  price mult at roll time, stock delta, mk_bias in `_roll_weighted_mark` (dead `MK_HIGH_OFFSET`
  deleted), shared `_upgrade_costs()` (display/spend dup killed), repair cost/mats
  (repair pairs recast: complex=+1 mat, cheap=2 mats no bounty, easy=baseline placeholder),
  restock mult (flat + per-round variants).
- **Front-ends (2026-07-09, second pass)** — patrol setup got a LOADOUT|CONDITIONS tab with four
  modes: **Off / Picked** (curated bucket-grouped picker, live mutex de-selection, Threat chips +
  running Threat/payout summary) / **Random** (Bad+Good count steppers, visible re-rollable Roll —
  uses `Conditions.roll_split(banes, boons, seed)`, one shared mutex dict across both pools) /
  **Blind** (counts only; rolled secretly at Begin from `run_seed ^ salt`, deterministic per run).
  Setup persists to `user://conditions_setup.json`; the old 0–5 stepper + `patrol_sector_modifiers`
  meta are retired. The outpost services column got a **SERVICES|STATUS tab**: Status lists active
  Conditions threat-sorted with ±chips and per-row ⓘ expanding the catalog blurb — the in-run
  reveal surface for blind patrols. The top-bar one-liner readout remains.
- **Tests** — `tools/test_conditions{,_economy,_player,_wildcard}.gd`, all PASS headless;
  parse_check 377/0.
- **NOT built (deferred)** — the four design-heavy enemy banes (Debris Fields, Elite Patrol,
  Reinforced, Bounty Hunters — not in the catalog yet), pacts, a launch reveal *beat* (the Status
  tab + summary meta cover the functional need), Threat Level selector, per-node Hotspots, the
  Threat/K tuner, legacy `sector_modifiers` retirement (roll machinery still parked behind the
  kill-switch). ~~Curated picker~~ ~~projected-payout panel~~ — built as the Picked mode + summary
  line (2026-07-09).
- **Playtest flags** — Glass Patrol respects the death-bomb save (a charged super rescues the
  lethal hull hit; Roman 2026-07-09); Hazard Pay/Starting Funds stack under bounty_mult
  (grant-then-mult); Faster Weapons covers all four cadence paths incl. burst rockets; beams no-op
  for Fast/Slow Bullets.

---

## 1. Why it was pulled, and what changed underneath it

The original system was a per-POI random roll that scaled with sector depth. Two things made it unfit:

1. **The multi-sector roguelite collapsed to a single-sector patrol.** `TOTAL_SECTORS = 1`,
   `sectors_cleared` stays 0, and the per-sector damage ramp `dangerous` was balanced against was
   retired (2026-06-23). The count driver `modifier_count = 1 + sectors_cleared`
   ([run_state.gd:602](../scripts/autoload/run_state.gd)) is therefore dead — it always yields 1.
2. **It was all-stick-no-carrot and invisible.** Seven of eight modifiers are pure player debuffs;
   only `wanted` rewards you. They roll *per-POI* but are only ever shown as a deduped sector-level
   list in the outpost — you walk into a "dangerous" fight blind. A roguelite modifier is only
   interesting when it's a **telegraphed risk you choose**, paired with a **reward**.

**Design thesis:** a Condition is a deal the player opts into. Each carries a signed **Threat** value;
the run's payout bonus (bounty + materials %) derives from the **net Threat** the player signs up for
(§5). Chosen, telegraphed, rewarded — that framing is what makes the system worth re-enabling.

Rename **modifier → Condition** throughout (player-facing and code). Keep `has_modifier()` as the
internal query name or rename to `has_condition()` — cheap either way (single seam).

---

## 2. What exists today (all parked, all reusable)

| Piece | Location | State |
|---|---|---|
| Kill-switch | `run_state.gd` `SECTOR_MODIFIERS_ENABLED = false` | flip to re-enable |
| Vocabulary (8) | `run_state.gd` `ALL_SECTOR_MODIFIERS` | reframe (§4) |
| Per-enemy effects | `director.gd` `_apply_sector_modifiers` | mostly reusable |
| `dangerous` ×2 dmg | `player.gd` `take_damage` | **becomes Heavy Ordnance** (§4b) |
| `cruiser_support` mult | `run_state.gd` `cruiser_encounter_chance_mult` | keep — good seam (Heavy Escort) |
| `shielded` +1 charge | `director.gd` `_resolve_shields` | keep; scope to non-chaff |
| Query seam | `run_state.gd` `has_modifier(id)` | keep |
| Active list | `run_state.gd` `sector_modifiers: Array` | becomes `active_conditions` |
| Labels | `strings.gd` `MODIFIER_LABELS` | rewrite as bane/boon (§4) |
| Outpost readout | `outpost.gd` `_format_sector_modifiers` | keep, extend with Threat/payout line |
| Weapon-scalar seam | `enemy_base.gd` `bullet_speed_mult`/`bullet_damage_mult`, ceiling-clamped at spawn (`shoot_pattern._spawn_bullet`, [enemy_turret.gd:253](../scripts/enemies/enemy_turret.gd)) | **live in production** — Fast/Slow Bullets ride it (§4a) |
| Asteroid bonus-bounty | `run_state.gd` `asteroid_bonus_bounty` (Asteroid Miners event; read [asteroid.gd:65](../scripts/enemies/asteroid.gd), paid [main.gd:455](../scripts/game/main.gd)) | **live** — Mining Contract rides it additively (§4f) |
| Part drop pool | `part_catalog._all_pool()` — flat `{factory, slot}` array | slot-filter for the No-X family (§4c) |
| **Patrol-setup stepper (0–5)** | `scripts/screens/patrol_start.gd` (~L936), writes `patrol_sector_modifiers` meta | **half-built — unconsumed** |

Cleanups that fall out regardless of front-end:

- **Retire the `armed` arm.** `director.gd` has a `match "armed"` arm (bullet dmg ×1.3) that's in
  neither `ALL_SECTOR_MODIFIERS` nor `MODIFIER_LABELS`. It's a **no-op against the player** (flat
  damage = 1/hit, [[flat-player-damage]]) and "Heavy Ordnance" now names the ×2 player-damage
  doubler (§4b), so drop the arm rather than promote it.
- **`fleeing` is mislabeled and imperceptible.** `recycle_passes = 0` = "don't loop back," which the
  player can't perceive and is arguably a boon in a bane pool. Rework into real flee behavior or
  retire (§4b note).

---

## 3. Run structure this has to fit

A patrol = **1 sector = 3 rows (lanes)**. Each row has 3–5 POIs (combat / hazard / signal) plus a
boss; you clear *every* POI on a row to unlock its boss, and kill all 3 bosses to win
([run_state.gd:923 `is_row_pois_complete`](../scripts/autoload/run_state.gd)). ~9–15 combats + 3
bosses, and you fight **everything** — not a pick-one-path map. Outposts are a hub button, not a node.

Consequence: **patrol-wide Conditions** (whole-run pre-commitments) are the natural primary surface —
like a Hades Pact or StS Ascension. **Per-node Conditions** work as a *secondary* spice layer, but
since you fight every node they're "this fight is hot — extra reward," not "route around it."
Telegraphing on the map is mandatory if we use them.

---

## 4. Vocabulary — functional buckets

Every Condition carries a signed **Threat** `T` (+ harder / − easier); the run's payout derives from
net Threat (§5). `T` values below are first-pass, for `economy-sim` to tune. **Mutex groups** (at
most one active per group; pacts flatten before the check): Enemy-toughness (Armored/Armored-Heavies
if exclusive), Enemy-speed (Fast↔Slow Enemies), Bullet-speed (Fast↔Slow Bullets), Weapon-damage
(Weak↔Better Weapons), Shield-strength (Weak↔Better Shields), and the eight economy pairs (§4e). The
No-X family (§4c) are independent slots — they may stack.

### 4a. Enemy banes — tougher / faster / more enemies

| Condition | T | Effect | Source / notes |
|---|---|---|---|
| **Armored** | +2 | enemy DR tiered 10/15/20% | `director` `_apply_sector_modifiers`; **collapse `armored`+`heavily_armored`**; scope DR to heavies/elites (global DR on chaff drags the fast-kill rhythm). |
| **Armored Heavies** *(Roman)* | +2 | non-chaff enemies get +max HP | `director` (`max_hull`); distinct feel from Armored (pool vs per-hit). Same mutex group unless playtest OKs stacking. |
| **Shielded** | +2 | enemy +1 shield charge | `director` `_resolve_shields`; scope to non-chaff. |
| **Trigger-Happy** | +2 | enemies fire faster (`fire_interval × 0.85`) | `director`; fire-rate only (speed → Fast Bullets). ~~**Compounds** with Supremacy `fire_rate_mult 0.7`~~ (removed 2026-07-07 — fire rates authored directly in roster config; no faction fire-rate mult). |
| **Fast Enemies** *(Roman)* | +2 | enemy movement +1 rung (cap rung 8) | `director` at spawn; walk the `Clarity.SPEED_RUNGS` ladder (creep half-rung!), **exclude hazard drift**. |
| **Fast Bullets** *(Roman)* | +2 | enemy bullet speed +1 rung (cap rung 8) | flat ±`RUNG_STEP` at the existing scalar site w/ `ABS_MAX_SPEED` clamp (§2). |
| **Heavy Escort** | +2 | rare cruisers far more common | `cruiser_encounter_chance_mult` (keep `cruiser_support`); intrinsically boon+bane (more loot *and* danger). |
| **Debris Fields** *(new)* | +2 | stray asteroids/mines drift through combat nodes | hazard conductor + decorative-mine spawner. |
| **Elite Patrol** *(new)* | +3 | heavies replace a fraction of chaff | wave palette; composition shift, not a stat tax. |
| **Reinforced** *(new)* | +3 | active-faction overlay a tier up / more spawns | `factions.gd` `apply`; compounds w/ faction mults by design — bench worst stack. |
| **Bounty Hunters** *(new)* | +2 | an extra elite "hunter" spawns mid-wave | director spawn hook; pairs with Bounty Surge. |

### 4b. Player-fragility banes — the intentional rule-breakers

| Condition | T | Effect | Source / notes |
|---|---|---|---|
| **Glass Patrol** *(Roman)* | +5 | **any hull damage = instant death.** No damage states; hull/ablative modules removed from the roll | `player.gd` `take_damage` (hull-hit → `die()` directly, skip pips/tells); filter `_make_ablative_plating` + Reinforced-Hull from `_all_pool()`. **Flat-damage-compatible** — it's a death trigger, not a damage-amount change. Shields still absorb normally; first hull hit ends the run. Supersedes hull-quantity boons (Better Hull becomes cosmetic — Curated should grey it). |
| **Heavy Ordnance** *(Roman; replaces `dangerous`)* | +4 | **all player damage ×2** — burns 2 shield charges / 2 hull pips per hit | `player.gd` `take_damage`. **Intentionally breaks the flat-damage rule** ([[flat-player-damage]]) — Roman-sanctioned; this Condition *is* the exception. Keep i-frames so it isn't a chain-kill. |
| **Weak Shields** *(Roman)* | +3 | shield module starts at ½ charges and gains ½ per progression tier | Shield Core Mk→charge mapping (`ShieldComponent` capacity + per-Mk growth). Mutex w/ Better Shields. |
| **Weak Weapons** *(Roman)* | +3 | player weapon damage ×0.5 (rounded) | player-side damage mult (§8 — needs one choke point). Mutex w/ Better Weapons. |

*(Retire/rework `fleeing` here if kept: real flee behavior — low-HP enemies bolt off-screen, trading
dropped bounty for a faster clear.)*

### 4c. Loadout-restriction banes — constrain the build (starting kit always unaffected)

| Condition | T | Effect | Source |
|---|---|---|---|
| **No Primaries** *(Roman)* | +2 | no CANNON weapons rolled/given (keep your blaster) | filter `slot == CANNON` from `_all_pool()` at the offer roll. |
| **No Secondaries** *(Roman)* | +1 | no HARDPOINT_WING weapons rolled/given | filter `slot == HARDPOINT_WING`. |
| **No Modules** *(Roman)* | +2 | no MODULE **or** SHIFT_MODE parts rolled/given ("including new modes") | filter `slot in {MODULE, SHIFT_MODE}`. |
| **No Starting Super** *(Roman)* | +1 | don't start with the smart-bomb super | skip the DEVICE_BAY_1 default at initial equip. |
| **No Starting Mode** *(Roman)* | +1 | don't start with a shift-mode (no Focus) | skip the SHIFT_MODE default at initial equip. |

### 4d. Player boons — stronger kit / easier fights

| Condition | T | Effect | Seam / notes |
|---|---|---|---|
| **Better Weapons** *(Roman)* | −2 | player weapon damage ×1.5 (rounded) | same choke point as Weak Weapons (§8). Mutex w/ Weak Weapons. |
| **Faster Weapons** *(Roman)* | −2 | player rate of fire +50% (rounded) | weapon `base_cooldown` / player fire cadence (respect the sub-frame residual fix, [[fire-cadence-tick-alignment]]). |
| **Better Modes** *(Roman)* | −1 | shift-modes last 50% longer | mode duration on `mode_part.gd` ([[shift-mode-unification]]). |
| **Better Hull** *(Roman)* | −2 | starting hull +3 pips | `apply_run_upgrades()` after loadout sets `max_hull`. **⚠ +3 on a base-2 hull = 2.5×** — shadows the Reinforced Hull module; price steep or trim to +2. |
| **Better Shields** *(Roman)* | −2 | shorter recharge delay + faster regen ticks | `_effective_regen_delay()` + the 1/s tick; floor the delay (composes w/ Capacitor/Energy Routers). Mutex w/ Weak Shields. |
| **More Ammo** *(Roman)* | −1 | +50% max ammo, all armaments | scale `ammo_max` / `secondary_ammo_max` / per-part `ammo_max` at loadout; capacity only, don't touch the two-tier regen rules ([[weapon-ammo-economy-tiers]]). |
| **Slow Enemies** *(Roman)* | −2 | enemy movement −1 rung (floor: creep) | ladder-walk, mutex w/ Fast Enemies, excludes hazard drift. |
| **Slow Bullets** *(Roman)* | −2 | enemy bullet speed −1 rung (floor: rung 1) | same delta site, mutex w/ Fast Bullets. |

### 4e. Economy pairs — outpost ledger (inverse boon ↔ bane, mutex by group)

Seams verified against `outpost.gd`. Bane `T ≈ +1…+2`, boon `T ≈ −1…−2` (symmetric).

| Group | Bane | Boon | Seam |
|---|---|---|---|
| Buy prices | **Galactic Tariffs** (+20%) | **Buyer's Market** (−20%) | offer `cost` at roll/buy. |
| Stock count | **Market Scarcity** | **Market Surplus** | offer count in `_roll_offers`. |
| Mk quality | **Shoddy Imports** | **Quality Goods** | weighted Mk roll (`MK_HIGH_OFFSET`). |
| Upgrade — materials | **Complex Upgrades** (+mat) | **Cheap Upgrades** (mat only) | `mats = new_mk`. |
| Upgrade — bounty | **Costly Upgrades** (+bounty) | **Easy Upgrades** (bounty only) | `_upgrade_bounty_cost`. |
| Repair — materials | **Complex Repairs** (+mat) | **Cheap Repairs** (mat only) | `_on_repair` — **⚠ repairs cost no material today** (§8). |
| Repair — bounty | **Costly Repairs** (+bounty) | **Easy Repairs** (bounty only) | `_hull_repair_cost()` (compose w/ the Mk-9 30% discount). |
| Restock | **Costly Restock** | **Cheap Restock** | `PRIMARY_REFILL_COST` / `AMMO_COST_PER_ROUND` / `SUPER_REFILL_COST`. |

"Costs *only* X" presupposes both currencies. Upgrades already cost both; **repairs don't** — resolve
in §8 before building the repair pairs.

### 4f. Economy grants — bounty / material boons

| Condition | T | Effect | Seam / notes |
|---|---|---|---|
| **Salvage Rights** *(Roman)* | −2 | every combat level grants ≥1 material; bosses grant more | grant hook at `level_cleared` / boss payout. A floor, not a %. |
| **Hazard Pay** *(Roman)* | −2 | clearing any combat POI (combat **or** hazard) → +100 bounty | per-node clear payout. **⚠ ~12–15 nodes ≈ +1,200–1,500/run** — steep; `economy-sim` it, maybe 50. |
| **Starting Funds** *(Roman)* | −1 | start the patrol with **500 bounty** *(bumped from 250)* | apply after `new_run()` zeroes bounty, in `patrol_start._launch`. |
| **Mining Contract** *(Roman)* | −1 | asteroids worth 5 bounty each in hazards; **stacks with events** | **add to** `Run.asteroid_bonus_bounty` (the Asteroid Miners event sets it; make Condition + event additive, not overwrite). |
| **Ordnance Disposal** *(Roman)* | −1 | mines worth 5 bounty each; **stacks with events** | **needs a new `mine_bonus_bounty` field** mirroring `asteroid_bonus_bounty` — mines are `bounty_value = 0` today with no bonus seam (§8). |

### Pacts (pre-bundled, one-tap; mutex on the flattened set)

- **Blood Money** — Heavy Ordnance, **+big bounty payout**.
- **Scrap Run** — Shielded + **Salvage Rights**.
- **Speed Trap** — Trigger-Happy + **Better Shields**.
- **Black Market** — **Galactic Tariffs** + **Quality Goods**.
- **Bare Fists** — No Primaries + No Secondaries + **Better Weapons** (blaster-only, hard-hitting).

---

## 5. Reward model — one signed Threat budget

Every Condition declares one signed **Threat**. The run's payout bonus derives from **net Threat,
floored at zero**:

```
net_threat     = Σ(condition.threat)
bounty_mult    = 1 + K_BOUNTY    × max(0, net_threat)
materials_mult = 1 + K_MATERIALS × max(0, net_threat)
```

Two global knobs (`K_*` ~0.05–0.10) instead of a per-bane weight matrix — one dial, and the tuner /
`economy-sim` pass works on Threat values. What the unified budget buys:

- **Economy + fragility banes are pickable.** Galactic Tariffs / Glass Patrol contribute +Threat →
  raise the payout. The player can take a squeeze *for* the bonus.
- **The boon free-lunch is priced, not punished.** An all-boon loadout drives net Threat negative →
  payout bonus floors at zero, never a penalty. An easy, boon-stacked patrol stays legitimate — it
  just doesn't pay extra (and reads as a low Threat rating on the summary).
- **Wildcard needs no roll bias.** A boon simply eats budget; the payout self-corrects.
- **Direct grants stay direct.** Salvage Rights / Hazard Pay / Starting Funds / Mining Contract /
  Ordnance Disposal pay their own flat effects (that's *why* they carry negative Threat); the
  multipliers apply to ordinary bounty/material drops on top.
- **Threat rating** (net Threat, bucketed into named bands) is the run-summary line and the future
  meta-unlock hook — a display, not a second currency.

**Source/sink tension** stands: a combat bane pumps `materials_mult` up while Complex Upgrades makes
materials cost more to spend. That's the design, not a bug.

Surface live numbers at patrol setup ("Threat 8 — projected +55% bounty, +40% materials, prices
+20%") and extend the outpost readout. Tuning needs a tuner (Copy-GDScript button) once numbers
matter.

---

## 6. Front-ends (one pipe, multiple UIs)

All front-ends write the same `Run.active_conditions: Array` and reuse every effect site in §2. Build
the pipe once; each UI is then cheap. Which to build, and in what order, is Roman's call.

1. **Wildcard count** *(smallest first ship)* — consume the 0–5 stepper already writing
   `patrol_sector_modifiers` (`patrol_start._launch`). Roll N mutex-respecting Conditions, store,
   **reveal** on a confirmation beat. ~1 consume-function + the roll; proves the pipe end-to-end.
2. **Curated picker** — hand-pick from cards showing effect + Threat, with running Threat total and
   projected payout; greys out mutex-blocked and superseded options (e.g. Better Hull under Glass
   Patrol). Most agency; most UI.
3. **Threat Level** — a named selector (Routine → Standard → Hot → Critical) that auto-stacks banes to
   a target net Threat. The Hades-Heat / StS-Ascension meta hook. Same pipe.
4. **Per-node Hotspots** *(Phase 2, highest polish)* — flip the per-POI roll back on but make it
   **visible**: badge + tooltip on flagged nodes, harder fight = guaranteed bonus. Reuses the
   `_gen_row_pois` machinery. "This fight is hot," not "avoid this one."

These map 1:1 onto Roman's brief (pick / roll-a-count / difficulty / all-of-the-above).

---

## 7. Recommended phasing

1. **Pipe + vocab reframe.** `active_conditions` + per-Condition Threat + mutex metadata + net-Threat
   payout multipliers. Collapse `armored` tiers; split `aggressive` (fire-rate → Trigger-Happy,
   speed → Fast Bullets); wire Glass Patrol + Heavy Ordnance in `take_damage`; retire the `armed`
   arm; retire/rework `fleeing`. Re-enable combat sites behind the flag.
2. **Player-kit + loadout sites.** Weak/Better/Faster Weapons choke point; Weak/Better Shields; Better
   Modes; Better Hull; More Ammo; the No-X drop-pool filters + No-Starting-Super/Mode initial-equip
   skips.
3. **Economy-axis sites.** Price / stock / Mk-roll / service-cost hooks in `outpost.gd` (§4e); the
   grant hooks (§4f), incl. the new `mine_bonus_bounty` field. Independent — can land in parallel.
4. **Wildcard count front-end** (first playable; honors mutex).
5. **Reward surfacing** (patrol panel + outpost line) + a Threat/`K_*` tuner.
6. **Curated picker**, then **Threat Level**.
7. **Per-node Hotspots** (Phase 2) if the patrol-wide version proves fun.

**Seed discipline:** roll patrol-wide Conditions from a **decorrelated seed** (`run_seed ^ <const>`,
like `outpost_name`), NOT the sector-gen `rng` — layouts must not shift when the roll is added. The
per-POI roll calls in `_gen_row_pois` run **unconditionally** so the enable flag never shifts the RNG
stream ([run_state.gd:765](../scripts/autoload/run_state.gd)); preserve that.

---

## 8. Open questions

- **Ordnance Disposal needs a new field.** Asteroids have `asteroid_bonus_bounty`; mines
  (`tether_mine`, `bomblet`) are `bounty_value = 0` with no bonus seam. Add a parallel
  `mine_bonus_bounty` (reset in `new_run`, in the save whitelist, read at mine death) — mirror the
  asteroid path exactly, incl. additive-with-events.
- **Player weapon-damage choke point.** Weak/Better Weapons need ONE place to scale outgoing player
  damage — weapons fire via several parts/paths. Cleanest: a `Run`-level `player_weapon_damage_mult`
  read where the player bullet's `damage` is set at spawn. Confirm there's a single such site (or add
  one) before building these two.
- **Repair cost model (blocks the repair pairs).** Repairs cost bounty + a charge, **no material**.
  Pick: **(a)** add a small baseline material cost so the matrix mirrors upgrades *(recommended)*, or
  **(b)** define Complex/Cheap Repairs as "adds/swaps" and accept Easy Repairs is near-baseline.
- **Charge economy is a separate axis.** Repair/restock are charge-limited (2d6 +1d6/boss) — a
  different lever than cost. A future Quartermaster (+charges) / Supply Shortage (−charges) pair
  lives there; out of scope for v1.
- **Speed-step edge case.** +1 rung on a tiny bullet can push its px/frame *ratio* past `TIER_MAX`
  (per-sprite strobe) even under the 480 ceiling — production already accepts this for faction mults,
  but eyeball the fastest chaff bullet at +1 rung / re-run `tools/clarity_audit.gd`.
- **Glass Patrol vs hull boons.** Glass Patrol makes hull quantity meaningless — Better Hull becomes
  cosmetic under it, and hull/ablative rolls are pulled. Either mutex them or let Glass Patrol win
  and have Curated grey the redundant boon. (Not a bug, just a clarity call.)
- **No-X stacking cap.** No Primaries + No Secondaries + No Modules = blaster-only. Legal and spicy,
  but the Wildcard roller may want a cap on how many No-X can co-roll so a random run isn't gutted.
- **Bosses** carry no Conditions today (`modifiers: []`). Patrol-wide probably apply; per-node skips
  bosses.
- **Hazard nodes** — most combat Conditions no-op there (no ships); Fast/Slow Enemies excludes hazard
  drift; Debris Fields is redundant; economy Conditions are hazard-agnostic. Define the no-op set.
- **Save/resume** — `active_conditions` (+ tiers) must persist (patrol-scoped). Add to the `run_save`
  whitelist alongside `sector_modifiers` / `asteroid_bonus_bounty`.

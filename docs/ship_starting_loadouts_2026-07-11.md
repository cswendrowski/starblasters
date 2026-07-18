# Per-Ship Starting Loadouts — (2026-07-11, rev 3)

**Status: BUILT 2026-07-11 (unplaytested).** Kits live in `ship_catalog.gd` `loadout`
entries, seeded by `Run._seed_default_loadout_snapshot` via `PartCatalog.make_part`;
verified headless by `tools/test_ship_loadouts.gd` (VERDICT: PASS). The corpo-hull squeeze
resolved via Option B: the **Corpo Shield Core** (`scripts/parts/corpo_shield_core.gd`) —
base 5 charges (+1/Mk, +2 @Mk.9 → 15 = half the vintage curve), regen 3.0s/0.6s at Mk.1 →
1.5s/0.35s at Mk.9 (min-wins alongside Shield Capacitor), rolls in the shop. Shield charges
are PART-DRIVEN now (`module_shield_base`, max-wins; player's hardcoded base-10 retired —
legacy pre-bay saves keep 10). Shop pricing: parts may override the flat 116+70/Mk curve
(`Part.shop_base_cost/shop_cost_per_mk`, offer + upgrade-fee sites) — vintage core
**520+140/Mk**, corpo core **380+90/Mk**. Companion doc:
`docs/ship_unlock_system_2026-07-11.md` (hull unlocks — still unbuilt).

## Current state (unchanged)

Every ship starts identical: `PartFactory.default_starting_loadout` = Main Engine + Energy
Blaster (CANNON) + Super Pulse Bomb (DEVICE_BAY_1) + Focus (SHIFT_MODE); `Run.new_run()`
seeds the meta-scene snapshot mirror + `modules = [ShieldCore Mk.1]` (run_state.gd:500).
`player.gd:489-508` applies defaults, then `Run.loadout_snapshot` slots + `Run.modules`
on top — Run's seeding is the one place a per-ship kit needs to land.

**Universal baseline (all ships, not counted in kit value):** Main Engine, Energy Blaster,
Super Pulse Bomb, Focus mode. Note outpost.gd:1367 assumes "Blaster at index 0 is
permanent / always owned" in cannon_pool — keep the Energy Blaster in every ship's pool
(index 0) and append the signature weapon as the ACTIVE one. That invariant also solves
the dry-metered-gun problem for free: a Falchion with an empty Minigun swaps (G) to the
blaster instead of flying unarmed.

## The kits (Roman 2026-07-11)

Design rule: kits mirror the hull's faction temperament — corpo = shielded/technical,
privateer = tough hull, no shields; zealot = no shields, extreme identities. Reaver stays
the weakest starting hull by design.

All modes DECIDED (Roman 2026-07-11) — G3 closed. Reaver gets Refire (it's objectively the
weakest starting hull); Weaver gets Hyper so it can auto-fire its missiles.

| Ship (faction) | Weapons (active first; blaster stays pooled) | Modules | Mode |
|---|---|---|---|
| **Reaver** (free hulls) | Energy Blaster only | Shield Core | **Refire** |
| **Wraith** (corpo) | Scatter Blaster (blaster family — unlimited ammo, W1 resolved) | Shield Core + shield module (pick: Backup Shield Capacitor / Shield Capacitor / Reflective Shield Tuning) + Thrusters (agility) | **Echo** |
| **Weaver** (corpo) | Energy Blaster + Seeking Missile secondary (HARDPOINT_WING, pre-equipped w/ seeded `secondary_ammo`) | Shield Core + shield module (pick as above) + Internal Micro Fabricator (4th item, decided — restocks the missiles) | **Hyper** (auto-fires the missiles) |
| **Cobra** (privateer) | Autocannon (`autocannon.tres`, metered) + Ammo Pods | 2 hull modules (propose Reinforced Hull + Repair Nanites) — **no Shield Core → shieldless** | Focus |
| **Falchion** (privateer) | Minigun (`minigun.tres`, metered) + Ammo Pods | 2 hull modules (propose Ablative Plating + Repair Nanites) — **shieldless** | Focus |
| **Stiletto** (zealot) | Energy Blaster only | Ablative Plating + **Reinforced Hull Mk.2** (decided — ram hull wants hull depth) — **shieldless ram hull** | **Rush** |
| **Pilgrim** (zealot) | **Twin Blaster Mk.2** (decided — more teeth) | Critical System De-Limiter + Overcharge Core — **shieldless glass cannon** (Overcharge's −1 shield charge is moot with no shield) | **Refire** |
| **Mongoose** (supremacy, added 2026-07-11; kit rev 2 same day) | **Heavy Blaster** (pool[0]) | Speed + crit build (Roman): Overclock Core Mk.2 + Targeting Computer Mk.2 + Thrusters Mk.2 | Focus |
| **Piercer** (supremacy, added 2026-07-11) | Twin Blaster (pool[0]) + Auto Laser (pool[1], active) — "dual blasters, dual lasers" | Reinforced Hull Mk.4 (the Stiletto's deep-hull setup; NOTE: adding its Ablative too would cost 860 — interpreted as RH only to stay on par) | **Rush** |
| **Hive** (prestige, added 2026-07-11) | Energy Blaster + **Combat Drones** secondary | Purely defensive drone fortress (Roman): Corpo Shield Core + Intercept Drones + Micro Fabricator + Repair Nanites | **Thief** (enemy fire → shield) |

**Hive budget exception:** the five named pillars can't fit 659 — a shield core alone is
396–536 effective. Wired at **≈976 effective** (corpo core + 4×116 + Thief) and treated
as PRESTIGE-PRICED: its 30-boss unlock (≥10 flawless full patrols) is the cost. The corpo
core is the mechanical pick (fast recharge = the sustain loop; Thief refills it mid-fight).
Vintage-core variant would be ~1116. Trimming to par would mean cutting two of Roman's
five pillars — rejected.

- Ammo Pods is a MODULE (module bay), listed under weapons above only because Roman paired
  it with the guns; it counts against the module bay (size 6).

## Mk.1 value tally / bounty budget

The shop prices EVERY offer (weapons, modules, shift modes — one pricing site,
outpost.gd:1397) at `116 + (Mk−1)×70`. So **Mk.1 item ≈ 116 bounty, +70 per Mk**; a
non-Focus starting mode counts as one item.

**Shield Core effective value ≈ ~536 (Roman's method, corrected 2026-07-11):** flat player
damage means 1 shield charge = 1 hull pip; Shield Core Mk.1 grants base 10 charges. The
hull-equivalent comparison starts from the base hull of 3 pips (2 + 1 danger pip): reaching
10 pips of durability via Reinforced Hull takes +7 pips = **RH Mk.7 = 116 + 6×70 = 536**.
That's a floor — the shield also refills at every level start (player.gd:891) + in-combat
ShieldRegenTimer, and it stacks ON TOP of your 3 hull pips rather than replacing them —
but close enough. (Ablative Plating similarly punches above its 116 — every 6th hull hit
ignored ≈ +17% effective hull.)

| Ship | Items beyond baseline | Shop cost | Effective (SC≈536) |
|---|---|---|---|
| Reaver | Shield Core, Refire | 232 | **652** |
| Wraith | Scatter Blaster, Shield Core, shield module, Thrusters, Echo | 580 | **1000** |
| Weaver | Seeking Missile, Shield Core, shield module, Micro Fabricator, Hyper | 580 | **1000** |
| Cobra | Autocannon, Ammo Pods, 2 hull modules | 464 | 464 |
| Falchion | Minigun, Ammo Pods, 2 hull modules | 464 | 464 |
| Stiletto | Ablative Plating, Reinforced Hull Mk.2, Rush | 418 | 418 (+ablative premium) |
| Pilgrim | Twin Blaster Mk.2, De-Limiter, Overcharge Core, Refire | 534 | 534 |
| Mongoose | Heavy Blaster, Overclock Core Mk.2, Targeting Computer Mk.2, Thrusters Mk.2 | 674 | 674 |
| Piercer | Twin Blaster, Auto Laser, Reinforced Hull Mk.4, Rush | 674 | 674 |
| Hive | Combat Drones, Corpo Shield Core, Intercept Drones, Micro Fabricator, Repair Nanites, Thief | 960 | **976 — prestige exception** |

## Par target ~659 (Roman 2026-07-11)

Direction: bring every ship to **~659 effective value** — i.e. par with the Reaver's 652.
"Reaver weakest" then means *fewest toys* (pure defense, zero offense/utility), not least
value; unlocked hulls differ in flavor, not power. Proposed kits (628–674, ±5% of par):

| Ship | Kit at par | Effective |
|---|---|---|
| **Reaver** | unchanged: Shield Core + Refire | 652 |
| **Wraith** | see corpo options below | 628–652 |
| **Weaver** | see corpo options below | 628–652 |
| **Cobra** | Autocannon **Mk.2**, Ammo Pods, Reinforced Hull **Mk.3**, Repair Nanites | 674 |
| **Falchion** | Minigun **Mk.3** (signature gun deep), Ablative **Mk.2**, Repair Nanites, Ammo Pods | 674 |
| **Stiletto** | Ablative Mk.2, Reinforced Hull **Mk.4**, Rush | 628 (+ablative premium ≈ par) |
| **Pilgrim** | Twin Blaster **Mk.3**, De-Limiter, Overcharge **Mk.2**, Refire | 674 |

**The corpo problem:** Shield Core alone is 536 of the 659 — a full-shield corpo hull has
room for exactly ONE more 116 item. Two ways out:

- **Option A — no new parts:** each corpo hull = Shield Core + its single signature item,
  Focus mode. Wraith = SC + Scatter Blaster (652; "agile" moves into the hull's base
  handling stats instead of a Thrusters part). Weaver = SC + Seeking Missile (652; loses
  Hyper auto-fire + Fabricator — missiles restock at shops only). Preserves full shields,
  guts the kit personality.
- **Option B — one new part, "Compact Shield Core" (RECOMMENDED):** a corpo-surplus
  half-core at **5 charges**. Value: base hull 3 → 8 pips of durability = RH Mk.5 = **396**.
  That buys back two kit slots: **Wraith** = Compact SC + Scatter Blaster + Echo **(628)**
  (or Thrusters instead of Echo); **Weaver** = Compact SC + Seeking Missile + Hyper
  **(628)** — the auto-firing-missiles fantasy survives. Fits the fiction (mass-produced
  corpo hardware) and gives the shop a mid-tier shield rung as a bonus. Build note: the
  base-10 charge count currently lives in `player.apply_run_upgrades`, not the part — it
  needs to become part-driven (a `base_charges` the module supplies) for a 5-charge
  variant to exist.

Residual notes: Ablative/RH punch above sticker (every-6th-hit ≈ +17% hull), so the
Stiletto's 628 is effectively at or above par. Playtest arbitrates the last ±5%; the
lever stays Mk bumps.

## Open items

- **Hull-module picks** for Cobra/Falchion are proposals (pool: Reinforced Hull, Ablative
  Plating, Repair Nanites) — any pair works mechanically.
- ~~G3 modes~~ RESOLVED 2026-07-11: Reaver Refire, Wraith Echo, Weaver Hyper, Cobra Focus,
  Falchion Focus, Stiletto Rush, Pilgrim Refire. (Hyper/Echo being shop items elsewhere is
  accepted.)
- ~~W1 Scatter Blaster ammo~~ RESOLVED: blaster family, unlimited ammo.

## Implementation sketch

1. **Data:** `loadout` key per ShipCatalog entry:
   `{"cannons": ["res://resources/weapons/minigun.tres"], "secondary": "...", "modules": [["shield_core", 1], ["thrusters", 1]], "mode": "rush"}`
   (module entries carry a Mk for the budget bumps). Energy Blaster is implicit at pool
   index 0 (outpost invariant). Absent key = current defaults.
2. **One seeder, ship-aware:** `Run._seed_default_loadout_snapshot()` + the modules seed
   read `ShipCatalog.get_ship(ship_variant).loadout`. `PartFactory.default_starting_loadout`
   stays the generic no-Run fallback (dev scenes); the live player already lets
   snapshot/modules override it.
3. **Ordering fix:** `patrol_start._on_begin_pressed` calls `new_run()` (which seeds) before
   writing `ship_variant` — re-seed after the write (`apply_conditions` already re-seeds for
   condition gates; verify the no-conditions path also re-seeds, else add an explicit call).
4. **Secondary ammo:** pre-equipped secondaries need `Run.secondary_ammo` seeded the way
   `equip_part` does for HARDPOINT_WING parts.
5. **Surface it:** derive the patrol-start left panel + codex armament/module lines from the
   loadout data so flavor can't drift from mechanics. Update the codex strings where the old
   flavor no longer matches (e.g. Cobra's "auto-lasers" → autocannon).
6. **Verify:** parse + headless boot; per-ship smoke = force each variant, boot combat,
   assert cannon/module/mode identity (small tools/ script walking all 7).

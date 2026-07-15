# Per-Ship Starting Loadouts — scoping (2026-07-11, rev 2)

**Status: PROPOSAL — nothing built.** Rev 2 replaces the codex-string mapping with Roman's
faction-aligned kits (2026-07-11) + the Mk.1 value tally. Companion doc:
`docs/ship_unlock_system_2026-07-11.md` (hull unlock via cross-run kill counts).

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

Reading: on effective value the shielded corpo hulls sit ~2× the shieldless ones, with the
Reaver in between at 652 (652 of pure defense — it has the durability floor but nothing
else, which is what "weakest playable start" means in practice). That gap IS
the faction identity (corpo = protected/technical, privateer/zealot = tough-or-glass, you
feel the hits). The shieldless kits compensate with offense/utility, and Ablative/RH are
themselves worth more than sticker. If playtest says the gap is too wide, the lever is Mk
bumps on the shieldless kits (each +70 shop / more in effect), not adding Shield Cores.
Reaver remains the weakest playable START (one defensive item + Refire) by design.

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

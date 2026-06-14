# 04 · Player, Parts & Economy

This doc covers the **player ship**, **upgrade system** (`Part`s), and the **economy** (bounty, shop, pricing). Read this when you're tuning damage numbers, adding a new upgrade, or changing shop costs.

---

## The Player Ship

### Stats start at zero — Parts populate them

All player statistics begin at zero. The ship has no hardcoded fire rate, damage, speed, or hull — every stat comes from the **Parts** you equip via `PlayerLoadout`.

When the player starts a run, `player.gd` loads a default starting loadout (main engine, energy blaster cannon, smart bomb super, Focus shift-mode) and then layers on any Parts the player bought from the shop between scenes. So a ship with no parts would have zero speed and zero damage — it wouldn't be able to move or shoot. This design lets Parts be purely **additive**: when you equip a Part, you add to the ship's stats; when you remove it, you subtract.

Read `scripts/game/player.gd` to see the stat declarations:
- `speed` (pixels/second, affected by `speed_multiplier`)
- `cooldown` (seconds between shots)
- `bullet_damage` (damage per bullet)
- `max_shield` (HP pool) and `shield` (current)
- `max_hull` (pip count) and `hull` (current)
- And ~40 more for spread fire, secondary ammo, beams, drones, etc. (see lines 14–156 for the full list).

### Shield is an HP pool; Hull is pips

**Shield** ([`scripts/game/player.gd:166–190`](https://github.com/TODO)) is a **rechargeable HP pool**. When you're hit:
- If shield > 0: the hit is absorbed fully by the shield (no overflow to hull). Short i-frame of 0.1 seconds so sustained fire drains it normally.
- If shield = 0: the next hit damages hull (1 pip) and triggers a 0.6-second i-frame.

Shield recharges slowly: 5-second delay after a hit, then 1 point/second until full.

**Hull** is **pip-based** (default 3 pips). Each hit when shield is empty costs 1 pip. At 0 pips, the pips flash; the next hit fires a smart bomb (if you have charges) or kills the ship.

### The damage model — scaling and tells

Each time you take damage, `take_damage(amount)` applies two modifications:

1. **Sector difficulty scaling** ([`scripts/game/player.gd:680–687`](https://github.com/TODO)):
   ```
   incoming_damage = incoming_damage × (1 + 0.05 × sectors_cleared)
   ```
   By sector 3, every hit does ~15% more damage. This is applied BEFORE shield/hull absorption.

2. **Dangerous sector modifier**: if the sector is marked "dangerous", all incoming damage is doubled (in addition to the scaling above).

**Damage tells** — visual cues that you're hurt — appear once you take any hull damage ([`scripts/game/player.gd:360–376`](https://github.com/TODO)):
- Engine torch: procedural fire on the nozzle (leans opposite your movement direction)
- Damage smoke trail: drifting smoke puffs

Both activate at `activate_below = 0.01`, meaning any pip loss triggers them. The comment says "even losing 1 of 3 pips (damage_level ≈ 0.33) triggers the effects," so they're aggressive tells early on, not gated to 50%.

### Signals your code can listen to

When building UI or special effects, hook these signals on the Player node:

| Signal | Signature | Emitted when |
|--------|-----------|--------------|
| `shield_changed` | `(max_shield: int, current_shield: int)` | Shield value changes (hit or regen) |
| `hull_changed` | `(max_hull: int, current_hull: int)` | Hull pips change |
| `damaged` | `(amount: int)` | Damage was applied (amount=0 if shield absorbed it, 1 if hull was hit) |
| `died` | none | Ship died |
| `ammo_changed` | `(value: int)` | Primary weapon ammo count changed |
| `secondary_ammo_changed` | `(value: int, maximum: int)` | Secondary weapon ammo changed |
| `super_charges_changed` | `(value: int, maximum: int)` | Smart bomb or super weapon charges |
| `focus_charge_changed` | `(charge: float, max_charge: float)` | Focus-mode charge (precision slowdown) |

See `scripts/game/player.gd` lines 3–9 and 78, 146, 228, 248 for the exact definitions.

---

## Parts (Ship Upgrades)

### What is a Part?

A **Part** is a `Resource` that augments the player's ship. It has:
- A **slot** it plugs into (ENGINE, CANNON, SHIELD, HARDPOINT_WING, DEVICE_BAY_1, etc.)
- A **Mk (Mark)** from 1–9, scaling its power
- `apply(ship)` — mutates the ship's stats when equipped
- `unapply(ship)` — reverses the mutation when unequipped

Parts are swappable during a run via the outpost. When you swap a Part, the old one calls `unapply()` to undo its changes, then the new one calls `apply()` to add its bonuses. This is why the delta-recording pattern matters: it guarantees clean reversals.

### The slot system

Each ship has **10 slots** (see `scripts/weapons/SlotTypes.gd`):

| Slot | Purpose | Example Part |
|------|---------|--------------|
| ENGINE | Movement speed | `BasicEngine` (Mk scales speed bonus) |
| CANNON | Primary weapon | Energy Blaster, Machinegun, Rotary Laser |
| SHIELD | Hull protection | (reserved — shield upgrades moved to the Outpost Mk system; no part targets this slot) |
| WING_LEFT, WING_RIGHT | — | (reserved — early per-slot design, replaced by the Outpost Mk upgrade system; no part targets these) |
| TAIL | — | (reserved — same as the wing slots; no part targets it) |
| HARDPOINT_WING | Secondary weapon | Seeking Missile, Rocket Pod, Particle Beam |
| HARDPOINT_WINGTIP | Alternate secondary | (expansion slot) |
| DEVICE_BAY_1, DEVICE_BAY_2 | Super (panic button, X) | Smart Bomb — the **only** super |
| SHIFT_MODE | Shift stance (Shift) | Focus (default), Phase, Hyper — `ModePart`s; one occupies the slot, swapped at outposts. See `docs/shift_mode_system_2026-06-08.md`. |

A Part's `slot_type` is set in its `_init()` — if you get this wrong, the shop won't route it to the right slot.

### The apply/unapply pattern — why delta recording?

Here's `BasicEngine` ([`scripts/parts/basic_engine.gd`](https://github.com/TODO)):

```gdscript
extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

@export var speed_bonus: float = 200.0

var _applied: float = 0.0

func _init() -> void:
    slot_type = Slots.SlotType.ENGINE
    display_name = "Main Engine"
    description = "Stock thrusters. Base maneuvering."

func apply(ship) -> void:
    var bonus := speed_bonus * mark_multiplier()
    ship.speed += bonus
    _applied = bonus  # Record what we added

func unapply(ship) -> void:
    ship.speed -= _applied  # Reverse the exact amount
    _applied = 0.0
```

Notice: `_applied` stores the **exact value added** in `apply()`. When `unapply()` runs, it subtracts that stored value. This is critical because:

1. **Mk matters**: Mk.1 adds `200`, Mk.5 adds `1000`. If you just subtracted the `@export` value, you'd leave the ship in a broken state.
2. **Stacking upgrades**: if the player equips Engine → upgrades it → swaps it, the old Mk is cleanly reversed before the new Mk is applied.
3. **No side effects**: the delta record means `unapply()` is always the precise inverse, even if the ship's stats were modified by other Parts between `apply()` and `unapply()`.

The base `Part` class provides `mark_multiplier()` which returns `float(mark)` — so Mk.1 = 1.0x, Mk.9 = 9.0x. Some weapons override this (e.g. `wave_gun_cannon` uses non-linear scaling).

### Mk.1–9 scaling

Every Part scales linearly with its Mark: `Mk = 1` is 1× the base value, `Mk = 9` is 9×. The formula is:

```
effective_value = base_value + (mark - 1) * per_mark_increment
```

For a weapon with `base_damage = 10` and `dmg_per_mark = 5`:
- Mk.1: 10 + 0 × 5 = 10
- Mk.5: 10 + 4 × 5 = 30
- Mk.9: 10 + 8 × 5 = 50

The `Part` base class provides `effective_damage(at_mark)` to compute this for weapons (see `scripts/parts/part.gd:25–36`). For non-weapon parts, return -1 so the weapon editor knows to skip it.

---

## The Economy & Shop

### Bounty — the currency

**Bounty** is earned by killing enemies (each enemy grants bounty on death). It's the only currency. You spend bounty to:
- Buy weapon cards (cannons, secondaries, supers)
- Buy upgrade cards (hull capacity, shield, thrusters, etc.)
- Repair hull at the outpost
- Refill ammo (machinegun, secondary, super charges)
- Refresh the weapon/upgrade stock (reroll cards)

Bounty is saved between sectors, so you can accumulate it across a run and make larger purchases later.

### Weapons column pricing

The outpost rolls **5 weapon cards** each visit, weighted:
- 50% CANNON (primary weapon)
- 25% HARDPOINT_WING (secondary weapon)
- 25% DEVICE_BAY_1 (super/special ability)

Weapon prices are:
```
CANNON_BASE_COST := 116
CANNON_COST_PER_MK := 70
```

So a cannon at Mk.X costs: `116 + (X - 1) × 70`
- Mk.1: 116 bounty
- Mk.5: 116 + 4 × 70 = 396
- Mk.9: 116 + 8 × 70 = 676

See `scripts/screens/outpost.gd:56–57` for the exact constants.

### Upgrades column pricing

The outpost rolls **3 upgrade cards** (hull, thrusters, shield, self-repair, hull plating). Upgrade prices are:

```
UPGRADE_BASE_COST := 140
UPGRADE_COST_PER_MK := 70
```

Per upgrade: `140 + (next_mk - 1) × 70`
- Mk.1→2: 140 + 0 × 70 = 140
- Mk.5→6: 140 + 4 × 70 = 420
- Max is Mk.9

See `scripts/screens/outpost.gd:27–38` and `36–37` for the upgrade list and costs.

### Services (hull repair, ammo refill, etc.)

**Hull repair** ([`scripts/screens/outpost.gd:39`](https://github.com/TODO)):
```
HULL_REPAIR_COST := 250
```
Restores 1 hull pip for 250 bounty. Multiple purchases allowed, up to `max_hull`.

**Ammo refill** — two paths:
- **Primary (Machinegun) refill**: `PRIMARY_REFILL_COST := 100` bounty refills the active cannon's magazine to full. Energy Blaster (infinite ammo) greys out the button.
- **Secondary ammo refill**: scales by rounds missing. `AMMO_COST_PER_ROUND := 1.0`, so refilling a 60-round secondary from 0 costs 60 bounty; from 30 costs 30. Partial refills allowed if you can't afford full.

See `scripts/screens/outpost.gd:46–51` and the `_on_primary_ammo_refill()` / `_on_secondary_ammo_refill()` methods for the logic.

**Super charges**: `SUPER_REFILL_COST := 120` per charge. No auto-refill — you **pay** to keep them topped up. This makes supers a real economy decision (is 120 bounty worth firing the super now, or should I save for a weapon upgrade?).

**Refresh stock** ([`scripts/screens/outpost.gd:58–62`](https://github.com/TODO)):
```
REFRESH_BASE_COST := 10
REFRESH_MAX_DOUBLINGS := 7
```
First refresh costs 10 bounty. Second costs 20 (10 << 1). Third costs 40 (10 << 2). Caps at 10 << 7 = 1280 bounty to prevent runaway inflation. The cost resets on the next outpost visit.

---

## Walkthrough: Add a new Part

Here's end-to-end how to add a new Part to the game. We'll add a fictitious **Overcharge Capacitor** that boosts damage.

### 1. Create the script

Create `scripts/parts/overcharge_capacitor.gd`:

```gdscript
extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

@export var damage_bonus: int = 2

var _applied: int = 0

func _init() -> void:
    slot_type = Slots.SlotType.DEVICE_BAY_2  # or whichever slot fits
    display_name = "Overcharge Capacitor"
    description = "Amplifies weapon output. Mk.1: +2 damage. Mk.9: +18 damage."

func apply(ship) -> void:
    var bonus := int(damage_bonus * mark_multiplier())
    ship.bullet_damage += bonus
    _applied = bonus

func unapply(ship) -> void:
    ship.bullet_damage -= _applied
    _applied = 0
```

**Key points:**
- Extend `Part` (from `scripts/parts/part.gd`).
- Set `slot_type` in `_init()` to the intended slot (see the SlotTypes enum above).
- `apply()` adds to the ship's stat (here, `bullet_damage`) and **records the delta** in `_applied`.
- `unapply()` subtracts that delta and resets `_applied`.
- `mark_multiplier()` is provided by the base class and returns `float(mark)` (1.0 for Mk.1, 9.0 for Mk.9).

### 2. Register it in PartFactory

Open `scripts/parts/part_factory.gd` and add your Part to the imports and/or the factory methods that build the shop. If it's a device-bay item, check how `SmartBomb` is registered. If it's a weapon, check `BasicBlasterCannon`.

Example (in `part_factory.gd`):

```gdscript
const OverchargeCapacitor = preload("res://scripts/parts/overcharge_capacitor.gd")

# ... in the method that builds device-bay offers:
var part = OverchargeCapacitor.new()
part.mark = chosen_mk  # Mk.1–9 rolled by the shop
```

See `scripts/parts/part_factory.gd` for the current registration points. If unsure, check `scripts/parts/part_catalog.gd` — it maintains the master list of all buyable Parts and how they're weighted in the shop.

### 3. Set the Mk limit and cost

The outpost will price your Part using the formula:
```
cost = BASE_COST + (mk - 1) × COST_PER_MK
```

If your Part should be a weapon (CANNON, HARDPOINT_WING, DEVICE_BAY_1), it uses `CANNON_BASE_COST` and `CANNON_COST_PER_MK` (see `scripts/screens/outpost.gd:56–57`). If it's a passive upgrade (WING, TAIL, etc.), check if the outpost has a separate category or if it defaults to weapon pricing.

The Mk limit is typically `MAX_MK := 9` (see `scripts/screens/outpost.gd:38`). The shop rolls Mk values up to `sector_index + 3` with weighting that favors the middle of the range (`scripts/screens/outpost.gd:63–65`).

### 4. Test the Part

- Load a dev scene (e.g., the **Hangar** from the dev menu) that spawns the player with a shop UI.
- Manually equip your Part in the loadout and verify that `apply()` is called and the stat changes.
- Swap it out (or reload the scene) and verify that `unapply()` cleanly reverses the change.
- Check the player's speed, damage display, and behavior.

To verify via headless boot:
```
godot --path . --headless --quit-after 2
```
This catches GDScript parse errors that a live editor might hide.

### 5. Balance & iteration

For numeric tuning (damage per Mk, cost, etc.), see:
- **`docs/economy_2026-05-24.md`** — full economy analysis (costs, inflation curves, decision trees).
- **`docs/weapon_mk_progression_2026-05-25.md`** — weapon scaling guidelines (e.g. when to cap DPS, how to scale secondary ammo).

If your Part changes fundamental ship mechanics (like a new secondary fire mode), document it in a comment block in the Part's `apply()` method so the next contributor understands the intent.

---

## Coordination with related systems

- **Weapons & bullets** — when your Part equips a cannon, it sets `ship.bullet_scene` and `ship.bullet_damage`. See [Doc 05 → Projectiles](05-projectiles-effects-visuals.md) for how bullets inherit those values.
- **Damage/VFX** — when the player's `hull_changed` signal fires, HUD elements and damage tells respond. See [Doc 05 → Effects](05-projectiles-effects-visuals.md) for the effect helpers.
- **Enemy tuning** — if your Part makes the player overpowered, enemies scale their HP/spawn rate. That's in [Doc 03 → Combat & Waves](03-combat-waves-enemies.md).
- **Coordinate space** — if your Part spawns visual effects (drones, beams), use `scripts/systems/playfield.gd` for bounds. See [Doc 02 → Architecture](02-architecture.md).

---

## Quick lookup: key files

| File | What's there |
|------|--------------|
| `scripts/game/player.gd` | All player stats, signals, damage logic, shield/hull mechanics. |
| `scripts/parts/part.gd` | `Part` base class. Read this first. |
| `scripts/parts/basic_engine.gd` | Simplest Part example — study this to understand the pattern. |
| `scripts/parts/part_factory.gd` | How Parts are instantiated and registered. |
| `scripts/parts/part_catalog.gd` | Master list of buyable Parts and shop weights. |
| `scripts/weapons/loadout.gd` | `PlayerLoadout` — manages equip/unequip and calls apply/unapply. |
| `scripts/weapons/SlotTypes.gd` | Slot enum (ENGINE, CANNON, SHIELD, etc.). |
| `scripts/screens/outpost.gd` | The shop UI, pricing, services. Start at line 27 (UPGRADES const) or line 56 (weapon pricing). |
| `docs/economy_2026-05-24.md` | Design doc for pricing and economic balance. |
| `docs/weapon_mk_progression_2026-05-25.md` | Scaling guidelines for weapons across Mk levels. |

---

*Return to:* [Contributing README](README.md)

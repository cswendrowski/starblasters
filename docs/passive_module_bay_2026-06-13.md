# Passive-Module Bay — implementation plan (2026-06-13)

Realizes the REMAINING "PASSIVE-MODULE layer" from `docs/supers_modes_modules_2026-06-05.md`
(§2, §12–15) + `TODO.md` items A–E. The SHIFT_MODE slot is the proven precedent for the
whole pattern. **Decisions locked with Roman 2026-06-13:** reify the defensive systems (not
present-only), and **6 bay slots** — Shield Core auto-takes one, leaving 5 to play with (or 6
if you drop shields for a glass-cannon build).

> **Note (2026-07-11):** the shipped bay is `MODULE_BAY_SIZE = 6` (`run_state.gd`). The
> "≤5" figures in the plan sections below predate the 6-slot lock above — trust the code.

## The one open architectural decision (resolved here)

A bay holds **up to 5 modules, any module in any slot** — but the existing loadout keys ONE
part per slot int (`loadout.gd` `_parts[slot] = part`; `equip(slot, part)` validates
`part.slot_type == slot`). A module's `slot_type` is a single value, so it can't naturally sit
in "any of 5 slots."

**Resolution — a list-backed bay, not 5 scattered slots.** Add ONE `MODULE` slot type. The bay
is a dedicated `Run.modules: Array` (≤5) + a parallel `loadout` path that applies/unapplies each,
instead of 5 `MODULE_BAY_1..5` enum singletons. This keeps modules fully interchangeable and
matches how a roguelite bay actually behaves (a list you add to / swap within). It's a small,
contained loadout extension rather than 5 enum hacks + slot-reassignment-on-equip.
- `SlotTypes.SlotType.MODULE` (single new enum value) — every module Part uses it.
- `Run.modules: Array[Part]` (≤ MODULE_BAY_SIZE = 5), persisted in `_SAVE_FIELDS` + the RunSave mirror.
- `loadout.apply_all` also iterates `Run.modules` and calls each module's `apply(ship)`.
- Equip/unequip = append/remove on the array (bounded to 5) + re-apply. The bay UI drives it.

(The alternative — 5 `MODULE_BAY_1..5` enum slots — is viable but forces slot-assignment logic on
equip and 5 display rows hard-keyed to indices. The list is cleaner; revisit if Roman prefers fixed slots.)

## Reify approach — ADDITIVE + default-safe (no regression to existing saves)

Every module effect is gated so that **no module equipped = today's exact behavior**. The default
loadout equips Shield Core, and a pre-bay save (no `modules` field) is treated as Shield-Core-present.
So existing runs/saves are unchanged; only *opting into* modules changes anything. This is what makes
the refactor safe to land without a playtest breaking survival systems.

- **Shield Core** gates the shield. `player.apply_run_upgrades()` (`player.gd:2477-2479`) keeps the
  `shield_cap_mk` capacity formula, then: `if not _has_shield_core(): max_shield = 0`. `_has_shield_core`
  reads `Run.modules` (back-compat: empty/absent bay → true). Drop the Core → `max_shield = 0` = glass cannon.
  `shield_cap_mk` STAYS an Upgrade scaling the Core's capacity (spec §12).
- **Repair Nanites / Ablative Plating** (later): same pattern — the module's presence gates the existing
  `self_repair_mk` (regen, `sector_map_v3.gd:196`) / `hull_plating_mk` (`player.gd:2473`) effect. Ablative
  also flips RNG-shrug → deterministic every-Nth (spec §15) as part of the reify.

## Wiring (mirror SHIFT_MODE — the equip plumbing is otherwise slot-generic)

| Stage | File | Change |
|---|---|---|
| Slot enum | `scripts/weapons/SlotTypes.gd` | add `MODULE` + `slot_name` case |
| Base class | `scripts/parts/module_part.gd` (NEW) | extends `part.gd`; `module_id`; `apply/unapply` mutate ship (default-safe); Mk |
| Bay state | `scripts/run_state.gd` | `modules: Array` + `MODULE_BAY_SIZE=6`; reset in `new_run`; seed default Shield Core; `_SAVE_FIELDS` + RunSave mirror; equip/unequip helpers |
| Loadout | `scripts/weapons/loadout.gd` | `apply_all` also applies `Run.modules` |
| Catalog | `scripts/parts/part_catalog.gd` | preloads + roll-pool entries (Shield Core default-only, like Focus) + factory dispatch |
| Defaults | `scripts/parts/part_factory.gd` | default loadout includes Shield Core in the bay |
| Player | `scripts/player.gd` | `_has_shield_core` + the `max_shield` gate; `module_damage_mult` read in the fire path (`~1549`); on-kill shield siphon hook; `module_*` fields default to no-op |
| Manage Ship | `scripts/manage_ship.gd` | a MODULES column/section: list equipped (≤5) + Equip-from-owned + Unequip |
| Outpost | `scripts/outpost.gd` | offer modules in the shop (`WEAPON_SLOT_WEIGHTS` + `roll_for_slot`); `_slot_short_name`/`_slot_color` MODULE cases |
| HUD | `scripts/ui.gd` | a small equipped-modules icon strip (net-new; static icons) |
| Strings | `scripts/strings.gd` / `armory_strings.gd` | module names + codex blurbs |

## Module roster

**BUILT (18, 2026-06-13 → 06-14). Bay size = 6.**
- **Shield Core** *(default)* — gates the shield AND its Mk now drives capacity (base 10 + 2/Mk + 4 at Mk.9 → 30; the old shield_cap upgrade folded in). Drop = glass cannon.
- **Overcharge Core** — +damage % (fire path `module_damage_mult`), −1 max shield charge. Pure stat; default-safe.
- **Siphon Core** — kills restore a sliver of SHIELD charge (NEVER Mode Energy — spec §8 runaway lever). One kill hook.
- **Repair Nanites** — gated in-combat hull regen tick (`module_regen_interval`), capped at max−1.
- **Ablative Plating** — deterministic every-Nth hull-hit absorb (`module_ablative_n`).
- **Targeting Computer** — primary crit chance (`module_crit_chance`, ×2 dmg) + a purple HDR bolt tint on crit.
- **Overclock Core** — sustained-fire rate ramp (`module_overclock_max`; ramp/decay on the player), resets on release.
- **Critical System De-Limiter** — fire-rate + damage scale with hull lost, peaking at 1 hull (`module_delimiter_max`, `_delimiter_bonus()`). (was "Adrenal Surge".)
- **Reinforced Hull** — +max_hull pips (`module_hull_bonus`, up to +8) + Mk.9 repair discount. (the old Hull upgrade.)
- **Thrusters** — +move speed % (`module_speed_pct`). (the old Thrusters upgrade.)
- **Shield Capacitor** — lower shield-regen delay + faster per-charge tick (`shield_regen_delay`/`shield_regen_interval`).
- **Intercept Drones** *(2026-06-14)* — migrated off the HARDPOINT_WING secondary to a module. Spinning ablative drones soak bullets; spawn at combat start, respawn each level, gone once destroyed (`intercept_drones.gd`, reuses `shield_drone.tscn`).
- **Backup Shield Capacitor** *(06-14)* — first shield drop per level restores 5%/Mk of max shield (`module_backup_shield_pct`, `_backup_cap_used` once-per-level latch in the take_damage shield branch).
- **Reflective Shield Tuning** *(06-14)* — every Nth absorbed bullet bounced back at the nearest enemy (`module_reflect_n`, `_reflect_bullet`); N: 6 at Mk.1 → 2 at Mk.9.
- **Internal Micro Fabricator** *(06-14)* — clearing a level restocks 5%/Mk of max primary+secondary ammo (`module_ammo_restore_pct` → `Run.restock_ammo_fraction` in `_on_level_cleared`).
- **Passive Energy Routers** *(06-14)* — while the trigger is idle, shield-regen delay + interval cut by 20%→60% (`module_energy_router_pct`, `_effective_regen_*`, off `_shot_recency`).
- **Blaster Smart Mount** *(06-14)* — auto-turrets the Blaster onto enemies in a 120° arc; manual Primary stays; Q-locked. Direct-spawn turret (`module_blaster_*`, `_update_blaster_mount`).
- **Primary Smart Mount** *(06-14)* — auto-turrets the Primary (real fire_primary pipeline + aim); manual Blaster stays; regen lasers wait for full recharge; Q-locked (`module_primary_*`, `_update_primary_mount`). Both mounts = fully hands-off.

**Upgrades retired entirely (2026-06-13):** hull/thrusters/shield-capacity are the modules above; the
outpost UPGRADES column was removed (parts column widened + renamed "PARTS"); Manage-Ship upgrade list
emptied; the Salvage Cache "upgrade" outcome now grants a random MODULE. Run int fields kept for save compat.

**Smart Mount feel — first-pass numbers, NEEDS PLAYTEST TUNING (Roman, 2026-06-14):** turret traverse
(2.5→6.1 rad/s by Mk), dispersion (~10°→2° by Mk), 120° arc, 240px acquisition range, ~8° fire tolerance
all live in `smart_mount.gd` + the `MOUNT_*` consts in `player.gd`. Known v1 limits: Pulse Laser (hitscan)
+ minigun-hitscan fire axially (the bullet-spawn path takes the aim; their bespoke paths don't yet); a
non-regen metered primary that runs dry under the turret snaps to the blaster as usual.

**Cut/hold** (spec §15 + later calls): Auto-Dodge, Scavenger (→Upgrade), Reflector/Thorns, Last Stand,
Threat Sensor, Piercing Core, Auto-Turret, and **Tractor Coil** — CUT 2026-06-13: it auto-collects/pulls
*pickups*, but the game has no pickup system (bounty is awarded directly on kill), so it has nothing to do.

## Build order
1. **Foundation** — `MODULE` enum, `module_part.gd`, `Run.modules` + save + loadout apply. (Low-risk, parse-verifiable.)
2. **Shield Core + the gate** (+ back-compat + a headless equip/unequip→max_shield test). The reify headline.
3. **Overcharge + Siphon** (fire-path mult + kill hook; default-safe).
4. **Bay UI** — manage_ship + outpost + HUD strip.
5. **Verify** — parse + boot; a new `tools/test_module_bay.gd` (equip/unequip → max_shield, damage mult, siphon, save round-trip); ship-skill boot.
6. The tail modules + full Repair/Ablative reify = Increment 2 (needs Roman's playtest on feel).

## Verification / risk
Default-safe guards mean existing saves + the no-module path are unchanged (headless-verifiable). The
NEW module *feel* (glass-cannon balance, Overcharge/Siphon tuning) is playtest-only — flag for Roman.
RunSave round-trip of `Run.modules` is the one save-compat item to test explicitly.

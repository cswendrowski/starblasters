# Weapon data: single source of truth (.tres) — 2026-06-11

Centralized weapon stats so there's one authority per weapon, ending the prior
split where a stat could live in both the script `_init()` and the `.tres` with the
`.tres` silently winning (Energy Blaster: script `0.22`, `.tres` `0.15`).

## The model

- **Stats → the `.tres`** (`resources/weapons/<name>.tres`). This is the single
  source of truth for every tunable value: `base_damage`, `dmg_per_mark`,
  `base_cooldown`, `base_ammo`, `ammo_recharge_rate`, `refill_cost_override`,
  `no_outpost_refill`, `bullet_scene`, and weapon-specific stat `@export`s.
- **Behavior + curve shape → the script** (virtual methods + `_mk_knobs()` + bespoke
  curve methods). These work for both `.new()` and `.tres`-loaded instances.
- **Identity → the script** (`display_name`, `description`) via `_init()`, re-stamped
  onto loaded weapons by `PartCatalog._build_weapon` (the `.tres` deliberately stores
  these empty). `slot_type` is now persisted in the `.tres`.
- **`_init()` no longer sets stat values.** Godot doesn't run `_init()` on a
  disk-loaded resource, so any stat literal there was dead-but-misleading for every
  `.tres` weapon. Those assignments are removed; each script's `_init()` keeps only
  identity + a `# Stats live in <name>.tres` pointer.

`_build_weapon` now **errors loudly** (`push_error`) if a pooled weapon's `.tres` is
missing — a missing `.tres` yields a schema-default (often zero-stat) weapon, which
is a packaging bug, not a silent fallback.

## Authoring a new weapon (updated)

1. Script: extend the right base (`primary_weapon` / `metered_primary` /
   `bullet_secondary` / …), set `display_name`/`description` in `_init()`, override
   the behavior virtuals + `_mk_knobs()` curve **shape**. Do NOT set `base_damage`
   etc. in `_init()`.
2. `.tres`: create `resources/weapons/<name>.tres` with the stat values (the Weapon
   Lab / a hand-authored resource). This is where the numbers live.
3. Register in `PartCatalog._make_by_name` via `_build_weapon(<tres>, <Script>, <bullet>)`.
4. Run the guard: `godot --headless -s res://tools/validate_weapon_data.gd` → must
   print `VERDICT: PASS`.

## Validation guard

`tools/validate_weapon_data.gd` asserts, for every pooled weapon:
1. its `.tres` exists,
2. no `.tres` field is stale (every persisted key maps to a live script property),
3. it builds and resolves `_mk_knobs()` with a valid `slot_type`.

Run it after any weapon change (and consider wiring it into `parse_check`).

## Known remaining layer (clean, optional follow-up)

A handful of stat values still live as `@export` **declaration defaults** in the
scripts rather than in the `.tres` — these are fields whose current value equals the
`@export` default, so `ResourceSaver` omitted them (e.g. `cooldown_at_mk9`,
`damage_at_mk9`/`bullet_speed_at_mk*` on Wave Gun, `base_dps`/`base_width` on Particle
Beam, `base_drones`/`base_hits` on Intercept Drones, `base_charges` on Smart
Bomb/Combat Drones, `base_bullet_count`/`spread_degrees` on Spread). This is the
standard Godot **schema-default + data-override** model — there is no *competing*
value, so the "two sets, one silently overriding" problem is fully resolved. If a
fully-explicit `.tres` (every stat visible in the data file, `@export` defaults
neutralized) is wanted, that's a clean follow-up: neutralize the declaration defaults
and write the values into each `.tres`.

Two weapons additionally encode their curve **shape** in hardcoded method constants
(Auto Laser `_cooldown_for_mark` `0.162`, `ammo_at_mark` `200 + 30·mk`) — that's
behavior, not a tunable stat, and stays in code by design.

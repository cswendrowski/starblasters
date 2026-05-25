extends "res://scripts/parts/part.gd"

# WeaponPart — declarative Mk-scaling base for every primary/secondary
# weapon. Subclasses declare what knobs to write into the ship + how they
# scale per Mk; the base handles snapshot/restore so re-equipping never
# leaks stale stats from a previously equipped weapon (CLAUDE.md "no
# silent fallbacks" + the round-trip rule).
#
# Subclass contract:
#   - Override _mk_knobs() → {"ship_field": [mk1, mk9]} | {"ship_field": Callable(self, "_picker_method")}
#     The Callable receives (mark:int) and returns the value. Use for
#     non-linear cases (e.g. Wave Gun's bullet_scene switch at Mk.5).
#   - Override _snapshot_keys() to declare additional ship fields _apply_visuals
#     writes. Keys in _mk_knobs() are auto-included; no need to repeat.
#   - Override _apply_visuals(ship) to write visual/audio-style fields
#     (weapon_style, fire_sfx_kind, etc).
#   - Override _on_unapply(ship) for any extra cleanup (beam visuals,
#     ammo zero, drone teardown). Snapshot restore + GunCooldown re-sync
#     are handled by the base.
#
# .tres compat: the canonical cannon @exports (bullet_scene/base_damage/
# dmg_per_mark/base_cooldown) live here so existing resources/weapons/*.tres
# files keep deserializing onto subclasses (Godot 4 resolves inherited
# @exports).

# Canonical cannon knobs. Subclasses don't need to re-declare these — Godot
# resolves them through inheritance during .tres loading.
@export var bullet_scene: PackedScene
@export var base_damage: int = 0
@export var dmg_per_mark: int = 0
@export var base_cooldown: float = 0.2

# Per-equip snapshot. Maps ship_field_name → prior value. Restored verbatim
# in unapply. Cleared after restore so re-equipping starts fresh.
var _snapshot: Dictionary = {}


func _mk_knobs() -> Dictionary:
	return {}


func _snapshot_keys() -> Array:
	return []


func _apply_visuals(_ship) -> void:
	pass


func _on_unapply(_ship) -> void:
	pass


# Full set of keys to snapshot: caller-declared visual keys plus every
# knob driven by _mk_knobs(). Auto-union avoids the "forgot to snapshot
# what I wrote" bug class (Pattern F).
func _all_snapshot_keys() -> Array:
	var keys: Dictionary = {}
	for k in _snapshot_keys():
		keys[k] = true
	for k in _mk_knobs().keys():
		keys[k] = true
	return keys.keys()


func apply(ship) -> void:
	super.apply(ship)
	_snapshot.clear()
	for key in _all_snapshot_keys():
		if key in ship:
			_snapshot[key] = ship.get(key)
		else:
			# Knob declared but ship doesn't have the field. Surface loudly
			# per CLAUDE.md — never silently noop.
			push_warning("[%s] _snapshot key '%s' missing on ship" % [display_name, key])
	_apply_knobs(ship)
	_apply_visuals(ship)
	_resync_gun_cooldown(ship)


func unapply(ship) -> void:
	for key in _snapshot.keys():
		if key in ship:
			ship.set(key, _snapshot[key])
	_resync_gun_cooldown(ship)
	_on_unapply(ship)
	_snapshot.clear()
	super.unapply(ship)


# Walk _mk_knobs() and write each scaled value to the ship.
func _apply_knobs(ship) -> void:
	for key in _mk_knobs().keys():
		if not (key in ship):
			push_warning("[%s] _mk_knobs key '%s' missing on ship" % [display_name, key])
			continue
		var spec = _mk_knobs()[key]
		var value = _compute_knob_value(key, spec, ship)
		ship.set(key, value)


# Resolve a single knob spec to a concrete value for the current mark.
# Spec types:
#   Array [mk1, mk9] → linear interp; rounded to int if target field is int.
#   Callable(mark) → arbitrary picker.
#   Anything else → passed through as-is (rare; lets a subclass declare a
#   constant override via _mk_knobs without juggling _apply_visuals).
func _compute_knob_value(key: String, spec, ship):
	if spec is Callable:
		return spec.call(int(mark))
	if spec is Array and spec.size() == 2:
		var t: float = (clampf(float(mark), 1.0, 9.0) - 1.0) / 8.0
		var v_lo = spec[0]
		var v_hi = spec[1]
		var lerped: float = lerpf(float(v_lo), float(v_hi), t)
		# Match the current ship field's type — keep ints int, floats float.
		# Snapshot has the prior typed value; fall back to spec[0]'s type.
		var sample = _snapshot.get(key, v_lo)
		if typeof(sample) == TYPE_INT or (sample == null and typeof(v_lo) == TYPE_INT):
			return int(round(lerped))
		return lerped
	return spec


# Cannon timer node lives on the player scene; every primary writes
# cooldown then needs to re-sync the Timer. Secondaries don't have a
# GunCooldown — has_node short-circuits cleanly.
func _resync_gun_cooldown(ship) -> void:
	if ship.has_node("GunCooldown") and "cooldown" in ship:
		ship.get_node("GunCooldown").wait_time = ship.cooldown

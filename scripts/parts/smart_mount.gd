extends "res://scripts/parts/module_part.gd"

# Smart Mount — shared base for the two auto-turret Modules (2026-06-14). A mounted cannon
# fires automatically at the nearest enemy in a 120° front arc; the player still flies +
# manually fires the OTHER cannon (or, with both mounts, doesn't have to fire at all).
# Mk raises the turret traverse rate and tightens shot dispersion. The actual turret logic
# lives on player.gd (module_blaster_* / module_primary_* fields + _update_*_mount); this
# Part just stamps the per-Mk knobs. Subclass overrides _is_blaster() + identity in _init().
# Default-safe: the mount flags default false on the ship.

@export var base_traverse: float = 1.0472    # rad/s aim slew at Mk.1 — 60°/s, slower, more visible aim (intaken from Smart Mount Lab 2026-06-17; was 2.5 ≈ 143°/s)
@export var traverse_per_mark: float = 0.45  # +/mark → ~6.1 rad/s at Mk.9
@export var base_dispersion: float = 0.1745  # ~10° half-spread at Mk.1
@export var min_dispersion: float = 0.0349   # ~2° floor at Mk.9


# Which cannon this mount drives. Blaster = direct-spawn turret; Primary = the real pipeline.
func _is_blaster() -> bool:
	return true


func _traverse_for(at_mark: int) -> float:
	return base_traverse + (at_mark - 1) * traverse_per_mark


func _dispersion_for(at_mark: int) -> float:
	var t: float = clampf((float(at_mark) - 1.0) / 8.0, 0.0, 1.0)
	return lerpf(base_dispersion, min_dispersion, t)


func apply(ship) -> void:
	var tv: float = _traverse_for(int(mark))
	var dp: float = _dispersion_for(int(mark))
	if _is_blaster():
		ship.module_blaster_mount = true
		ship.module_blaster_traverse = maxf(ship.module_blaster_traverse, tv)
		# Tighter (lower) dispersion wins; treat ship's 0 as "unset".
		ship.module_blaster_dispersion = dp if ship.module_blaster_dispersion <= 0.0 else minf(ship.module_blaster_dispersion, dp)
	else:
		ship.module_primary_mount = true
		ship.module_primary_traverse = maxf(ship.module_primary_traverse, tv)
		ship.module_primary_dispersion = dp if ship.module_primary_dispersion <= 0.0 else minf(ship.module_primary_dispersion, dp)


func unapply(ship) -> void:
	if _is_blaster():
		ship.module_blaster_mount = false
		ship.module_blaster_traverse = 0.0
		ship.module_blaster_dispersion = 0.0
	else:
		ship.module_primary_mount = false
		ship.module_primary_traverse = 0.0
		ship.module_primary_dispersion = 0.0


# Editor readout — turret traverse in deg/s at this Mk.
func effective_damage(at_mark: int) -> int:
	return int(round(rad_to_deg(_traverse_for(at_mark))))

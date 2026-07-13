extends "res://scripts/enemies/enemy_core.gd"

# Ground structures — buildings + turrets (Roman 2026-07-12). They drift down the lane like an asteroid
# (LateralDrift movement) and carry NO ship VFX: no damage-tell overlay/spiral, no engine trail, no
# parallax shadow, and no styled spin-out / wreck death. A weapon, if any, is a hardpoint from the
# roster (GUN muzzles on the diamond turret, a rotating TURRET on the turret / launcher); the plain
# buildings have none — "won't shoot".
#
# Death = EXPLODE WITH DEBRIS, then leave the base as an inert husk:
#   - a random explosion type + a debris scatter at the structure,
#   - the ROTATING turret layer (an EnemyTurret, if this structure has one) is destroyed + removed,
#   - the intact overlays (Building / GlowMuzzle) hide and the "Destroyed" frame shows,
#   - the base keeps drifting with collision OFF (bullets AND the player pass through), freed once it
#     clears the bottom of the screen.

const ExplosionFxC = preload("res://scripts/effects/explosion_fx.gd")
const EnemyDeathFxC = preload("res://scripts/effects/enemy_death_fx.gd")

var _husk: bool = false   # true once destroyed — the base is now inert, drifting debris


func _ready() -> void:
	# Structures aren't ships: no damage-tell overlay/spiral, engine trail, or parallax shadow, and the
	# styled/wreck death is skipped (explode() below is fully overridden anyway). Set before super._ready
	# so the vfx gating reads it.
	has_ship_vfx = false
	# Never recycle (Roman 2026-07-13): a ground structure that drifts off-screen must despawn, not fly
	# back through the parallax. recycle_passes == 0 makes RecycleController._leave() instead of cycling.
	recycle_passes = 0
	super._ready()


func _process(delta: float) -> void:
	if _husk:
		# Inert base husk: keep drifting via the same pattern (no firing / components / auto-rotate), and
		# free it once it clears the bottom (RecycleController is bypassed — a husk never recycles).
		var sd: float = min(delta, 1.0 / 30.0)
		if _pattern != null and not _cycling:
			position += _pattern.compute_step(self, sd)
		if global_position.y > screensize.y + 48.0:
			queue_free()
		return
	super._process(delta)


func explode() -> void:
	if _husk or _dying:
		return
	_husk = true
	# Credit the bounty + fire component death hooks (faction drops), but DO NOT run the hull's styled
	# spin-out / classic hull death — the base survives.
	died.emit(bounty_value)
	_components_death()
	# Blast origin: the rotating turret if there is one, else the structure's own centre.
	var tur := _find_turret(self)
	var at: Vector2 = (tur.global_position if (tur != null and is_instance_valid(tur)) else global_position)
	if tur != null and is_instance_valid(tur):
		tur.queue_free()   # the rotating turret layer is destroyed + removed
	# Explode WITH DEBRIS: a random explosion type + a debris scatter (both parented to the world so they
	# outlive the husk).
	var fx: Node = _fx_parent()
	var names: Array = ExplosionFxC.variant_names()
	var scn: PackedScene = null
	if not names.is_empty():
		scn = ExplosionFxC.scene_for(String(names[randi() % names.size()]))
	ExplosionFxC.play(at, 1.0, true, fx, scn)
	EnemyDeathFxC.spawn_debris(fx, at, display_scale)
	# Base → Destroyed look (hide the intact overlays, show the "Destroyed" frame) + inert drifting husk.
	_hide_layer("Building")
	_hide_layer("GlowMuzzle")
	var d := find_child("Destroyed", true, false)
	if d != null and d is CanvasItem:
		(d as CanvasItem).visible = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	remove_from_group("enemies")


func _hide_layer(layer_name: String) -> void:
	var n := find_child(layer_name, true, false)
	if n != null and n is CanvasItem:
		(n as CanvasItem).visible = false


# First EnemyTurret in the subtree (the mount attaches it under the "Turret" marker).
func _find_turret(n: Node) -> Node:
	for c in n.get_children():
		if c is EnemyTurret:
			return c
		var r := _find_turret(c)
		if r != null:
			return r
	return null

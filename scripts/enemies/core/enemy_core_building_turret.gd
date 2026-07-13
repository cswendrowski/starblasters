extends "res://scripts/enemies/enemy_core.gd"

# Core Turret (Roman 2026-07-12). Drifts down its lane like an asteroid (LateralDrift movement); the
# turret LAYER — a TURRET hardpoint on the "Turret" marker — tracks the player and fires. Bench-tunable
# weapon (payload / rate / count / spread / rotation), like the Helix/Crusader turrets.
#
# Destroying it is a TURRET kill, NOT a hull death:
#   - the turret gets a RANDOM explosion type and is removed,
#   - NO spin-out / styled death,
#   - the BASE switches to its "Destroyed" look and stays a passive husk: collision is disabled (bullets
#     AND the player pass straight through) and it keeps drifting until it clears the bottom of the screen.

const ExplosionFxC = preload("res://scripts/effects/explosion_fx.gd")

var _husk: bool = false   # true once the turret is destroyed — the base is now inert, drifting debris


func _process(delta: float) -> void:
	if _husk:
		# Passive base husk: keep drifting via the same pattern (no firing / components / auto-rotate),
		# and free it once it clears the bottom (RecycleController is bypassed — a husk never recycles).
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
	# TURRET kill: credit the bounty + fire component death hooks (faction firecore drop etc.), but skip
	# the hull's styled spin-out / classic explosion — the base survives.
	died.emit(bounty_value)
	_components_death()
	# Random explosion type ON the turret, then remove the turret layer.
	var tur := _find_turret(self)
	if tur != null and is_instance_valid(tur):
		var names: Array = ExplosionFxC.variant_names()
		var scn: PackedScene = null
		if not names.is_empty():
			scn = ExplosionFxC.scene_for(String(names[randi() % names.size()]))
		ExplosionFxC.play(tur.global_position, 1.0, true, _fx_parent(), scn)
		tur.queue_free()
	# Base → "Destroyed" look + inert husk: collision off (bullets + player pass through), leave the
	# live-combatant group so the director stops counting it. It keeps drifting (see _process above).
	var destroyed := get_node_or_null("Sprite2D/Destroyed")
	if destroyed != null and destroyed is CanvasItem:
		(destroyed as CanvasItem).visible = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	remove_from_group("enemies")


# First EnemyTurret in the subtree (the mount attaches it under the "Turret" marker).
func _find_turret(n: Node) -> Node:
	for c in n.get_children():
		if c is EnemyTurret:
			return c
		var r := _find_turret(c)
		if r != null:
			return r
	return null

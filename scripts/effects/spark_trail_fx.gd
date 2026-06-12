extends Node

# SparkTrailFx — attaches scenes/effects/spark_trail.tscn (Roman's fire-spark GPUParticles2D
# trail: white→orange→red radial sparks with ribbon trails) as a reusable effect. Two modes:
#
#   attach_to_player(player, local, activate_below) — a DAMAGE TELL: parented to the player at
#       `local`, it only EMITS once the hull drops past activate_below (gated on hull_changed,
#       exactly like engine_torch / damage_smoke_trail). Returns the instance.
#   spawn(parent, pos) — always-on; parented to `parent` at `pos` (e.g. a burning debris chunk),
#       emitting immediately. Returns the instance; the caller stops emission / frees it.
#
# The scene's particle node is found generically (first GPUParticles2D child), so renaming it
# in the editor won't break this.

const SPARK_SCENE := preload("res://scenes/effects/spark_trail.tscn")

# Downward drift for the PLAYER sparks (px/s²), faking the ship's forward motion so the sparks
# fall behind — same idea as the damage smoke trail's downward drift (DRIFT_BASE_SPEED 225).
const PLAYER_SPARK_GRAVITY := 240.0
const PLAYER_SPARK_AMOUNT := 60   # cap (player markers are gated, but several can light at once)


static func spawn(parent: Node, pos: Vector2) -> Node2D:
	if parent == null:
		return null
	var inst: Node2D = SPARK_SCENE.instantiate()
	inst.position = pos
	parent.add_child(inst)
	return inst


static func attach_to_player(player: Node, local: Vector2, activate_below: float) -> Node2D:
	if player == null:
		return null
	var inst: Node2D = SPARK_SCENE.instantiate()
	inst.position = local
	player.add_child(inst)
	var parts: GPUParticles2D = particles(inst)
	if parts != null:
		# Downward drift to fake the ship's forward motion (the sparks fall behind, like the
		# damage smoke). Duplicate the process material first so this only touches the PLAYER
		# sparks — the scene resource is shared with the debris / burning-trail variants.
		if parts.process_material != null:
			parts.process_material = parts.process_material.duplicate()
			var pm := parts.process_material as ParticleProcessMaterial
			if pm != null:
				pm.gravity = Vector3(0.0, PLAYER_SPARK_GRAVITY, 0.0)
		parts.amount = mini(parts.amount, PLAYER_SPARK_AMOUNT)
		parts.emitting = false   # off until the hull crosses the damage threshold
		# Gate emission on the host's hull, mirroring engine_torch / damage_smoke_trail.
		var gate := func(mh, h):
			if not is_instance_valid(parts):
				return
			if mh <= 0:
				parts.emitting = false
				return
			parts.emitting = (1.0 - float(h) / float(mh)) >= activate_below
		if player.has_signal("hull_changed"):
			player.hull_changed.connect(gate)
		if "max_hull" in player and "hull" in player:
			gate.call(player.max_hull, player.hull)
	return inst


# The instance's GPUParticles2D child (first one found), or null.
static func particles(inst: Node) -> GPUParticles2D:
	if inst == null or not is_instance_valid(inst):
		return null
	for c in inst.get_children():
		if c is GPUParticles2D:
			return c
	return null

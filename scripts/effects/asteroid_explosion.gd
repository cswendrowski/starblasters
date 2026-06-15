extends Node

# AsteroidExplosionFx (Roman 2026-06-15) — static spawner for the authored asteroid
# death-burst scene (res://scenes/effects/asteroid_explosion.tscn). Instantiate it at a
# world position, fire its one-shot GPUParticles2D emitters, and free the whole node once
# the longest-lived emitter (plus its trail) has finished. Keeping the play/cleanup logic
# here means the .tscn stays a pure particle-authoring surface with no root script — so it
# can keep being tuned live in the editor.
#
#   AsteroidExplosionFx.play(parent, world_pos)

const SCENE := preload("res://scenes/effects/asteroid_explosion.tscn")


static func play(parent: Node, world_pos: Vector2, tint: Color = Color.WHITE) -> void:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var fx: Node2D = SCENE.instantiate()
	parent.add_child(fx)
	fx.global_position = world_pos
	# Tint the whole burst to the rock's colour (modulate multiplies through to every emitter).
	fx.modulate = tint
	# Trigger every one-shot emitter and find the slowest to time the self-free. speed_scale
	# shortens wall-clock life (Small Particles runs at 6×), so divide it out.
	var ttl: float = 0.5
	for child in fx.get_children():
		if child is GPUParticles2D:
			var p: GPUParticles2D = child
			p.emitting = true
			ttl = maxf(ttl, p.lifetime / maxf(p.speed_scale, 0.01) + p.trail_lifetime)
	# Connect to the fx node's own queue_free (not the caller's) so the cleanup survives the
	# spawning asteroid freeing itself ~0.5 s after death.
	parent.get_tree().create_timer(ttl + 0.3).timeout.connect(fx.queue_free)

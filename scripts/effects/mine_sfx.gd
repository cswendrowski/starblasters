extends Node

# Tiny helper for one-shot mine / bomblet explosion audio. Spawns a transient
# AudioStreamPlayer2D at the world position, plays, and frees itself when
# done. Used by all mine variants + bomblets so they sound like real
# detonations (Roman, 2026-05-16: "mines need to play the explosion death
# sound like normal enemies do").

const EXPLOSION_SFX = preload("res://Sound/SFX_explosion1.wav")

static func play_at(world_pos: Vector2, volume_db: float = -4.0) -> void:
	var p := AudioStreamPlayer2D.new()
	p.stream = EXPLOSION_SFX
	p.volume_db = volume_db
	p.global_position = world_pos
	Engine.get_main_loop().root.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

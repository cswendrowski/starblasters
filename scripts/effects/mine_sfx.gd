extends Node

# Tiny helper for one-shot mine / bomblet explosion audio. Spawns a transient
# AudioStreamPlayer2D at the world position, plays, and frees itself when
# done. Used by all mine variants + bomblets so they sound like real
# detonations (Roman, 2026-05-16: "mines need to play the explosion death
# sound like normal enemies do").

# RETIRED 2026-06-10: explosions now sound through ExplosionFx -> ExplosionSfx (the distance-based
# close/medium/distant system), which every mine/bomblet already triggers via ExplosionFx.play/burst.
# play_at is a no-op kept so existing call sites don't break; the redundant calls can be swept in a
# later cleanup pass (logged in Worklog). The old SFX_explosion1.wav cue is no longer referenced here.
static func play_at(_world_pos: Vector2, _volume_db: float = -4.0) -> void:
	pass

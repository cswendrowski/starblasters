extends Node

# Distance-based explosion SFX (Roman 2026-06-10). Picks a Close / Medium / Distant clip pool by the
# explosion's distance to the player and plays a positional one-shot on the SFX bus. Wired into
# ExplosionFx.play so every blast sounds; ExplosionFx.burst sounds ONCE per death (not per sub-blast)
# via with_sound. Retires the old single SFX_explosion1.wav cue.
#
#   ExplosionSfx.play(world_pos)             # auto distance to player
#   ExplosionSfx.play(world_pos, 1.8, parent)

const CLOSE_CLIPS := [
	preload("res://assets/audio/weapons/explosions/CloseExplosion_01.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_02.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_03.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_04.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_05.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_10.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_11.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_12.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_13.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_14.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_15.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_16.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_17.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_18.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_19.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_20.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_21.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_22.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_23.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_24.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_25.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_26.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_27.ogg"),
	preload("res://assets/audio/weapons/explosions/CloseExplosion_28.ogg"),
]
const MEDIUM_CLIPS := [
	preload("res://assets/audio/weapons/explosions/MediumExplosion_01.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_02.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_03.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_04.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_05.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_06.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_07.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_08.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_09.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_10.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_11.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_12.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_13.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_14.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_15.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_16.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_17.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_18.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_19.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_20.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_21.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_22.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_23.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_24.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_25.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_26.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_27.ogg"),
	preload("res://assets/audio/weapons/explosions/MediumExplosion_28.ogg"),
]
const DISTANT_CLIPS := [
	preload("res://assets/audio/weapons/explosions/DistantExplosion_01.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_02.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_03.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_04.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_05.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_06.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_07.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_08.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_09.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_10.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_11.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_12.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_13.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_14.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_15.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_16.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_17.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_18.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_19.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_20.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_21.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_22.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_23.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_24.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_25.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_26.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_27.ogg"),
	preload("res://assets/audio/weapons/explosions/DistantExplosion_28.ogg"),
]

# Distance bands in 480x270 playfield px (explosion -> player). TUNABLE — logged for Roman.
const NEAR_DIST: float = 62.0      # < this  => Close
const FAR_DIST: float = 168.0      # >= this => Distant; between => Medium
const VOL_CLOSE: float = -1.0
const VOL_MEDIUM: float = -4.0
const VOL_DISTANT: float = -8.0


static func _player() -> Node2D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for n in tree.get_nodes_in_group("player"):
		if is_instance_valid(n):
			return n as Node2D
	return null


# Play a distance-appropriate explosion clip at `world_pos`. `scale` nudges volume (bigger=louder).
# `parent` defaults to the window root; pass a container (hangar world) to keep it in that viewport.
static func play(world_pos: Vector2, scale: float = 1.0, parent: Node = null) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var pool: Array
	var vol: float
	var p := _player()
	var dist: float = 95.0   # default band (Medium) when there's no player (meta scenes)
	if p != null:
		dist = world_pos.distance_to(p.global_position)
	if dist < NEAR_DIST:
		pool = CLOSE_CLIPS
		vol = VOL_CLOSE
	elif dist >= FAR_DIST:
		pool = DISTANT_CLIPS
		vol = VOL_DISTANT
	else:
		pool = MEDIUM_CLIPS
		vol = VOL_MEDIUM
	if pool.is_empty():
		return
	var clip: AudioStream = pool[randi() % pool.size()]
	vol += clampf((scale - 1.0) * 2.0, -2.0, 4.0)
	var host: Node = parent if (parent != null and is_instance_valid(parent)) else tree.root
	var ap := AudioStreamPlayer2D.new()
	ap.stream = clip
	ap.volume_db = vol
	ap.bus = "SFX"
	ap.global_position = world_pos
	host.add_child(ap)
	ap.play()
	ap.finished.connect(ap.queue_free)

extends Node

# Laser/beam audio (Roman 2026-07-15). One home for every laser sound family so the
# beam emitter, the player Particle Beam, and any future beam host share pools.
# Preload-referenced, NOT a class_name (headless class-cache safety):
#   const LaserSfx = preload("res://scripts/effects/laser_sfx.gd")
#
# Families (assets/audio/weapons/universal/):
#   BLAST_SMALL  — start/stop one-shot for non-boss enemy lasers + the player laser
#   BLAST_LARGE  — start/stop one-shot for BOSS lasers
#   POWER_UP     — non-boss charge-up warning (the audio tell a shot is coming —
#                  always precedes firing; the visual tell may run longer)
#   POWER_UP_FLUTTER / POWER_DOWN_FLUTTER — boss charge-up / post-fire spin-down
#   LOOP_*       — sustained firing loops, faded out as the beam finishes:
#                  enemy = field loops 1-3, boss = field loops 4-5, sapper = force loop
#   play_hit     — per-hit impact sound (small blast pool, ducked) when a beam
#                  strikes a player/enemy/boss.
#
# One-shots spawn a self-freeing AudioStreamPlayer2D on the SFX bus (parent them to
# the tree root so they outlive a dying emitter). Loops go through make_loop_player()
# — the CALLER owns the returned node (adds it, plays/fades it).

const BLAST_SMALL := [
	preload("res://assets/audio/weapons/universal/energy_blast_small_01.ogg"),
	preload("res://assets/audio/weapons/universal/energy_blast_small_02.ogg"),
	preload("res://assets/audio/weapons/universal/energy_blast_small_03.ogg"),
	preload("res://assets/audio/weapons/universal/energy_blast_small_04.ogg"),
	preload("res://assets/audio/weapons/universal/energy_blast_small_05.ogg"),
]
const BLAST_LARGE := [
	preload("res://assets/audio/weapons/universal/energy_blast_large_02.ogg"),
	preload("res://assets/audio/weapons/universal/energy_blast_large_03.ogg"),
	preload("res://assets/audio/weapons/universal/energy_blast_large_04.ogg"),
	preload("res://assets/audio/weapons/universal/energy_blast_large_05.ogg"),
]
const POWER_UP := preload("res://assets/audio/weapons/universal/power_up.ogg")
const POWER_UP_FLUTTER := preload("res://assets/audio/weapons/universal/power_up_flutter.ogg")
const POWER_DOWN_FLUTTER := preload("res://assets/audio/weapons/universal/power_down_flutter.ogg")
const LOOP_ENEMY := [
	preload("res://assets/audio/weapons/universal/energy_field_loop_1.ogg"),
	preload("res://assets/audio/weapons/universal/energy_field_loop_2.ogg"),
	preload("res://assets/audio/weapons/universal/energy_field_loop_3.ogg"),
]
const LOOP_BOSS := [
	preload("res://assets/audio/weapons/universal/energy_field_loop_4.ogg"),
	preload("res://assets/audio/weapons/universal/energy_field_loop_5.ogg"),
]
const LOOP_SAPPER := [
	preload("res://assets/audio/weapons/universal/energy_force_loop.ogg"),
]

const BLAST_VOLUME_DB: float = -4.0
const CHARGE_VOLUME_DB: float = -4.0
const SPIN_DOWN_VOLUME_DB: float = -4.0
const LOOP_VOLUME_DB: float = -8.0
const HIT_VOLUME_DB: float = -12.0   # per-hit ticks land often — keep them under the beam bed
const SILENT_DB: float = -60.0


# Start/stop one-shot. big = boss laser (large blast pool).
static func play_blast(parent: Node, world_pos: Vector2, big: bool) -> void:
	var pool: Array = BLAST_LARGE if big else BLAST_SMALL
	_play(parent, world_pos, pool[randi() % pool.size()], BLAST_VOLUME_DB)


# Charge-up warning — the audio tell that a shot is coming.
static func play_charge(parent: Node, world_pos: Vector2, boss: bool) -> void:
	_play(parent, world_pos, POWER_UP_FLUTTER if boss else POWER_UP, CHARGE_VOLUME_DB)


# Boss post-fire spin-down.
static func play_spin_down(parent: Node, world_pos: Vector2) -> void:
	_play(parent, world_pos, POWER_DOWN_FLUTTER, SPIN_DOWN_VOLUME_DB)


# Beam strike tick (player/enemy/boss hit by a laser).
static func play_hit(parent: Node, world_pos: Vector2) -> void:
	_play(parent, world_pos, BLAST_SMALL[randi() % BLAST_SMALL.size()], HIT_VOLUME_DB)


# Build a positional loop player for a profile ("boss"/"sapper"/anything-else=enemy).
# Caller adds it to the tree, plays it, and fades volume_db to SILENT_DB to end it.
static func make_loop_player(profile: String) -> AudioStreamPlayer2D:
	var pool: Array = LOOP_ENEMY
	match profile:
		"boss":
			pool = LOOP_BOSS
		"sapper":
			pool = LOOP_SAPPER
	# Duplicate before forcing loop on — the preloaded resource is shared and the
	# .import sidecars author these clips loop=false.
	var stream: AudioStream = (pool[randi() % pool.size()] as AudioStream).duplicate()
	if "loop" in stream:
		stream.loop = true
	var p := AudioStreamPlayer2D.new()
	p.stream = stream
	p.volume_db = LOOP_VOLUME_DB
	p.bus = "SFX"
	return p


static func _play(parent: Node, world_pos: Vector2, clip: AudioStream, volume_db: float) -> void:
	if parent == null or clip == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = clip
	p.volume_db = volume_db
	p.bus = "SFX"
	p.global_position = world_pos
	parent.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

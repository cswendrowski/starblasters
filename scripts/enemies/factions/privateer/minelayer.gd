extends "res://scripts/enemies/enemy_core.gd"

# Minelayer. Travels horizontally across the playfield (side_traverse
# pattern) dropping bomblets in a regular cadence. Multi-hit because it's
# slow and chunky. On death, scatters a cluster of bomblets like a
# cluster mine going off.

# Roman 2026-06-01: minelayer drops plain DUMB bomblets (not the smart,
# station-keeping variant) — both the trail it lays and the death scatter use
# the same simple bomblet, mirroring the cluster mine's burst.
const BulletWorld = preload("res://scripts/systems/bullet_world.gd")
const BombletScene = preload("res://scenes/enemies/enemy_bomblet.tscn")
const DeathBombletScene = preload("res://scenes/enemies/enemy_bomblet.tscn")

@export var drop_interval: float = 2.5
@export var drop_count_on_death: int = 6

var _drop_t: float = 0.0


func _ready() -> void:
	# Minelayer crosses the screen and exits the opposite side.
	offscreen_mode = OffscreenMode.FREE_OPPOSITE_SIDE
	# Doesn't shoot (Roman, 2026-05-16). Strip any pattern the director
	# may have wired up + stop the timer so the carrier never opens fire.
	shoot_pattern = null
	if has_node("ShootTimer"):
		$ShootTimer.stop()
	super._ready()


# Minelayer entry override: the carrier spawns OUTSIDE the playfield on
# one of the two sides at mid-screen y, then cruises across. Roman,
# 2026-05-16: "Minelayer needs to come in from the left or right around
# the middle of the screen". Bypasses the standard top-down spawn rig
# by re-positioning at start() time after super.start() has set up the
# pattern.
func start(pos: Vector2) -> void:
	super.start(pos)
	# Use the pattern's direction if set (the wave generator hands the
	# pattern a direction); otherwise roll one. Place us just off the
	# corresponding edge so we'll cross into the playfield.
	var dir: int = 1
	if _pattern != null and "direction" in _pattern:
		dir = int(_pattern.direction)
	# Spawn just outside the playfield band so the carrier enters gameplay
	# immediately and mines drop inside the shootable zone. Roman 2026-06-01:
	# crosses the mid-UPPER band (0.33) so the line of mines sits ahead of the
	# player rather than dead-center.
	var mid_y: float = screensize.y * 0.33
	if dir > 0:
		position = Vector2(Playfield.X_MIN - 32.0, mid_y)
	else:
		position = Vector2(Playfield.X_MAX + 32.0, mid_y)


func _process(delta: float) -> void:
	super._process(delta)
	if _cycling:
		return
	# Generic `_on_playfield()` margin (8 px) isn't wide enough for the
	# minelayer specifically — sprite is ~48 px wide after the 3×/2× scale,
	# so x=8 leaves half the ship still hanging off-screen. Use a margin
	# that matches the carrier's silhouette so bomblets only drop when the
	# whole ship is visible. Roman, 2026-05-17.
	if not _carrier_fully_visible():
		return
	_drop_t -= delta
	if _drop_t <= 0.0:
		_drop_t = drop_interval
		_drop_bomblet()


# Minelayer-specific visibility gate: the carrier's silhouette has to be
# entirely on-screen before mines fall. Uses a generous 56 px margin so
# the wing tips clear the edge.
func _carrier_fully_visible() -> bool:
	# Margin sized to half the carrier silhouette (sprite ~48 px wide after
	# scale) plus a small buffer. On the narrow 216-px playfield band, 56
	# left only ~100 px of drop range; 32 gives ~150 px while keeping the
	# wingtips inside the shootable zone.
	# Sized to ~half the carrier silhouette. New 16×32 art (Roman 2026-06-01,
	# was a scaled 48px placeholder) crosses ~32 px along its travel axis, so 16
	# keeps the hull on-screen while leaving most of the band as drop range.
	const CARRIER_MARGIN := 16.0
	var p: Vector2 = position
	return p.x >= Playfield.X_MIN + CARRIER_MARGIN \
		and p.x <= Playfield.X_MAX - CARRIER_MARGIN \
		and p.y >= 8.0 \
		and p.y <= screensize.y - 8.0


func _drop_bomblet() -> void:
	var b = BombletScene.instantiate()
	var world: Node = BulletWorld.resolve(self, get_tree().root)
	world.add_child(b)
	# Drop from the rear of the carrier (Roman, 2026-05-17: "should come
	# out the back of the ship rather than the middle"). The minelayer
	# traverses horizontally — "back" is opposite the travel direction.
	var dir: int = 1
	if _pattern != null and "direction" in _pattern:
		dir = int(_pattern.direction)
	var rear_offset: Vector2 = Vector2(-float(dir) * 16.0, 0.0)
	if b.has_method("start"):
		b.start(global_position + rear_offset)
	else:
		b.global_position = global_position + rear_offset


# Death override: drop a scatter of bomblets in addition to the regular
# explode sequence.
func explode() -> void:
	var world: Node = BulletWorld.resolve(self, get_tree().root)
	for i in drop_count_on_death:
		var b = DeathBombletScene.instantiate()
		world.add_child(b)
		var jitter: Vector2 = Vector2(randf_range(-28.0, 28.0), randf_range(-12.0, 18.0))
		if b.has_method("start"):
			b.start(global_position + jitter)
		else:
			b.global_position = global_position + jitter
	super.explode()

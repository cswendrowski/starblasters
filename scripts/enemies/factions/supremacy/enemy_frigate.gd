extends EnemyBase
class_name EnemyFrigate

# Frigate — tough broadside gunner. Roman 2026-06-01 rework.
#
# A slow, heavily-armoured warship that presents a BROADSIDE: it fires a
# steady stream of slow shots straight out of whichever flank (port/starboard)
# is currently facing the player — a raking wall of fire, strongest when the
# frigate crosses the screen horizontally and its down-facing flank rakes the
# playfield.
#
# Two arrival modes, rolled per spawn in start():
#   TOP_DESCENT — enters from the top, steams slowly straight down.
#   SIDE_CROSS  — enters off one side at an upper-mid band, cruises across.
# Either way `auto_rotate` (EnemyBase) turns the hull to face its heading, so
# the port/starboard flanks always sit perpendicular to travel.
#
# Bespoke (extends EnemyBase, not enemy_core) because the broadside firing and
# the two-mode locomotion can't be expressed as a movement/shoot Resource. The
# roster entry sets movement/shoot to null; the director skips both overrides
# (guarded by `"movement" in enemy`) but still applies max_health from
# compose_stats, so toughness is driven by the roster `hp_override`.
#
# The two-frame sprite sheet packs the hull on frame 0 and an emissive GLOW
# layer on frame 1 (GlowMask node). EnemyBase installs the damage-overlay
# shader + hit-flash on the node literally named "Sprite2D" only, so the glow
# overlay never darkens/frays with damage — exactly as intended.

const BULLET_SCENE = preload("res://scenes/projectiles/enemy_bullet.tscn")
const MuzzleFx = preload("res://scripts/effects/muzzle_fx.gd")

enum Mode { TOP_DESCENT, SIDE_CROSS }

# --- Locomotion ----------------------------------------------------------
const TOP_SPEED   := 32.0   # px/s — slow steaming descent
const SIDE_SPEED  := 38.0   # px/s — slow horizontal cruise
const SIDE_BAND_MIN := 46.0 # upper-mid Y band for a side-cross entry
const SIDE_BAND_MAX := 128.0
const SIDE_ENTER_INSET := 28.0  # spawn this far outside the playfield band

# --- Broadside -----------------------------------------------------------
const GUN_COUNT     := 5      # guns per flank (GunLeft1..5 / GunRight1..5)
const FIRE_INTERVAL := 0.34   # per-gun beat — a steady patter, not a volley
const BULLET_SPEED  := 140.0  # slow shots

# --- Formation separation (X-only) --------------------------------------
const SEPARATION_RADIUS := 40.0
const PUSH_STRENGTH      := 55.0
const SEP_SIDE_MARGIN    := 14.0

var _mode: int = Mode.TOP_DESCENT
var _side_dir: int = 1        # +1 = cruising right, -1 = cruising left
var _fire_t: float = 0.0
var _next_gun: int = 0


func _ready() -> void:
	# Tough. Set before super._ready() (per the boss-stat convention); the wave
	# spec's max_health from compose_stats(hp_override) overrides this on spawn.
	max_health = 28
	bounty_value = 25
	auto_rotate = true
	offscreen_mode = OffscreenMode.FREE_ANY_EDGE
	super._ready()


# Director calls start(pos) after on_spawned_in_wave(). Roll the arrival mode
# here: TOP_DESCENT keeps the director's top-band spawn; SIDE_CROSS overrides
# position to just off one side at a random upper-mid altitude.
func start(pos: Vector2) -> void:
	if randf() < 0.5:
		_mode = Mode.SIDE_CROSS
		_side_dir = 1 if randf() < 0.5 else -1
		var y: float = randf_range(SIDE_BAND_MIN, SIDE_BAND_MAX)
		if _side_dir > 0:
			position = Vector2(Playfield.X_MIN - SIDE_ENTER_INSET, y)
		else:
			position = Vector2(Playfield.X_MAX + SIDE_ENTER_INSET, y)
	else:
		_mode = Mode.TOP_DESCENT
		position = pos
	# Seed the auto-rotation reference so the first frame's delta is sane.
	_last_position = global_position


func _process(delta: float) -> void:
	if _dying:
		return
	match _mode:
		Mode.TOP_DESCENT:
			position.y += TOP_SPEED * delta
		Mode.SIDE_CROSS:
			position.x += SIDE_SPEED * float(_side_dir) * delta
	_update_broadside(delta)
	# EnemyBase handles auto-rotation (from our position delta) + offscreen free.
	super._process(delta)
	# Spacing only matters for the top-band clump; side-crossers are spread
	# across randomized Y bands and a lateral push would fight their cruise.
	if _mode == Mode.TOP_DESCENT:
		_separate_from_siblings(delta)


# Fire a steady broadside out the flank whose outward normal best faces the
# player. Guns on the chosen flank fire one-at-a-time on FIRE_INTERVAL, ripple
# down the hull (gun 1→5) for a "rolling broadside" read. Shots travel straight
# out the flank (perpendicular to the hull) — a true naval broadside.
func _update_broadside(delta: float) -> void:
	var player := find_player()
	if player == null:
		return
	var to_player: Vector2 = player.global_position - global_position
	if to_player.length_squared() < 1.0:
		return
	to_player = to_player.normalized()
	# Flank outward normals in world space (hull faces travel via rotation).
	var left_n: Vector2 = Vector2(-1.0, 0.0).rotated(rotation)
	var right_n: Vector2 = Vector2(1.0, 0.0).rotated(rotation)
	var use_right: bool = right_n.dot(to_player) >= left_n.dot(to_player)
	var fire_dir: Vector2 = right_n if use_right else left_n
	var prefix: String = "GunRight" if use_right else "GunLeft"

	_fire_t -= delta
	if _fire_t > 0.0:
		return
	_fire_t = FIRE_INTERVAL
	_fire_gun(prefix, fire_dir)
	_next_gun = (_next_gun + 1) % GUN_COUNT


func _fire_gun(prefix: String, dir: Vector2) -> void:
	var marker := get_node_or_null(prefix + str(_next_gun + 1)) as Marker2D
	var spawn_pos: Vector2 = marker.global_position if marker else global_position
	var b = BULLET_SCENE.instantiate()
	b.speed = BULLET_SPEED
	get_tree().root.add_child(b)
	if b.has_method("start"):
		b.start(spawn_pos, dir)
	elif "velocity_dir" in b:
		b.velocity_dir = dir
	MuzzleFx.play_enemy(spawn_pos, dir, get_tree().root)
	if has_node("EnemyShoot"):
		$EnemyShoot.play()


# X-only repulsion from other frigates within SEPARATION_RADIUS so a top-band
# trio doesn't stack into a single bullet column. Applied straight to position
# (we own locomotion now — there's no pattern snap to undo). Re-clamped into
# the playfield band so the push can't shove a frigate into the gutter.
func _separate_from_siblings(delta: float) -> void:
	var my_script: Script = get_script()
	var push_x: float = 0.0
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self or not is_instance_valid(node):
			continue
		if node.get_script() != my_script:
			continue
		var other := node as Node2D
		if other == null:
			continue
		var dx: float = global_position.x - other.global_position.x
		var dy: float = global_position.y - other.global_position.y
		var dist: float = sqrt(dx * dx + dy * dy)
		if dist < SEPARATION_RADIUS and dist > 0.001:
			var falloff: float = 1.0 - (dist / SEPARATION_RADIUS)
			var sdir: float = signf(dx) if absf(dx) > 0.001 else 1.0
			push_x += sdir * falloff
	if push_x == 0.0:
		return
	position.x += push_x * PUSH_STRENGTH * delta
	position.x = clampf(position.x, Playfield.X_MIN + SEP_SIDE_MARGIN, Playfield.X_MAX - SEP_SIDE_MARGIN)

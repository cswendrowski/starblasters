extends EnemyBase
class_name EnemyFirecoreCruiser

# Rare huge traversal enemy. Enters from a side edge, flies straight across
# the upper-middle screen band, exits off the opposite side. Carries an
# inline hook turret that fires plasma_orb bullets while the ship is more
# than 51% on-screen. On death: stops movement, descends at 40 px/s with
# fire+smoke trailing upward, explodes + queue_frees when off the bottom.

const TRAVERSE_SPEED  := 60.0      # px/s horizontal
const DESCENT_SPEED   := 40.0      # px/s downward during death
const TRAVERSE_Y      := 62.0      # centre Y while traversing
const FIRE_INTERVAL   := 2.0       # seconds between turret shots
const BULLET_SPEED    := 160.0
const ROTATION_SPEED  := 2.0       # turret aim radians/second
const AIM_TOLERANCE   := 0.20      # radians — must be aimed within to fire
const SIZE_PX         := 64.0      # sprite-frame width for on-screen check

const PlasmaOrbVariant = preload("res://data/bullets/plasma_orb.tres")
const EnemyBulletScene = preload("res://scenes/projectiles/enemy_bullet.tscn")
const HookTurretTex    = preload("res://graphics/enemies/hook_turret.png")

var _traverse_speed: float = TRAVERSE_SPEED
var _direction: float = 1.0  # +1 = moving right, -1 = moving left

# Inline turret state
var _turret_node: Node2D = null
var _turret_sprite: Sprite2D = null
var _fire_t: float = 0.0
var _turret_rot: float = 0.0
var _turret_can_fire: bool = false

# Death descent
var _descending: bool = false


func _ready() -> void:
	max_health    = 32
	bounty_value  = 100
	auto_rotate   = false
	display_scale = 3.0
	offscreen_mode = OffscreenMode.NONE  # manages its own lifecycle
	super._ready()

	# Determine traversal direction from spawn position.
	# Spawned just off the left edge → move right (+1).
	# Spawned just off the right edge → move left (-1).
	if global_position.x < Playfield.CENTER.x:
		_direction = 1.0
	else:
		_direction = -1.0

	# Clamp Y to the traversal band.
	global_position.y = TRAVERSE_Y

	# Build inline turret.
	_build_turret()

	# Stagger initial fire timer so first shot isn't instant.
	_fire_t = randf_range(0.5, FIRE_INTERVAL)


func _build_turret() -> void:
	_turret_node = Node2D.new()
	_turret_node.name = "HookTurret"
	add_child(_turret_node)

	_turret_sprite = Sprite2D.new()
	_turret_sprite.texture = HookTurretTex
	_turret_sprite.modulate = Color.html("9350ad")
	_turret_node.add_child(_turret_sprite)


func _process(delta: float) -> void:
	if _dying and not _descending:
		return  # explode() sets _descending before movement resumes

	if _descending:
		_tick_descent(delta)
		return

	_tick_traverse(delta)
	_tick_turret(delta)
	# No super._process() call — NONE offscreen mode and auto_rotate=false
	# means the base _process would just check offscreen (skipped) and
	# _apply_auto_rotation (no-op). Skip to avoid redundant work.


func _tick_traverse(delta: float) -> void:
	global_position.x += _traverse_speed * _direction * delta
	# Exit off the opposite side — clean leave, no death.
	if _direction > 0.0 and global_position.x > screensize.x + SIZE_PX:
		_leave()
	elif _direction < 0.0 and global_position.x < -SIZE_PX:
		_leave()


func _offscreen_majority() -> bool:
	# Returns true when the cruiser's centre is more than 51% outside the
	# playfield band, so the turret should stop firing.
	var half: float = SIZE_PX * 0.51
	return global_position.x < Playfield.X_MIN + half \
		or global_position.x > Playfield.X_MAX - half


func _tick_turret(delta: float) -> void:
	_turret_can_fire = not _offscreen_majority()

	var player := find_player()
	if player and _turret_node and is_instance_valid(_turret_node):
		var dir: Vector2 = (player.global_position - _turret_node.global_position).normalized()
		var target_rot: float = atan2(dir.y, dir.x) + PI * 0.5
		var diff := angle_difference(_turret_rot, target_rot)
		_turret_rot += clamp(diff, -ROTATION_SPEED * delta, ROTATION_SPEED * delta)
		_turret_node.rotation = _turret_rot

	if not _turret_can_fire:
		return
	_fire_t += delta
	if _fire_t >= FIRE_INTERVAL:
		var player2 := find_player()
		if player2:
			var dir2: Vector2 = (player2.global_position - _turret_node.global_position).normalized()
			var target2: float = atan2(dir2.y, dir2.x) + PI * 0.5
			if abs(angle_difference(_turret_rot, target2)) < AIM_TOLERANCE:
				_fire_t = 0.0
				_shoot_turret()


func _shoot_turret() -> void:
	var fire_dir := Vector2(cos(_turret_rot - PI * 0.5), sin(_turret_rot - PI * 0.5))
	var b = EnemyBulletScene.instantiate()
	if "variant" in b:
		b.variant = PlasmaOrbVariant
	get_tree().root.add_child(b)
	var spawn_pos: Vector2 = _turret_node.global_position
	if b.has_method("start"):
		b.start(spawn_pos, fire_dir)
	else:
		b.global_position = spawn_pos
		if "velocity" in b:
			b.velocity = fire_dir * BULLET_SPEED


# ---- Death sequence --------------------------------------------------------

func explode() -> void:
	if _dying:
		return
	if _shield_ring and is_instance_valid(_shield_ring):
		_shield_ring.visible = false
	_dying = true
	_descending = true
	set_deferred("monitorable", false)

	# Stop horizontal movement.
	_traverse_speed = 0.0

	# Disable turret.
	_turret_can_fire = false
	if _turret_node and is_instance_valid(_turret_node):
		_turret_node.visible = false

	# Attach engine torch pointing upward (nozzle at top of ship).
	_attach_death_torch()
	_attach_death_smoke()

	# Play the death SFX immediately (detached so it outlives queue_free).
	if has_node("EnemyDie"):
		var SfxCls = load("res://scripts/effects/sfx.gd")
		SfxCls.play_node_detached($EnemyDie)


func _attach_death_torch() -> void:
	# Nozzle at the TOP of the ship — negative Y.
	var nozzle := Vector2(0.0, -32.0)
	var EngineTorchScript = load("res://scripts/effects/engine_torch.gd")
	var torch: ColorRect = EngineTorchScript.new()
	torch.name = "DeathTorch"
	var plume_size := Vector2(24, 32)
	torch.size = plume_size
	# Position: top-centre of nozzle. attach_to_player sets position as
	# nozzle - Vector2(plume_size.x * 0.5, 0). We mirror that calculation.
	torch.position = nozzle - Vector2(plume_size.x * 0.5, 0.0)
	torch.pivot_offset = plume_size * 0.5
	# rotation = 0 so the flame extends UPWARD (shader tip naturally goes
	# toward lower UV i.e. screen-up without the PI flip that player uses).
	torch.rotation = 0.0
	torch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	torch.color = Color(0, 0, 0, 0)
	torch.z_index = 1
	var mat := ShaderMaterial.new()
	mat.shader = load("res://graphics/torch_fire.gdshader")
	mat.set_shader_parameter("pixelSize", 0.08)
	mat.set_shader_parameter("toColor",    Color.html("894400"))
	mat.set_shader_parameter("fromColor",  Color.html("f06007"))
	mat.set_shader_parameter("sparkColor", Color.html("ffa435"))
	mat.set_shader_parameter("smokeColor", Color.html("050505"))
	mat.set_shader_parameter("speed",      2.5)
	mat.set_shader_parameter("sparkSpeed", 0.4)
	mat.set_shader_parameter("aspectRatio", plume_size.x / plume_size.y)
	# Force max flame size — not HP-gated for death sequence.
	mat.set_shader_parameter("size", Vector2(0.4, 1.0))
	torch.material = mat
	torch.visible = true
	add_child(torch)


func _attach_death_smoke() -> void:
	var SmokeScript = load("res://scripts/effects/damage_smoke_trail.gd")
	var smoke: Node2D = SmokeScript.new()
	smoke.name = "DeathSmoke"
	# emit_local: top of ship in local coords so smoke starts from the top.
	smoke.emit_local = Vector2(0.0, -32.0)
	# Force active: set activate_below to 0.0 so damage_level=1.0 always passes.
	smoke.activate_below = 0.0
	add_child(smoke)
	# _player must be set after add_child so the scene tree is available for
	# the Line2D parent attachment in DamageSmokeTrail._ready().
	smoke._player = self
	# Drive damage_level to 1.0 so the trail renders at full intensity.
	smoke._damage_level = 1.0


func _tick_descent(delta: float) -> void:
	global_position.y += DESCENT_SPEED * delta

	# Off the bottom of the screen — trigger final death burst.
	if global_position.y > 300.0:
		_finish_death()


func _finish_death() -> void:
	# Guard: may be called while already queued for free.
	if not is_instance_valid(self):
		return
	set_process(false)

	var ExplosionFxScript = load("res://scripts/effects/explosion_fx.gd")
	var DeathDustScript   = load("res://scripts/effects/death_dust.gd")
	ExplosionFxScript.burst(global_position, 8, 32.0, 0.1)
	DeathDustScript.play(global_position, display_scale)

	var parent: Node = get_tree().current_scene
	if parent == null:
		parent = get_tree().root
	_spawn_debris(parent, global_position, display_scale)

	died.emit(bounty_value)
	queue_free()

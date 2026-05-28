extends "res://scripts/enemies/enemy_base.gd"

# Intermediate class for pattern-driven enemies. Adds slots for movement
# and shoot behavior Resources. Handles the wiring, loop dispatch, and
# common state around parallax recycling.

const Playfield = preload("res://scripts/playfield.gd")

# Pattern Resources. Directors wire these up via WaveSpec, or scripts
# set them directly in _ready().
@export var movement: Resource = null
@export var shoot_pattern: Resource = null

# Shoot loop state. Managed by _on_shoot_tick().
var _shoot_accum: float = 0.0

# Parallax recycling. When we exit the bottom of the screen, we flip
# back to the top instead of freeing (Roman, 2026-05-16 "Parallax
# recycle" pass). Only active when offscreen_mode == CYCLE_BOTTOM and
# movement pattern declares a parallax period.
var _cycling: bool = false
var _pattern: Resource = null  # Deprecated: use `movement` instead


func _ready() -> void:
	# Consume the deprecated `_pattern` slot if present (legacy compatibility).
	if _pattern != null:
		movement = _pattern
		_pattern = null
	super._ready()
	if movement != null:
		movement.on_start(self)
	# Wire up the shoot timer if the scene has one.
	if has_node("ShootTimer"):
		$ShootTimer.timeout.connect(_on_shoot_tick)


func _process(delta: float) -> void:
	if _dying:
		return
	# Movement: compute step from the pattern, apply it.
	if movement != null:
		var step: Vector2 = movement.compute_step(self, delta)
		global_position += step
	super._process(delta)


func start(pos: Vector2) -> void:
	# Called by the director when this enemy enters the playfield.
	# Allows bespoke placement logic (e.g., minelayer spawning sideways).
	# Default: use the pos argument.
	global_position = pos


func _on_shoot_tick() -> void:
	# Fired by ShootTimer each tick. Delegates to the shoot_pattern Resource.
	if shoot_pattern == null or _dying:
		return
	shoot_pattern.tick(self)


func _on_offscreen() -> void:
	# Override EnemyBase's offscreen handler to support parallax recycling.
	# When moving downward + max_speed and parallax_period are set, we can
	# recycle the enemy from the top instead of freeing it.
	if offscreen_mode == OffscreenMode.CYCLE_BOTTOM and _can_recycle():
		_cycle_to_top()
	else:
		super._on_offscreen()


func _can_recycle() -> bool:
	# Check if movement pattern supports recycling (has parallax_period).
	if movement == null or not "parallax_period" in movement:
		return false
	var period: float = movement.get("parallax_period")
	return period > 0.0


func _cycle_to_top() -> void:
	# Reset position + state for a fresh loop.
	_cycling = true
	if movement != null and "on_recycle" in movement:
		movement.on_recycle(self)
	# Move to a mirrored Y position so the next pass is seamless.
	global_position.y = -global_position.y
	health = max_health
	shield = max_shield
	_cycling = false


func _setup_shield_ring() -> void:
	# Called by base class when max_shield > 0. Build a flat ring mesh.
	if _shield_ring != null and is_instance_valid(_shield_ring):
		return
	_shield_mat = ShaderMaterial.new()
	_shield_mat.shader = SHIELD_SHADER
	_shield_mat.set_shader_parameter("ring_color", Color(0.2, 0.8, 1.0, 0.8))
	_shield_mat.set_shader_parameter("thickness", 0.1)
	_shield_ring = ColorRect.new()
	_shield_ring.custom_minimum_size = Vector2(shield_ring_size * 2.0, shield_ring_size * 2.0)
	_shield_ring.material = _shield_mat
	_shield_ring.z_index = 3
	_shield_ring.z_as_relative = false
	_shield_ring.anchor_left = 0.5
	_shield_ring.anchor_top = 0.5
	_shield_ring.offset_left = -shield_ring_size
	_shield_ring.offset_top = -shield_ring_size
	add_child(_shield_ring)


func find_player() -> Node:
	# Shared helper for enemies that need to locate the player.
	for n in get_tree().get_nodes_in_group("player"):
		return n
	return null

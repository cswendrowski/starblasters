class_name MissileCruiser
extends Node2D

# MISSILE CRUISER (Roman, 2026-05-31) — a background "mortar ship" that
# traverses vertically through the MID parallax depth and rains AoE missiles
# onto the playfield. It is UNATTACKABLE and deliberately NOT a member of the
# "enemies" group: director._hazards_present()/_live_combatants_present()
# would otherwise treat it as a live combatant and freeze wave-clear forever.
#
# It is a plain world-space Node2D. The combat camera is centred on
# (240,135) of the 480x270 viewport, so world coords == playfield coords; its
# telegraph circles + missiles + explosions all spawn in plain world space
# and are parented to the WORLD (get_tree().root), never to the cruiser, so
# they outlive it when it traverses off the far edge.
#
# FAKED MID-DEPTH (confirmed faked, not literal CanvasLayer parenting): the
# node is added as a child of the scene's `Backdrop` Node2D (above the
# parallax layers, below the ships, in world space) via
# add_to_backdrop()/boss_base.add_world_node_above_backdrop. It is scaled DOWN
# and its BODY sprite tinted toward a desaturated background blue/grey so it
# reads as living in the mid layer. The engine-glow sprite is left bright
# (additive + shader bloom) so the tint never dims the glow.
#
# STRUCTURAL TEMPLATE: scripts/enemies/tether_mine.gd (fly-to-fixed-point +
# phase state machine + per-frame _draw), with the EnemyBase inheritance
# stripped out.

const GlowShaderFx = preload("res://scripts/effects/glow_shader_fx.gd")
const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")
# Mix-toward-bg-color shader (true desaturation; modulate can only dim/cool).
const DEPTH_TINT_SHADER: Shader = preload("res://graphics/enemies/missile_cruiser_depth_tint.gdshader")

# --- Faked-depth tuning (designer-facing) -----------------------------------
# Visual scale of the whole cruiser. <1 sells "further away / mid layer".
@export var cruiser_scale: float = 0.7
# How far (0..1) the BODY sprite is tinted toward the background color. Applied
# to the body Sprite2D only — the engine glow stays bright.
@export var bg_tint_amount: float = 0.45
# Desaturated background blue/grey the body tints toward.
@export var bg_tint_color: Color = Color(0.42, 0.50, 0.62, 1.0)
# Extra emissive brightness on the engine-glow sprite (frame 1). >1 = additive
# overdrive on top of the shader bloom halo.
@export var glow_brightness: float = 1.8

# --- Traverse tuning --------------------------------------------------------
# Slow vertical traverse. If derive_speed_from_cycle is true this is treated as
# a CEILING and the actual speed is clamped down so one full salvo lands while
# the full sprite is on-screen.
@export var traverse_speed: float = 50.0
# When true, clamp traverse_speed so the on-screen dwell comfortably exceeds
# one mark->fire->explode cycle (so the explosions LAND on-screen).
@export var derive_speed_from_cycle: bool = true
# Safety margin (seconds) added to the cycle time when deriving the speed.
@export var cycle_dwell_margin: float = 1.0

# --- Attack-cycle tuning ----------------------------------------------------
@export var zone_count: int = 4              # marks/missiles per salvo
@export var telegraph_time: float = 1.2      # MARK phase duration (s)
@export var missile_travel_time: float = 0.8 # missile fly-to-zone time (s)
@export var fuse_time: float = 0.4           # delay after arrival before boom
@export var aoe_radius: float = 24.0         # explosion damage radius (px)
@export var explosion_damage: int = 1        # damage per player in radius
@export var cooldown_time: float = 2.0       # gap between salvos (s)

# Y range (world/viewport) the zone points are picked within. X is always
# clamped to the gameplay band via Playfield.X_MIN/X_MAX. Kept inside 0..270.
@export var zone_y_min: float = 40.0
@export var zone_y_max: float = 240.0

# --- Telegraph circle visual ------------------------------------------------
const TELEGRAPH_COLOR := Color(1.0, 0.15, 0.15, 0.5)  # filled red, alpha 0.5
const TELEGRAPH_PULSE_HZ: float = 3.0
const TELEGRAPH_PULSE_PX: float = 5.0                  # radius pulse amplitude

# --- Sprite layout ----------------------------------------------------------
const SPRITE_PX: float = 64.0   # source frame is 64x64
const BODY_FRAME: int = 0
const GLOW_FRAME: int = 1

enum Phase { ENTERING, MARK, FIRE_WAIT, COOLDOWN }

var _phase: int = Phase.ENTERING
var _phase_t: float = 0.0
var _direction: int = 1          # +1 = moving down, -1 = moving up
var _half_height: float = 0.0    # scaled half sprite height (for on-screen gate)
var _did_first_salvo: bool = false
var _live_telegraphs: Array = [] # active telegraph circle nodes this salvo
var _missiles_remaining: int = 0 # outstanding missiles this salvo

@onready var _body: Sprite2D = get_node_or_null("Body") as Sprite2D
@onready var _glow: Sprite2D = get_node_or_null("Glow") as Sprite2D


func _ready() -> void:
	_half_height = SPRITE_PX * 0.5 * cruiser_scale

	# Pick entry edge (top or bottom) and park the sprite just off it.
	if randf() < 0.5:
		_direction = 1   # enter from top, move down
		global_position = Vector2(global_position.x, -_half_height - 8.0)
	else:
		_direction = -1  # enter from bottom, move up
		global_position = Vector2(global_position.x, 270.0 + _half_height + 8.0)

	scale = Vector2(cruiser_scale, cruiser_scale)

	# Tint the BODY sprite only — never the root (would dim the glow + halo).
	# Use a mix-toward-color SHADER, not modulate: modulate multiplies and can
	# only dim/cool the saturated-red art; the shader lerps RGB toward the flat
	# background color so the ship genuinely desaturates and reads mid-depth.
	if _body != null:
		_body.frame = BODY_FRAME
		var mat := ShaderMaterial.new()
		mat.shader = DEPTH_TINT_SHADER
		mat.set_shader_parameter("bg_tint", bg_tint_color)
		mat.set_shader_parameter("amount", bg_tint_amount)
		_body.material = mat

	# Engine glow: bright emissive frame + shader bloom halo, full brightness.
	if _glow != null:
		_glow.frame = GLOW_FRAME
		_glow.modulate = Color(glow_brightness, glow_brightness, glow_brightness, 1.0)
		# apply() parents the halo as a sibling under the host's parent, so the
		# host must already be in-tree — it is (we're inside the scene now).
		GlowShaderFx.apply(_glow)

	if derive_speed_from_cycle:
		traverse_speed = _derive_traverse_speed()

	_phase = Phase.ENTERING
	_phase_t = 0.0


# Cycle through EXPLODE = telegraph + travel + fuse (cooldown need NOT fit).
# Dwell (full sprite on-screen) = band_height / speed, where the band is the
# vertical range over which the sprite is FULLY on-screen.
#   band_height = 270 - 2*half_height = 270 - 64*scale
# Solve speed so dwell >= cycle + margin.
func _derive_traverse_speed() -> float:
	var cycle: float = telegraph_time + missile_travel_time + fuse_time
	var band_height: float = 270.0 - 2.0 * _half_height
	var max_speed_for_dwell: float = band_height / (cycle + cycle_dwell_margin)
	return minf(traverse_speed, max_speed_for_dwell)


func _is_fully_onscreen() -> bool:
	var top: float = global_position.y - _half_height
	var bottom: float = global_position.y + _half_height
	return top >= 0.0 and bottom <= 270.0


func _process(delta: float) -> void:
	# Always traverse (purely visual movement, no collision).
	global_position += Vector2(0.0, traverse_speed * delta * float(_direction))

	# Free ourselves once fully off the far edge.
	if _direction > 0 and global_position.y - _half_height > 270.0:
		queue_free()
		return
	if _direction < 0 and global_position.y + _half_height < 0.0:
		queue_free()
		return

	match _phase:
		Phase.ENTERING:
			# Begin the first MARK the instant the full sprite is on-screen, so
			# a salvo is guaranteed to land while visible.
			if _is_fully_onscreen():
				_begin_mark()
		Phase.MARK:
			_phase_t += delta
			if _phase_t >= telegraph_time:
				_begin_fire()
		Phase.FIRE_WAIT:
			# Missiles + their fuses run autonomously; we just wait for the
			# salvo to finish, then cool down.
			if _missiles_remaining <= 0:
				_phase = Phase.COOLDOWN
				_phase_t = 0.0
		Phase.COOLDOWN:
			_phase_t += delta
			if _phase_t >= cooldown_time:
				# Only start another salvo if still fully on-screen.
				if _is_fully_onscreen():
					_begin_mark()
				else:
					_phase = Phase.ENTERING


# ---- Attack cycle ----------------------------------------------------------

func _begin_mark() -> void:
	_did_first_salvo = true
	_phase = Phase.MARK
	_phase_t = 0.0
	_clear_telegraphs()
	for _i in range(zone_count):
		var zone: Vector2 = _pick_zone_point()
		var circle: Node2D = _TelegraphCircle.new()
		circle.setup(zone, aoe_radius)
		_world_parent().add_child(circle)
		# Store [node, zone] so FIRE can reuse the exact same point.
		_live_telegraphs.append({"node": circle, "zone": zone})


func _begin_fire() -> void:
	_phase = Phase.FIRE_WAIT
	_phase_t = 0.0
	_missiles_remaining = 0
	var launch: Vector2 = _launch_point()
	for entry in _live_telegraphs:
		var tdict: Dictionary = entry
		var zone: Vector2 = tdict["zone"]
		var circle: Node2D = tdict["node"]
		var missile: Node2D = _Missile.new()
		missile.setup(
			launch, zone, missile_travel_time, fuse_time,
			aoe_radius, explosion_damage, circle
		)
		_world_parent().add_child(missile)
		_missiles_remaining += 1
		# Each missile calls back when it detonates so we know the salvo is done.
		missile.detonated.connect(_on_missile_detonated)
	# Telegraph circles are now owned by their missiles (cleared on detonation).
	_live_telegraphs.clear()


func _on_missile_detonated() -> void:
	_missiles_remaining = maxi(0, _missiles_remaining - 1)


func _clear_telegraphs() -> void:
	for entry in _live_telegraphs:
		var tdict: Dictionary = entry
		var n: Node = tdict.get("node", null)
		if n != null and is_instance_valid(n):
			n.queue_free()
	_live_telegraphs.clear()


# Pick a random point in the gameplay band (X via Playfield, Y in the
# configured band). These are world coords directly.
func _pick_zone_point() -> Vector2:
	var x: float = randf_range(Playfield.X_MIN, Playfield.X_MAX)
	var y: float = randf_range(zone_y_min, zone_y_max)
	return Vector2(x, y)


# Launch point: a child Marker2D named "LaunchPoint" if present, else the
# sprite centre (the cruiser's world position).
func _launch_point() -> Vector2:
	var marker: Marker2D = get_node_or_null("LaunchPoint") as Marker2D
	if marker != null:
		return marker.global_position
	return global_position


# Parent for world-space children (telegraphs/missiles). Prefer the live scene
# root so they survive the cruiser; fall back to the tree root.
func _world_parent() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return self
	var cs: Node = tree.current_scene
	if cs != null:
		return cs
	return tree.root


# ============================================================================
# Telegraph circle — pulsing 50%-transparent filled red disc in world space.
# ============================================================================
class _TelegraphCircle extends Node2D:
	var _radius: float = 24.0
	var _pulse_t: float = 0.0

	func setup(world_pos: Vector2, radius: float) -> void:
		global_position = world_pos
		_radius = radius

	func _process(delta: float) -> void:
		_pulse_t += delta
		queue_redraw()

	func _draw() -> void:
		var pulse: float = sin(_pulse_t * TAU * MissileCruiser.TELEGRAPH_PULSE_HZ)
		var r: float = _radius + pulse * MissileCruiser.TELEGRAPH_PULSE_PX
		var a: float = MissileCruiser.TELEGRAPH_COLOR.a * (0.7 + 0.3 * (0.5 + 0.5 * pulse))
		var col := Color(
			MissileCruiser.TELEGRAPH_COLOR.r,
			MissileCruiser.TELEGRAPH_COLOR.g,
			MissileCruiser.TELEGRAPH_COLOR.b,
			a
		)
		draw_circle(Vector2.ZERO, maxf(1.0, r), col)


# ============================================================================
# Missile — flies from launch to UNDER its zone point over travel_time
# (tether-mine fly-to-fixed-point), waits a fuse, then explodes: AoE damage to
# players in radius + ExplosionFx + clears its telegraph circle.
# ============================================================================
class _Missile extends Node2D:
	signal detonated

	const MISSILE_COLOR := Color(1.0, 0.75, 0.2, 1.0)
	const MISSILE_LEN: float = 7.0
	const MISSILE_WID: float = 2.5

	var _from: Vector2 = Vector2.ZERO
	var _to: Vector2 = Vector2.ZERO
	var _travel: float = 0.8
	var _fuse: float = 0.4
	var _radius: float = 24.0
	var _damage: int = 1
	var _telegraph: Node2D = null

	var _t: float = 0.0
	var _arrived: bool = false
	var _fuse_t: float = 0.0
	var _detonated: bool = false
	var _heading: float = 0.0

	func setup(
		from: Vector2, to: Vector2, travel: float, fuse: float,
		radius: float, damage: int, telegraph: Node2D
	) -> void:
		_from = from
		_to = to
		_travel = maxf(0.05, travel)
		_fuse = maxf(0.0, fuse)
		_radius = radius
		_damage = damage
		_telegraph = telegraph
		global_position = from
		_heading = (to - from).angle()

	func _process(delta: float) -> void:
		if _detonated:
			return
		if not _arrived:
			_t += delta
			var u: float = clampf(_t / _travel, 0.0, 1.0)
			# Ease-out so it decelerates into the zone (reads like a lobbed shot).
			var eased: float = 1.0 - pow(1.0 - u, 2.0)
			var prev: Vector2 = global_position
			global_position = _from.lerp(_to, eased)
			var step: Vector2 = global_position - prev
			if step.length_squared() > 0.0001:
				_heading = step.angle()
			queue_redraw()
			if u >= 1.0:
				_arrived = true
				_fuse_t = 0.0
		else:
			_fuse_t += delta
			queue_redraw()
			if _fuse_t >= _fuse:
				_detonate()

	func _detonate() -> void:
		if _detonated:
			return
		_detonated = true
		# AoE: damage any player within radius. take_damage auto-scales with
		# sectors + handles i-frames/shield.
		var tree: SceneTree = get_tree()
		if tree != null:
			var players: Array = tree.get_nodes_in_group("player")
			for p in players:
				if not (p is Node2D):
					continue
				var pn: Node2D = p as Node2D
				if pn.global_position.distance_to(_to) <= _radius:
					if pn.has_method("take_damage"):
						pn.take_damage(_damage)
		# VFX at the zone point.
		ExplosionFx.play(_to, 1.0)
		# Clear this zone's telegraph circle.
		if _telegraph != null and is_instance_valid(_telegraph):
			_telegraph.queue_free()
		detonated.emit()
		queue_free()

	func _draw() -> void:
		if _detonated:
			return
		# Small warhead drawn along its heading: a bright capsule with a flame.
		var dir := Vector2.RIGHT.rotated(_heading)
		var nose: Vector2 = dir * MISSILE_LEN
		var tail: Vector2 = dir * -MISSILE_LEN
		if not _arrived:
			# Body line.
			draw_line(tail, nose, MISSILE_COLOR, MISSILE_WID)
			# Exhaust flicker behind the tail.
			var flame: Vector2 = tail + dir * -(3.0 + randf() * 2.0)
			draw_line(tail, flame, Color(1.0, 0.45, 0.1, 0.85), MISSILE_WID)
		else:
			# Fuse: pulse a warning dot at the zone so the player reads "incoming".
			var pulse: float = 0.5 + 0.5 * sin(_fuse_t * 30.0)
			draw_circle(Vector2.ZERO, 2.0 + pulse * 1.5, Color(1.0, 0.9, 0.4, 0.9))

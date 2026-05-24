extends "res://scripts/enemies/enemy_base.gd"

# Tether Mine — Commander's signature attack (replaces the black-hole
# sequence, 2026-05-23). Commander launches one of these toward a target
# point in the upper playfield. On arrival the mine plays its smart-mine
# activation animation (F0 -> F1 -> F2) and then drags the PLAYER ONLY
# toward itself with a squiggly red beam telegraph. The pull ends when:
#   - the player kills the mine,
#   - the player physically contacts the mine (it explodes), or
#   - active_duration elapses (mine fades out).
#
# Bullets and other enemies are NOT pulled — only the player.
#
# Sprite is the shared smart-mine 3-frame strip (16×16 each):
#   F0 = dormant (used during the TRAVELING phase),
#   F1 = transition (brief, during ARRIVING),
#   F2 = active (during ACTIVE / beam phase).

enum Phase { TRAVELING, ARRIVING, ACTIVE }

# Travel
@export var travel_speed: float = 90.0
@export var arrival_threshold: float = 4.0

# Activation transition
@export var transition_time: float = 0.18

# Pull (matches black-hole defaults — only applied to the player).
@export var pull_strength: float = 1100.0
@export var pull_radius: float = 140.0
@export var player_pull_multiplier: float = 0.35
@export var max_extra_speed: float = 1500.0

# Active phase duration (matches old black_hole_lifetime).
@export var active_duration: float = 4.5
@export var fade_out_time: float = 0.4

# Damage dealt when the player physically contacts the mine.
@export var contact_damage: int = 2

# Beam visual.
const BEAM_AMPLITUDE_PX: float = 5.0
const BEAM_FREQUENCY: float = 8.0      # radians per second (animates squiggle)
const BEAM_SEGMENTS: int = 24
const BEAM_WIDTH: float = 2.0
const BEAM_COLOR: Color = Color(1.0, 0.2, 0.2, 0.95)

var _phase: int = Phase.TRAVELING
var _phase_t: float = 0.0
var _target: Vector2 = Vector2.ZERO
var _active_t: float = 0.0
var _beam_t: float = 0.0
var _fading: bool = false


func _ready() -> void:
	max_health = 6
	is_hazard = true
	bounty_value = 0
	display_scale = 1.0
	auto_rotate = false
	offscreen_mode = OffscreenMode.NONE
	super._ready()
	if has_node("Sprite2D"):
		$Sprite2D.frame = 0


# Boss calls start(spawn_pos, target_pos). Falls back to the EnemyBase
# convention if a caller passes only one arg.
func start(pos: Vector2, target: Vector2 = Vector2.INF) -> void:
	position = pos
	if target == Vector2.INF:
		_target = pos
	else:
		_target = target
	_phase = Phase.TRAVELING


func _process(delta: float) -> void:
	if _dying or _fading:
		return
	match _phase:
		Phase.TRAVELING:
			var to_target: Vector2 = _target - position
			var dist: float = to_target.length()
			if dist <= arrival_threshold or dist <= travel_speed * delta:
				position = _target
				_phase = Phase.ARRIVING
				_phase_t = 0.0
				if has_node("Sprite2D"):
					$Sprite2D.frame = 1
			else:
				position += to_target / dist * travel_speed * delta
		Phase.ARRIVING:
			_phase_t += delta
			if _phase_t >= transition_time:
				_phase = Phase.ACTIVE
				_active_t = 0.0
				_beam_t = 0.0
				if has_node("Sprite2D"):
					$Sprite2D.frame = 2
		Phase.ACTIVE:
			_active_t += delta
			_beam_t += delta
			queue_redraw()
			if _active_t >= active_duration:
				_begin_fade_out()


func _physics_process(delta: float) -> void:
	if _dying or _fading:
		return
	if _phase != Phase.ACTIVE:
		return
	var players := get_tree().get_nodes_in_group("player")
	for p in players:
		if not (p is Node2D):
			continue
		var pn: Node2D = p as Node2D
		var to_center: Vector2 = global_position - pn.global_position
		var dist: float = to_center.length()
		if dist < 1.0:
			continue
		# Same falloff shape as black_hole.gd: strongest at the edge with a
		# soft inner plateau so we don't sling the player into the mine.
		var t_norm: float = clamp(dist / pull_radius, 0.0, 1.0)
		var falloff: float = 1.0 - t_norm
		var inner_soft: float = smoothstep(0.0, 0.15, t_norm)
		var mult: float = falloff * inner_soft * player_pull_multiplier
		var step: Vector2 = (to_center / dist) * pull_strength * mult * delta
		var max_step: float = max_extra_speed * delta
		if step.length() > max_step:
			step = step.normalized() * max_step
		pn.global_position += step


func _draw() -> void:
	if _phase != Phase.ACTIVE or _fading:
		return
	var p := find_player()
	if p == null or not (p is Node2D):
		return
	var target_local: Vector2 = (p as Node2D).global_position - global_position
	var length_sq: float = target_local.length_squared()
	if length_sq < 1.0:
		return
	var length: float = sqrt(length_sq)
	var dir: Vector2 = target_local / length
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var points := PackedVector2Array()
	for i in range(BEAM_SEGMENTS + 1):
		var u: float = float(i) / float(BEAM_SEGMENTS)
		# Taper the wave at both endpoints so the beam attaches cleanly to
		# the mine and the player rather than wiggling off them.
		var taper: float = sin(u * PI)
		var amp: float = sin(_beam_t * BEAM_FREQUENCY + float(i) * 0.6) * BEAM_AMPLITUDE_PX * taper
		var pt: Vector2 = dir * (length * u) + perp * amp
		points.push_back(pt)
	draw_polyline(points, BEAM_COLOR, BEAM_WIDTH)


# Player contact — only meaningful in ACTIVE phase per the brief, but the
# mine still does its damage on contact in any phase (it's a mine).
func _on_area_entered(area: Area2D) -> void:
	if _dying or _fading:
		return
	if area == null or not area.is_in_group("player"):
		return
	if area.has_method("take_damage"):
		area.take_damage(contact_damage)
	# Contact always pops the mine — that ends the pull in ACTIVE phase
	# and just removes it cleanly in earlier phases.
	explode()


# Death (player kill OR contact explode). EnemyBase.explode() handles the
# debris + VFX; we just stop drawing the beam first.
func explode() -> void:
	if _dying:
		return
	queue_redraw()
	super.explode()


func _begin_fade_out() -> void:
	if _fading or _dying:
		return
	_fading = true
	queue_redraw()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, fade_out_time)
	tw.tween_callback(queue_free)

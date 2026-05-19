## Black hole — visual effect with optional kinematic gravity well.
##
## Default config (pull_strength = 0): purely decorative backdrop. Set
## pull_strength > 0 to turn it into a hazard / attack that pulls bullets,
## enemies, and the player toward its centre. Damage is out of scope — this
## only translates positions.
##
## Spawn by instancing `res://scenes/hazards/black_hole.tscn` (or the smaller
## `black_hole_attack.tscn` variant the boss spawns) and adding to scene.
extends Node2D

## Visual reach (px). Drives both the shader quad size and the lens radius.
@export var radius: float = 320.0
## Total lifetime in seconds (including fade-in and fade-out).
@export var lifetime: float = 12.0
## Seconds of opacity ramp at the start and end of life.
@export var fade_time: float = 1.2
## Visual scale of the shader quad (multiplies the base sprite size).
@export var visual_scale: float = 1.4
## Acceleration at the well's edge in px / s^2 toward the centre. 0 = backdrop.
@export var pull_strength: float = 0.0
## Scales the pull for anything in the `player` group (gentler on the player).
@export var player_pull_multiplier: float = 0.35
## Hard cap on per-frame displacement so a low framerate can't teleport things.
@export var max_extra_speed: float = 1500.0
## When > 0, the visual scales from 0 → final over this many seconds at the
## start of life. Used by the boss telegraph (charge phase) and the post-fire
## expand pulse (Roman 2026-05-18 "grows while charging, expands after fired").
@export var expand_in_time: float = 0.0
## Color modulation for the visual. Bosses tint the telegraph warm/red so the
## player can read it as "incoming" before the real pull spawns.
@export var visual_modulate: Color = Color(1, 1, 1, 1)

@onready var visual: ColorRect = $Visual
@onready var well: Area2D = $Well if has_node("Well") else null

var _age: float = 0.0

func _ready() -> void:
	# Size the visual quad. The shader treats UV (0..1) as the full effect, so
	# the quad should be ~2*lens_radius across. We use 2.2*radius for headroom.
	var size: float = radius * 2.2 * visual_scale
	visual.size = Vector2(size, size)
	visual.position = -visual.size * 0.5
	visual.modulate = visual_modulate
	var mat := visual.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("fade", 0.0)
	# Pre-scale for the expand_in pulse. If expand_in_time is set, start
	# small and grow over that interval inside _process.
	if expand_in_time > 0.0:
		visual.scale = Vector2.ZERO
	# Size the gravity well to match `radius` unconditionally. Bosses spawn
	# the hole with pull_strength=0 during the charge phase and raise it on
	# detonate (Roman 2026-05-18); if we only assigned the shape when pull
	# was already on, the well would be inert forever. _physics_process is
	# already gated on pull_strength > 0, so a sized-but-idle shape is free.
	if well:
		var shape := CircleShape2D.new()
		shape.radius = radius
		var coll := well.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if coll:
			coll.shape = shape

func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	var fade_in: float = clamp(_age / max(fade_time, 0.001), 0.0, 1.0)
	var fade_out: float = clamp((lifetime - _age) / max(fade_time, 0.001), 0.0, 1.0)
	var fade: float = min(fade_in, fade_out)
	var mat := visual.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("fade", fade)
	# Expand-in pulse — visual scales 0 → 1 over expand_in_time, with a brief
	# overshoot (1.15) at the firing moment so the post-charge release reads as
	# a punchy expansion rather than a soft fade.
	if expand_in_time > 0.0:
		var k: float = clamp(_age / expand_in_time, 0.0, 1.0)
		# Overshoot curve: ease-out with a slight bump near k=1.
		var s: float = 1.0 - pow(1.0 - k, 2.0)
		var overshoot: float = 1.0 + 0.15 * sin(k * PI)
		visual.scale = Vector2(s * overshoot, s * overshoot)

func _physics_process(delta: float) -> void:
	if pull_strength <= 0.0 or well == null:
		return
	# Ramp pull with the same fade curve so the hazard spins up/down smoothly.
	var fade_in: float = clamp(_age / max(fade_time, 0.001), 0.0, 1.0)
	var fade_out: float = clamp((lifetime - _age) / max(fade_time, 0.001), 0.0, 1.0)
	var strength: float = pull_strength * min(fade_in, fade_out)
	var center: Vector2 = global_position
	for area in well.get_overlapping_areas():
		if is_instance_valid(area):
			_apply_pull(area, center, strength, delta)
	for body in well.get_overlapping_bodies():
		if is_instance_valid(body):
			_apply_pull(body, center, strength, delta)

func _apply_pull(node: Node2D, center: Vector2, strength: float, delta: float) -> void:
	var to_center: Vector2 = center - node.global_position
	var dist: float = to_center.length()
	if dist < 1.0:
		return
	var t: float = clamp(dist / radius, 0.0, 1.0)
	# Falloff: strongest at the edge, soft inner plateau so we don't sling
	# things at the singularity.
	var falloff: float = 1.0 - t
	var inner_soft: float = smoothstep(0.0, 0.15, t)
	var mult: float = falloff * inner_soft
	if node.is_in_group("player"):
		mult *= player_pull_multiplier
	var dir: Vector2 = to_center / dist
	var step: Vector2 = dir * strength * mult * delta
	var max_step: float = max_extra_speed * delta
	if step.length() > max_step:
		step = step.normalized() * max_step
	node.global_position += step

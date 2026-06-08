extends ColorRect
class_name EngineTorch

# Procedural torch-fire plume that sits under the player ship at the engine
# nozzle (same source point the damage smoke trail uses). Reads the player's
# horizontal velocity each frame and pushes it into the shader's `windForce`
# so the flame leans opposite the direction of travel (Roman 2026-05-18).

const SHADER_PATH := "res://graphics/torch_fire.gdshader"
const ImpactFx = preload("res://scripts/effects/impact_fx.gd")

# Plume canvas size (px). The shader draws from the bottom-center upward
# with size = vec2(0.05, 0.75) by default — a ~24×32 ColorRect gives a flame
# that's tall enough to read but doesn't dominate the ship sprite.
const PLUME_SIZE := Vector2(24, 32)

# Engine nozzle in PLAYER-LOCAL coords. Roman 2026-05-18: engine pixel
# (8, 14) in the 16×16 ship frame, sprite centered, so player-local
# nozzle = (0, 6). The flame BASE after the 180° flip sits at UV.y=0.25
# of the rect = rect.top + height*0.25. For base at local (0, 6):
#   rect.top + 32*0.25 = 6  →  rect.top = -2
const ENGINE_LOCAL := Vector2(0, 6)
const NOZZLE_OFFSET_DEFAULT := Vector2(0, -4)
# Per-unit nozzle override — bombers etc. supply their own pixel coord.

# Horizontal velocity → windForce gain. Player tops out around ±125 px/s,
# windForce uniform clamps at ±0.5. Positive gain — the rect is rotated
# 180° so screen "right" maps to shader-local "left," and positive
# windForce in shader space becomes screen-left = trail behind rightward
# motion.
const WIND_GAIN: float = 0.0024

# Smoothing on the windForce so a sudden direction flip doesn't snap the
# flame across the screen.
const WIND_SMOOTHING: float = 8.0

# Hull threshold for the flame to be visible. Default 0.5 for enemies
# (engage at 50% hull). Player overrides this to 0.01 so the torch
# activates on the first pip lost (hull_changed spec 2026-05-26).
const ACTIVATE_BELOW_DEFAULT: float = 0.5
var activate_below: float = ACTIVATE_BELOW_DEFAULT

# Flame size ramp (Roman 2026-05-18 "smaller at start, grows toward 0
# hull"). Min = a sliver of the max; lerped between them across the
# damaged range so the flame visibly grows as the player nears death.
# Roman 2026-05-29: floor dropped from (0, 0.5) to (0, 0.25) so a lightly
# damaged ship shows only a faint flame, not a half-strength one.
const FLAME_SIZE_MIN := Vector2(0.0, 0.25)
const FLAME_SIZE_MAX := Vector2(0.4, 1.0)

# Flame opacity (shader `alpha` uniform) scales with damage severity so a
# barely-damaged ship shows a near-transparent flame and a near-dead ship
# shows the full warm torch. Previously `alpha` was left at the shader
# default (0.95) regardless of damage — the binary "worst appearance on
# the first pip" Roman flagged 2026-05-29.
const ALPHA_MIN: float = 0.10
const ALPHA_MAX: float = 0.95

# Severity easing exponent. >1 keeps the bottom of the range subtle (light
# damage barely shows) and back-loads the intensity toward death. ROMAN'S
# TO TUNE. NOTE: the base ship has only 3 hull pips, so the only reachable
# living damaged states are 2/3 (ramp≈0.66) and 1/3 (ramp≈0.32). 1.5 keeps
# 2/3 subtle while letting 1/3 read clearly as critical; squaring (2.0) was
# too aggressive (1/3 only reached ~0.44 severity). Upgraded hulls (Mk.9 =
# 9 pips) get finer granularity and reach deeper into the curve.
const SEVERITY_EXP: float = 1.5

# Severity at/above which the one-shot EXPLOSIVE impact burst fires when
# crossing into damaged. Below this we just fade the flame in quietly —
# the dramatic "ship just got wrecked" flash is reserved for heavy hits
# (Roman 2026-05-29), not every pip. NOTE: with base 3 hull the deepest
# reachable severity is ~0.66, so this fires only when crossing straight
# to 1 pip on a base ship, or on upgraded (more-pip) hulls. ROMAN'S TO TUNE.
const BURST_SEVERITY: float = 0.6

var _player: Node2D = null
var _mat: ShaderMaterial = null
var _last_pos: Vector2 = Vector2.ZERO
var _wind: float = 0.0
var _was_damaged: bool = false   # tracks activate_below threshold crossing


static func attach_to_player(player: Node2D, nozzle: Vector2 = NOZZLE_OFFSET_DEFAULT, p_activate_below: float = ACTIVATE_BELOW_DEFAULT) -> ColorRect:
	var Script = load("res://scripts/effects/engine_torch.gd")
	var torch: ColorRect = Script.new()
	torch.name = "EngineTorch"
	torch.size = PLUME_SIZE
	# Position the ColorRect so its top-center sits at the nozzle.
	torch.position = nozzle - Vector2(PLUME_SIZE.x * 0.5, 0.0)
	# Shader flame grows toward the top of its quad (Y-inverted internally).
	# Without flipping, the tip points BACK at the ship — Roman 2026-05-18.
	# Rotate 180° around the rect's center so the tip extends downward and
	# the base sits at the engine nozzle.
	torch.pivot_offset = PLUME_SIZE * 0.5
	torch.rotation = PI
	torch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	torch.color = Color(0, 0, 0, 0)
	torch.z_index = 1   # in front of the ship sprite (Roman 2026-05-18)
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	# Roman 2026-05-18 settings: chunky pixels + warm torch palette.
	mat.set_shader_parameter("pixelSize", 0.08)
	mat.set_shader_parameter("toColor", Color.html("894400"))
	mat.set_shader_parameter("fromColor", Color.html("f06007"))
	mat.set_shader_parameter("sparkColor", Color.html("ffa435"))
	mat.set_shader_parameter("smokeColor", Color.html("050505"))
	# Roman 2026-05-18 tuning pass.
	mat.set_shader_parameter("speed", 2.5)
	mat.set_shader_parameter("sparkSpeed", 0.4)
	# Plume aspect: rect is 24×32 → 0.75. The shader uses this to keep the
	# fire from squishing on non-square canvases.
	mat.set_shader_parameter("aspectRatio", PLUME_SIZE.x / PLUME_SIZE.y)
	# Flame size ramps with hull damage (Roman 2026-05-18). Half-size at
	# the 50% activation threshold, full size as hull → 0. Updated in
	# _on_hull_changed.
	mat.set_shader_parameter("size", FLAME_SIZE_MIN)
	# Start faint; severity ramp in _on_hull_changed drives this up.
	mat.set_shader_parameter("alpha", ALPHA_MIN)
	# Per-instance randomization (Roman 2026-06-08): without this every torch
	# shares the same TIME + hash pattern and animates in identical lockstep.
	# A random time-phase + seed makes each flame look its own.
	mat.set_shader_parameter("timeOffset", randf_range(0.0, 1000.0))
	mat.set_shader_parameter("seedOffset", randf_range(0.0, 100.0))
	torch.material = mat
	torch._mat = mat
	torch._player = player
	torch._last_pos = player.global_position
	torch.activate_below = p_activate_below
	# Hide until damage threshold met.
	torch.visible = false
	if player.has_signal("hull_changed"):
		player.hull_changed.connect(torch._on_hull_changed)
	player.add_child(torch)
	# Pull current hull immediately so the gate is correct if we're
	# attached mid-combat (capture scenes, etc).
	if "max_hull" in player and "hull" in player:
		torch._on_hull_changed(player.max_hull, player.hull)
	return torch


func _on_hull_changed(max_hull, hull) -> void:
	if max_hull <= 0:
		visible = false
		_was_damaged = false
		return
	var damage_level: float = clamp(1.0 - (float(hull) / float(max_hull)), 0.0, 1.0)
	# Damage severity 0..1 drives both flame size and opacity so the flame
	# grows AND brightens as the ship nears death (Roman 2026-05-29 "scale
	# with severity proportional to hull remaining; light damage = subtle").
	# Eased (SEVERITY_EXP) so the bottom of the range stays subtle — a single
	# pip lost barely shows. Ramps across the whole damaged span
	# [activate_below, 1.0]. ROMAN'S TO TUNE: the easing exponent and the
	# MIN floors below decide how quickly the flame ramps up.
	var ramp: float = clamp((damage_level - activate_below) / (1.0 - activate_below), 0.0, 1.0)
	var severity: float = pow(ramp, SEVERITY_EXP)
	if _mat != null:
		_mat.set_shader_parameter("size", FLAME_SIZE_MIN.lerp(FLAME_SIZE_MAX, severity))
		_mat.set_shader_parameter("alpha", lerp(ALPHA_MIN, ALPHA_MAX, severity))
	var is_damaged: bool = damage_level >= activate_below
	# Threshold-crossing into damage: punch an impact flash at the engine
	# nozzle, then fade the flame in shortly after so the visual reads as
	# "the ship just took serious damage" (Roman 2026-05-18). Only fire the
	# flash for HEAVY hits (severity >= BURST_SEVERITY) — light damage just
	# fades the faint flame in quietly (Roman 2026-05-29).
	if is_damaged and not _was_damaged:
		if severity >= BURST_SEVERITY:
			_trigger_damage_burst()
		else:
			visible = true
	elif not is_damaged and _was_damaged:
		visible = false
	_was_damaged = is_damaged


func _trigger_damage_burst() -> void:
	if _player == null or not is_instance_valid(_player):
		visible = true
		return
	# Spawn the explosive impact flash at the engine pixel in world space.
	# Parent to scene root so it survives if the player moves/dies.
	var burst_pos: Vector2 = _player.to_global(ENGINE_LOCAL)
	var parent: Node = get_tree().current_scene
	if parent == null:
		parent = get_tree().root
	ImpactFx.spawn(parent, burst_pos, Color(1.0, 0.55, 0.20, 1.0), ImpactFx.ImpactKind.EXPLOSIVE)
	# Delay the flame so the flash leads. ~120ms keeps the beat tight.
	visible = false
	get_tree().create_timer(0.12).timeout.connect(_show_after_burst)


func _show_after_burst() -> void:
	# Don't override a subsequent heal that took us back above threshold.
	if _was_damaged:
		visible = true


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or _mat == null:
		return
	if not visible:
		return
	var pos: Vector2 = _player.global_position
	# Horizontal velocity via position delta. Sufficient — we just want a
	# directional cue, not a physics-grade reading.
	var vx: float = 0.0
	if delta > 0.0:
		vx = (pos.x - _last_pos.x) / delta
	_last_pos = pos
	var target_wind: float = clamp(vx * WIND_GAIN, -0.5, 0.5)
	_wind = lerp(_wind, target_wind, clamp(WIND_SMOOTHING * delta, 0.0, 1.0))
	_mat.set_shader_parameter("windForce", _wind)

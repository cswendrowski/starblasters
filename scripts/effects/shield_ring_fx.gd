extends RefCounted

# Shared driver for the hex_shield.gdshader ring, used by BOTH the player (player.gd) and the enemy
# ShieldComponent so the two shields look + behave identically (Roman 2026-07-09). Owns:
#   - the "Sparse Plates" base look (from the Player FX Lab preset),
#   - the charge-fraction adjusters: full shield → bold fill / no flicker, empty → faint fill / full flicker,
#   - the hit flash (white flash + fat lines + low rim, held through the invuln window then resettled),
#   - the regen/steal pulse (the hit_strength ripple), and
#   - collapse / come-online (fade opacity to 0 while shrinking size to 0, and the reverse).
# Preload-referenced (no class_name) for headless class-cache safety, mirroring factions.gd.
# Tween host = the ring node, so every tween auto-kills when the ring frees.

# Player shield cyan (#59d9ff) — also what the sapper's ring shows while it holds STOLEN player shields.
const PLAYER_COLOR := Color(0.349, 0.851, 1.0)

# Base look = the Player FX Lab "Sparse Plates" preset. fill_alpha + flicker are STATE-DRIVEN
# (by charge fraction), so they live in the adjusters below rather than the static base.
const BASE_CELLS := 4.0
# `cells` scales with the ring's PIXEL size so each hex cell stays a constant pixel size (1:1) — no
# blur / bloomed-out blowout as the bubble grows for bigger enemies. BASE_CELLS is the count that reads
# right at REF_RING_SIZE px (the player bubble); line_width/scroll are cell-relative so they follow.
const REF_RING_SIZE := 24.0
const BASE_SCROLL := Vector2(0.08, 0.05)
const BASE_LINE_WIDTH := 0.22
const BASE_RIM_POWER := 1.6
const BASE_DOME := 0.65

# Charge-fraction adjusters (0 = empty, 1 = full).
const FILL_FULL := 0.4
const FILL_LOW := 0.05
const FLICKER_FULL := 0.0
const FLICKER_LOW := 1.0

# Hit flash: white flash colour, opacity to max, flicker off, fat lines, low rim — held for the
# invuln window then eased back to base + the current charge-state adjusters.
const HIT_COLOR := Color(1, 1, 1, 1)
const HIT_LINE_WIDTH := 0.45
const HIT_RIM_POWER := 0.5
const RESETTLE_SECS := 0.28
const PULSE_SECS := 0.35
# Mild HDR output multiplier so the bright hex lines / rim / hit-flash bloom via the WorldEnvironment.
const SHIELD_HDR := 1.6

var _base_color: Color = Color(1, 1, 1, 1)   # the resting shield_color, restored after a hit-flash
var _mat: ShaderMaterial
var _ring: Control              # the ColorRect — scaled for the collapse / come-online
var _online: bool = false
var _alpha_tween: Tween
var _pulse_tween: Tween
var _resettle_tween: Tween


func _init(mat: ShaderMaterial, ring: Control, color: Color) -> void:
	_mat = mat
	_ring = ring
	# Scale from the ring's centre so a collapse shrinks toward the middle, not the top-left corner.
	_ring.pivot_offset = _ring.size * 0.5
	_ring.scale = Vector2.ZERO
	mat.set_shader_parameter("alpha", 0.0)
	mat.set_shader_parameter("hit_strength", 0.0)
	mat.set_shader_parameter("hit_color", HIT_COLOR)
	mat.set_shader_parameter("fill_alpha", FILL_LOW)
	mat.set_shader_parameter("flicker", FLICKER_LOW)
	apply_base()
	set_color(color)


# The static "Sparse Plates" base look (cells / scroll / line / rim / dome) + the HDR bloom multiplier.
# Separated from _init so a dev tool (Player FX Lab) can re-assert the true in-game base for its state
# preview after the look sliders have been tweaked.
func apply_base() -> void:
	if _mat == null:
		return
	var px: float = _ring.size.x if (_ring != null and is_instance_valid(_ring)) else REF_RING_SIZE
	_mat.set_shader_parameter("cells", cells_for(px))
	_mat.set_shader_parameter("scroll", BASE_SCROLL)
	_mat.set_shader_parameter("line_width", BASE_LINE_WIDTH)
	_mat.set_shader_parameter("rim_power", BASE_RIM_POWER)
	_mat.set_shader_parameter("dome", BASE_DOME)
	_mat.set_shader_parameter("hdr", SHIELD_HDR)


# Hex cell COUNT for a given bubble pixel size — a constant pixel-per-cell density (1:1), so the effect
# stays crisp instead of blurring / blooming out as the ring grows. Clamped to a sane range.
static func cells_for(px: float) -> float:
	return clampf(BASE_CELLS * px / REF_RING_SIZE, 2.0, 40.0)


# Set the bubble's pixel size + rescale the resolution-dependent shader params (hex cell count) so it
# keeps its 1:1 pixel density. Recentres the rect + its scale pivot. Use this instead of poking
# `_ring.size` directly so `cells` never falls out of sync with the size.
func set_ring_size(px: float) -> void:
	if _ring == null or not is_instance_valid(_ring) or _mat == null:
		return
	_ring.size = Vector2(px, px)
	_ring.position = -_ring.size * 0.5
	_ring.pivot_offset = _ring.size * 0.5
	_mat.set_shader_parameter("cells", cells_for(px))


func set_color(color: Color) -> void:
	_base_color = color
	if _mat != null:
		_mat.set_shader_parameter("shield_color", color)


# fill_alpha + flicker from the charge fraction. Full → bold fill / steady; empty → faint fill / flickering.
func apply_state(fraction: float) -> void:
	if _mat == null:
		return
	var f := clampf(fraction, 0.0, 1.0)
	_mat.set_shader_parameter("fill_alpha", lerpf(FILL_LOW, FILL_FULL, f))
	_mat.set_shader_parameter("flicker", lerpf(FLICKER_LOW, FLICKER_FULL, f))


# Collapse (fade opacity + shrink size to 0) or come online (fade in + grow back). Duration 0 = instant.
func set_online(online: bool, duration: float) -> void:
	if _mat == null or _ring == null or not is_instance_valid(_ring):
		return
	if online == _online and duration > 0.0:
		return  # already in this state — no redundant transition
	_online = online
	if _alpha_tween and _alpha_tween.is_valid():
		_alpha_tween.kill()
	var a_to := 1.0 if online else 0.0
	var s_to := Vector2.ONE if online else Vector2.ZERO
	if duration <= 0.0:
		_mat.set_shader_parameter("alpha", a_to)
		_ring.scale = s_to
		return
	_alpha_tween = _ring.create_tween().set_parallel(true)
	var a_from := float(_mat.get_shader_parameter("alpha"))
	_alpha_tween.tween_method(
		func(v): _mat.set_shader_parameter("alpha", v), a_from, a_to, duration)
	_alpha_tween.tween_property(_ring, "scale", s_to, duration) \
		.set_trans(Tween.TRANS_BACK if online else Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# The hit_strength ripple pulse — reused for shield regen (one per recovered charge) + bullet-steal.
func pulse() -> void:
	if _mat == null or _ring == null or not is_instance_valid(_ring):
		return
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_mat.set_shader_parameter("hit_strength", 1.0)
	_pulse_tween = _ring.create_tween()
	_pulse_tween.tween_method(
		func(v): _mat.set_shader_parameter("hit_strength", v), 1.0, 0.0, PULSE_SECS) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


# Shield-absorbed hit: pulse + snap to the bright flash state, hold `hold` seconds (the invuln
# window), then resettle to base + the current charge-state adjusters. `fraction` is the shield
# fraction AFTER the hit — a killing hit (fraction 0) only pulses; the collapse owns the fade/shrink.
func hit_flash(fraction: float, hold: float) -> void:
	if _mat == null or _ring == null or not is_instance_valid(_ring):
		return
	pulse()
	if fraction <= 0.0:
		return  # shield broke this hit — set_online(false) drives the collapse
	if _resettle_tween and _resettle_tween.is_valid():
		_resettle_tween.kill()
	# The WHOLE shield goes white for the hit (not just the ripple), held through the invuln window.
	_mat.set_shader_parameter("shield_color", HIT_COLOR)
	_mat.set_shader_parameter("alpha", 1.0)
	_mat.set_shader_parameter("flicker", 0.0)
	_mat.set_shader_parameter("line_width", HIT_LINE_WIDTH)
	_mat.set_shader_parameter("rim_power", HIT_RIM_POWER)
	var flick_to := lerpf(FLICKER_LOW, FLICKER_FULL, clampf(fraction, 0.0, 1.0))
	_resettle_tween = _ring.create_tween().set_parallel(true)
	_resettle_tween.tween_method(
		func(c): _mat.set_shader_parameter("shield_color", c), HIT_COLOR, _base_color, RESETTLE_SECS).set_delay(hold)
	_resettle_tween.tween_method(
		func(v): _mat.set_shader_parameter("line_width", v), HIT_LINE_WIDTH, BASE_LINE_WIDTH, RESETTLE_SECS).set_delay(hold)
	_resettle_tween.tween_method(
		func(v): _mat.set_shader_parameter("rim_power", v), HIT_RIM_POWER, BASE_RIM_POWER, RESETTLE_SECS).set_delay(hold)
	_resettle_tween.tween_method(
		func(v): _mat.set_shader_parameter("flicker", v), 0.0, flick_to, RESETTLE_SECS).set_delay(hold)

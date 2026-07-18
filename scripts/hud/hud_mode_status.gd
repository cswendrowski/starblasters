extends Node2D

# MODE STATUS widget (scenes/hud/hud_mode_status.tscn) — self-contained port of
# ui.gd's Shift-mode meter (2026-07-14). Drop the scene into any HUD layer: it
# finds the player via the "player" group on its own and rebinds after respawn,
# so it can be moved/rearranged freely in the editor with no extra wiring.
#
# Layout contract with the scene:
#   ModeLabel  — mode name, coloured per equipped mode.
#   light1..N  — charge pips, left→right. Only the first `mode_charges_max`
#                are shown. The scene authors 7 (the current Mk-scaled max);
#                the LIT tint is scene-authored too — the script reads the
#                first light's modulate as the lit colour, so tune it in the
#                editor. The off/spent tint stays a script constant.
#   TimerBar   — active-duration fill (value 0..1). The script drives its RIGHT
#                edge so the bar always ends flush with the outer edge of the
#                last visible pip; left/top/bottom stay as authored.

const HudLight = preload("res://scripts/hud/hud_light.gd")

const _MODE_COL_FOCUS := Color(0.4, 0.7, 1.0, 0.9)
const _MODE_COL_PHASE := Color(0.7, 0.45, 1.0, 0.9)
const _MODE_COL_HYPER := Color(1.0, 0.6, 0.2, 0.9)
const _MODE_COL_RUSH := Color(0.4, 1.0, 0.6, 0.9)     # green
const _MODE_COL_REFIRE := Color(1.0, 0.45, 0.45, 0.9) # red
const _MODE_COL_ECHO := Color(0.55, 0.85, 1.0, 0.9)   # cyan
const _MODE_COL_THIEF := Color(0.72, 0.32, 1.0, 0.9)  # purple
const _MODE_COL_REFLECT := Color(0.95, 0.85, 0.35, 0.9) # gold
# mode enum int → [label, colour]. Keep in sync with player.gd ShiftMode.
const _MODE_META := {
	0: ["FOCUS", _MODE_COL_FOCUS],
	1: ["PHASE", _MODE_COL_PHASE],
	2: ["HYPER", _MODE_COL_HYPER],
	3: ["RUSH", _MODE_COL_RUSH],
	4: ["REFIRE", _MODE_COL_REFIRE],
	5: ["ECHO", _MODE_COL_ECHO],
	6: ["THIEF", _MODE_COL_THIEF],
	7: ["REFLECT", _MODE_COL_REFLECT],
}
const _MODE_PIP_OFF := Color(0.2, 0.22, 0.3, 0.7)  # spent/empty charge pip

var _label: Label = null
var _bar: TextureProgressBar = null
var _lights: Array[Sprite2D] = []   # left→right, scene-authored
# Meter body is fixed purple regardless of equipped mode (Roman 2026-07-12) —
# the mode label keeps its per-mode colour, the pips don't swap. The lit tint
# is read from the scene's authored pip modulate in _ready.
var _pip_lit := Color(0.7, 0.45, 1.0, 0.9)
var _prev_charges: int = -1         # for pip-spend flash
var _player_ref: Node = null


func _ready() -> void:
	_label = $ModeLabel
	_bar = $TimerBar
	for child in get_children():
		if child is Sprite2D:
			_lights.append(child)
	if not _lights.is_empty():
		_pip_lit = _lights[0].modulate
	# Duration fill is a 0..1 fraction; the scene's textures render it.
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.value = 0.0
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	# Self-(re)bind: main.gd rebuilds the player node on respawn, so poll for a
	# live one instead of requiring external wiring.
	if _player_ref == null or not is_instance_valid(_player_ref):
		var p := get_tree().get_first_node_in_group("player")
		if p != null:
			bind_player(p)


func bind_player(player: Node) -> void:
	_player_ref = player
	if player == null:
		return
	if player.has_signal("mode_charges_changed") and not player.mode_charges_changed.is_connected(_on_mode_charges_changed):
		player.mode_charges_changed.connect(_on_mode_charges_changed)
	if player.has_signal("mode_duration_changed") and not player.mode_duration_changed.is_connected(_on_mode_duration_changed):
		player.mode_duration_changed.connect(_on_mode_duration_changed)
	if player.has_signal("mode_changed") and not player.mode_changed.is_connected(_on_mode_changed):
		player.mode_changed.connect(_on_mode_changed)
	# Seed to the player's current mode (label/colour), then live charge +
	# duration values.
	if "active_mode" in player:
		_on_mode_changed(int(player.active_mode))
	else:
		_seed_from_player()


# Only draw as many pips as the mode has charges (Roman 2026-07-14): lights
# past `count` are hidden. The scene authors the max the game can roll (7);
# anything beyond that is clamped.
func _set_pip_count(count: int) -> void:
	count = clampi(count, 0, _lights.size())
	for i in _lights.size():
		_lights[i].visible = i < count
	# Bar right edge sits flush with the last visible pip's outer edge.
	if count > 0 and _bar != null:
		_bar.offset_right = _pip_outer_edge(_lights[count - 1])


func _pip_outer_edge(light: Sprite2D) -> float:
	var frame_w := 8.0
	if light.texture != null:
		frame_w = float(light.texture.get_width()) / float(maxi(light.hframes, 1))
	return light.position.x + (frame_w * 0.5 if light.centered else frame_w)


# Discrete charges → light the pips, flash on spend.
func _on_mode_charges_changed(charges: int, max_charges: int) -> void:
	_set_pip_count(max_charges)
	var shown := mini(max_charges, _lights.size())
	for i in shown:
		var pip := _lights[i]
		var on: bool = i < charges
		pip.frame = 1 if on else 0
		pip.modulate = _pip_lit if on else _MODE_PIP_OFF
	# Flash the pip row when a charge is spent (count dropped).
	if _prev_charges >= 0 and charges < _prev_charges:
		for i in shown:
			HudLight.pip_flash(_lights[i])
	_prev_charges = charges


# Active window → fill the duration bar (1.0 at activation, empties as it runs out).
func _on_mode_duration_changed(active_t: float, duration: float) -> void:
	if _bar != null:
		_bar.value = clamp(active_t / max(0.001, duration), 0.0, 1.0)


# Swap label text/colour when the equipped Shift mode changes, then reseed from
# the player's current charge + duration values.
func _on_mode_changed(mode: int) -> void:
	var meta: Array = _MODE_META.get(mode, _MODE_META[0])   # default to FOCUS
	var col: Color = meta[1]
	if _label != null:
		_label.text = String(meta[0])
		_label.add_theme_color_override("font_color", Color(col.r, col.g, col.b, 0.9))
	_prev_charges = -1
	_seed_from_player()


func _seed_from_player() -> void:
	var p = _player_ref
	if p == null or not is_instance_valid(p):
		return
	if "mode_charges" in p and "mode_charges_max" in p:
		_on_mode_charges_changed(int(p.mode_charges), int(p.mode_charges_max))
	if "mode_active_t" in p and "mode_duration" in p:
		_on_mode_duration_changed(float(p.mode_active_t), float(p.mode_duration))

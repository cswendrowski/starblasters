extends Node2D

# SHIELD STATUS widget (scenes/hud/hud_shield_status.tscn) — self-contained
# port of ui.gd's shield pip grid (2026-07-15). Drop the scene into any HUD
# layer: it finds the player via the "player" group on its own and rebinds
# after respawn.
#
# Light contract with the scene: pips are the Sprite2D children of the lights
# container (any plain Node2D child; bare Sprite2D children of the root also
# count), scene order = fill order (rows left→right, top→bottom). Only the
# first `max_shield` pips are shown (clamped to the authored count); the first
# `shield` of those are lit. The LIT tint is scene-authored — the script reads
# the first pip's modulate as the lit colour, so tune it in the editor. The
# grid flashes when a charge is consumed.

const HudLight = preload("res://scripts/hud/hud_light.gd")

const COLOR_OFF := Color(0.18, 0.18, 0.18, 1.0)  # spent charge: neutral dark

var _lights: Array[Sprite2D] = []
var _color_lit := Color(0.35, 0.65, 1.00, 1.0)  # overridden by scene tint
var _flash_target: CanvasItem = null
var _prev_value: int = -1
var _player_ref: Node = null


func _ready() -> void:
	_flash_target = self
	for child in get_children():
		if child is Sprite2D:
			_lights.append(child)
		elif child is Node2D:
			# Lights container: flashing it (not the root) keeps the hit flash
			# off the label.
			_flash_target = child
			for grandchild in child.get_children():
				if grandchild is Sprite2D:
					_lights.append(grandchild)
	if not _lights.is_empty():
		_color_lit = _lights[0].modulate


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
	if player.has_signal("shield_changed") and not player.shield_changed.is_connected(_on_shield_changed):
		player.shield_changed.connect(_on_shield_changed)
	if "max_shield" in player and "shield" in player:
		_on_shield_changed(int(player.max_shield), int(player.shield))


func _on_shield_changed(max_value, value) -> void:
	var count := clampi(int(max_value), 1, _lights.size())
	for i in _lights.size():
		_lights[i].visible = i < count
	var filled := roundi(float(value) / max(float(max_value), 1.0) * float(count))
	for i in count:
		var on: bool = i < filled
		_lights[i].frame = 1 if on else 0
		_lights[i].modulate = _color_lit if on else COLOR_OFF
	# Pip hit flash on damage
	if _prev_value >= 0 and int(value) < _prev_value:
		HudLight.pip_flash(_flash_target)
	_prev_value = int(value)

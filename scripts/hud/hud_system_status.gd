extends Node2D

# SYSTEM STATUS widget (scenes/hud/hud_system_status.tscn) — annunciator lamps
# + FIRE light, self-contained port of ui.gd's annunciator + fire-crit logic
# (2026-07-15). Drop the scene into any HUD layer: it finds the player via the
# "player" group on its own and rebinds after respawn.
#
# Scene contract:
#   Annunciator/"WARN On"   — lit WARN lamp overlay: shown when shields are
#                             down but hull is above half.
#   Annunciator/"DANGER On" — lit DANGER lamp overlay: shown (pulsing at the
#                             danger_pulse.gd rate) when shields are down and
#                             hull is at/below half.
#   The matching "... Off" sprites underneath are the unlit lamp faces and are
#   never touched. Shields up = both overlays hidden.
#   FIRE light — first Sprite2D inside the lights container (plain Node2D
#                child, not the Annunciator): flickers while hull is critical
#                (≤ 50%), dark otherwise.

const HudLight = preload("res://scripts/hud/hud_light.gd")

# DANGER lamp pulse rate — matches danger_pulse.gd PULSE_HZ so the HUD lamp
# pulses in time with the low-hull warning overlay (Roman 2026-06-11).
const ANN_DANGER_PULSE_HZ: float = 1.5

var _warn_on: Sprite2D = null
var _danger_on: Sprite2D = null
var _fire_light: Sprite2D = null
var _pulse_t: float = 0.0
var _hull: int = -1
var _hull_max: int = 1
var _shield: int = 0
var _crit: bool = false
var _player_ref: Node = null


func _ready() -> void:
	_warn_on = get_node_or_null("Annunciator/WARN On") as Sprite2D
	_danger_on = get_node_or_null("Annunciator/DANGER On") as Sprite2D
	for child in get_children():
		if child is Sprite2D or child.name == "Annunciator":
			continue
		if child is Node2D:
			for grandchild in child.get_children():
				if grandchild is Sprite2D:
					_fire_light = grandchild
					break
	# Lamps dark until player state arrives.
	if _warn_on != null:
		_warn_on.visible = false
	if _danger_on != null:
		_danger_on.visible = false


func _process(delta: float) -> void:
	# Self-(re)bind: main.gd rebuilds the player node on respawn, so poll for a
	# live one instead of requiring external wiring.
	if _player_ref == null or not is_instance_valid(_player_ref):
		var p := get_tree().get_first_node_in_group("player")
		if p != null:
			bind_player(p)

	# DANGER lamp pulses at the warning-shader rate while lit, holding full
	# alpha otherwise.
	if _danger_on != null:
		if _danger_on.visible:
			_pulse_t += delta
			_danger_on.self_modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_pulse_t * ANN_DANGER_PULSE_HZ * TAU))
		else:
			_pulse_t = 0.0
			_danger_on.self_modulate.a = 1.0


func bind_player(player: Node) -> void:
	_player_ref = player
	if player == null:
		return
	if player.has_signal("hull_changed") and not player.hull_changed.is_connected(_on_hull_changed):
		player.hull_changed.connect(_on_hull_changed)
	if player.has_signal("shield_changed") and not player.shield_changed.is_connected(_on_shield_changed):
		player.shield_changed.connect(_on_shield_changed)
	if "max_hull" in player and "hull" in player:
		_hull_max = int(player.max_hull)
		_hull = int(player.hull)
	if "shield" in player:
		_shield = int(player.shield)
	_update_state()


func _on_hull_changed(max_value, value) -> void:
	_hull_max = int(max_value)
	_hull = int(value)
	_update_state()


func _on_shield_changed(_max_value, value) -> void:
	_shield = int(value)
	_update_state()


func _update_state() -> void:
	var hull_frac: float = float(_hull) / max(float(_hull_max), 1.0)
	# Annunciator: OK (both dark) while shields are up; WARN when shields are
	# down but hull holds; DANGER when shields are down and hull is critical.
	if _warn_on != null:
		_warn_on.visible = _shield <= 0 and hull_frac > 0.5
	if _danger_on != null:
		_danger_on.visible = _shield <= 0 and hull_frac <= 0.5

	# FIRE light: critical flicker at hull <= 50%.
	var crit: bool = hull_frac <= 0.5 and _hull > 0
	if crit != _crit:
		_crit = crit
		if _fire_light != null:
			if crit:
				_fire_light.frame = 1
				HudLight.apply(_fire_light, HudLight.Pattern.FLICKER)
			else:
				HudLight.stop(_fire_light)
				_fire_light.frame = 0

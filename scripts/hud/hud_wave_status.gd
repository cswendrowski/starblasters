extends Node2D

# WAVE/THREAT STATUS widget (scenes/hud/hud_wave_status.tscn) — self-contained
# port of ui.gd's warn-light stack (2026-07-14). Drop the scene into any HUD
# layer: it finds the player ("player" group) and the wave director on its own
# and rebinds after respawn, so it can be moved/rearranged with no extra wiring.
#
# Light contract with the scene: warn lights are the Sprite2D children of the
# lights container (any plain Node2D child; bare Sprite2D children of the root
# also count), scene order = top→bottom. The LIT tint is scene-authored — the
# script reads the first light's modulate as the lit colour, so tune it in the
# editor. Steady state = bottom N lights lit, N = waves remaining in the level.
# While enemies are arriving (offscreen/recycling or a wave is incoming) the
# stack runs a downward chase, then settles back into the count. The lights
# container flashes when the player takes a hit.

const HudLight = preload("res://scripts/hud/hud_light.gd")

const WARN_CHASE_STEP_S := 0.09       # chase advance interval
const WARN_CHASE_BAND := 3            # lit lights in the moving chase band
const COLOR_WARN_OFF := Color(0.30, 0.22, 0.10, 0.8)

var _lights: Array[Sprite2D] = []     # index 0 = top (scene order)
var _color_lit := Color(1.00, 0.65, 0.10, 1.0)  # overridden by scene tint
var _flash_target: CanvasItem = null
var _waves_remaining: int = 0
var _wave_spawning: bool = false
var _chase_t: float = 0.0
var _chase_step: int = 0
var _player_ref: Node = null
var _director_ref: Node = null


func _ready() -> void:
	_flash_target = self
	for child in get_children():
		if child is Sprite2D:
			_lights.append(child)
		elif child is Node2D:
			# Lights container: flashing it (not the root) keeps the hit flash
			# off the THREAT label and clear of the per-frame modulate writes.
			_flash_target = child
			for grandchild in child.get_children():
				if grandchild is Sprite2D:
					_lights.append(grandchild)
	if not _lights.is_empty():
		_color_lit = _lights[0].modulate


func _process(delta: float) -> void:
	_ensure_bindings()

	# Arriving (enemies exist but none on screen, or a wave is incoming) →
	# downward chase across all lights. Otherwise the stack settles into the
	# wave indicator: bottom N lights lit, N = waves remaining.
	var enemy_count: int = get_tree().get_nodes_in_group("enemies").size()
	var on_screen: int = _enemies_on_screen() if enemy_count > 0 else 0
	var arriving: bool = on_screen == 0 and (enemy_count > 0 or _wave_spawning)

	var n: int = _lights.size()
	if arriving and n > 0:
		_chase_t += delta
		if _chase_t >= WARN_CHASE_STEP_S:
			_chase_t = fmod(_chase_t, WARN_CHASE_STEP_S)
			_chase_step = (_chase_step + 1) % n
		for i in n:
			var lit: bool = posmod(i - _chase_step, n) < WARN_CHASE_BAND
			_set_light(i, lit)
	else:
		_chase_t = 0.0
		_chase_step = 0
		for i in n:
			_set_light(i, i >= n - _waves_remaining)


# Self-(re)bind: main.gd rebuilds the player node on respawn and the director
# lives in the combat scene, so poll for live ones instead of external wiring.
func _ensure_bindings() -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		var p := get_tree().get_first_node_in_group("player")
		if p != null:
			_player_ref = p
			if p.has_signal("damaged") and not p.damaged.is_connected(_on_player_damaged):
				p.damaged.connect(_on_player_damaged)
	if _director_ref == null or not is_instance_valid(_director_ref):
		var d = get_node_or_null("/root/Main/WaveDirector")
		if d == null:
			d = get_node_or_null("/root/Main/Director")
		if d != null:
			_director_ref = d
			if d.has_signal("wave_started") and not d.wave_started.is_connected(_on_wave_started):
				d.wave_started.connect(_on_wave_started)
			if d.has_signal("level_cleared") and not d.level_cleared.is_connected(_on_level_cleared):
				d.level_cleared.connect(_on_level_cleared)


func _on_wave_started(idx: int, total: int, _silent: bool, _announce_text: String = "") -> void:
	_wave_spawning = true
	# Waves remaining includes the wave that just started.
	_waves_remaining = clampi(total - idx, 0, _lights.size())


func _on_level_cleared() -> void:
	_wave_spawning = false
	_waves_remaining = 0


func _on_player_damaged(_amount: int) -> void:
	HudLight.pip_flash(_flash_target)


func _set_light(i: int, lit: bool) -> void:
	var light := _lights[i]
	if light == null or not is_instance_valid(light):
		return
	light.frame = 1 if lit else 0
	light.modulate = _color_lit if lit else COLOR_WARN_OFF


func _enemies_on_screen() -> int:
	var count := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node2D:
			var y: float = (e as Node2D).global_position.y
			var x: float = (e as Node2D).global_position.x
			if y >= -32.0 and y <= 302.0 and x >= -32.0 and x <= 512.0:
				count += 1
	return count

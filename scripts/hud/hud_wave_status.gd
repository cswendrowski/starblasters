extends Node2D

# WAVE/THREAT STATUS widget (scenes/hud/hud_wave_status.tscn) — three-state
# wave sequencer (Roman 2026-07-15, replacing the chase/steady warn-light
# behavior). Self-contained: finds the player ("player" group) and the wave
# director on its own and rebinds after respawn.
#
# States:
#   INCOMING — from wave_started until this wave's first spawn: a soft pulse
#              travels down the stack top→bottom (enemies inbound).
#   ACTIVE   — all lights turn on, then tick down as the wave is destroyed: a
#              progress meter for the current wave. The wave has no authored
#              enemy total (the director walks phrases), so the meter is the
#              live fraction of the wave's PEAK alive force — full while
#              spawns keep pace, draining as kills win out, empty exactly when
#              the field is clear. Drains top-down (bottom N stay lit, old
#              stack convention).
#   CLEARED  — field empty: the top N lights pulse in unison, N = the NEXT
#              wave's number (1-based), until that wave starts. After the
#              final wave (or level_cleared) the stack goes dark. A straggler
#              spawn from the same wave drops the widget back to ACTIVE.
#
# Lights follow the HudLight PULSE style — smooth sine alpha breathing, not
# the old hard chase flicker. The traveling incoming pulse is the same sine
# with a per-light phase offset down the stack. (Driven here in _process
# rather than via HudLight tweens because the phases/count are dynamic.)
#
# Light contract with the scene: warn lights are the Sprite2D children of the
# lights container (any plain Node2D child; bare Sprite2D children of the root
# also count), scene order = top→bottom. The LIT tint is scene-authored — the
# script reads the first light's modulate as the lit colour. The lights
# container flashes when the player takes a hit.

const HudLight = preload("res://scripts/hud/hud_light.gd")

const INCOMING_CYCLE_S := 1.6   # incoming pulse: seconds for one full top→bottom sweep
const CLEARED_PULSE_S := 2.0    # cleared pulse: sine period (matches HudLight PULSE 1s down / 1s up)
const PULSE_MIN_A := 0.15       # pulse alpha floor — lights breathe, never fully vanish
const COLOR_WARN_OFF := Color(0.30, 0.22, 0.10, 0.8)

enum State { IDLE, INCOMING, ACTIVE, CLEARED }

var _lights: Array[Sprite2D] = []     # index 0 = top (scene order)
var _color_lit := Color(1.00, 0.65, 0.10, 1.0)  # overridden by scene tint
var _flash_target: CanvasItem = null
var _state: int = State.IDLE
var _t: float = 0.0                   # pulse clock for the current state
var _wave_idx: int = 0                # current wave (0-based, from wave_started)
var _wave_total: int = 0
var _peak_alive: int = 0              # max concurrent enemies seen this wave
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
	var n: int = _lights.size()
	if n == 0:
		return
	_t += delta

	match _state:
		State.INCOMING:
			# Traveling pulse: one sine crest sweeps the stack top→bottom per
			# cycle (phase falls with index, so the crest moves down).
			for i in n:
				var phase: float = _t / INCOMING_CYCLE_S - float(i) / float(n)
				_set_light_pulse(i, 0.5 + 0.5 * sin(TAU * phase))
		State.ACTIVE:
			var alive: int = _alive_enemies()
			_peak_alive = maxi(_peak_alive, alive)
			if alive <= 0:
				_state = State.CLEARED
				_t = 0.0
				return
			var lit: int = clampi(ceili(float(alive) / float(maxi(_peak_alive, 1)) * float(n)), 1, n)
			for i in n:
				_set_light_steady(i, i >= n - lit)
		State.CLEARED:
			var next_num: int = _wave_idx + 2   # next wave's 1-based number
			if _wave_total > 0 and _wave_idx + 1 >= _wave_total:
				next_num = 0                    # that was the final wave — go dark
			var count: int = clampi(next_num, 0, n)
			var a: float = 0.5 + 0.5 * sin(TAU * _t / CLEARED_PULSE_S)
			for i in n:
				if i < count:
					_set_light_pulse(i, a)
				else:
					_set_light_steady(i, false)
		_:
			for i in n:
				_set_light_steady(i, false)


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
			if d.has_signal("enemy_spawned") and not d.enemy_spawned.is_connected(_on_enemy_spawned):
				d.enemy_spawned.connect(_on_enemy_spawned)
			if d.has_signal("level_cleared") and not d.level_cleared.is_connected(_on_level_cleared):
				d.level_cleared.connect(_on_level_cleared)


func _on_wave_started(idx: int, total: int, _silent: bool, _announce_text: String = "") -> void:
	_wave_idx = idx
	_wave_total = total
	_peak_alive = 0
	_state = State.INCOMING
	_t = 0.0


func _on_enemy_spawned(_scene_path: String, _bounty_value: int) -> void:
	# First spawn flips incoming → the live progress meter; a straggler spawn
	# after a premature clear (mid-wave lull) resumes the meter.
	if _state == State.INCOMING or _state == State.CLEARED:
		_state = State.ACTIVE


func _on_level_cleared() -> void:
	_state = State.IDLE


func _on_player_damaged(_amount: int) -> void:
	HudLight.pip_flash(_flash_target)


func _set_light_steady(i: int, lit: bool) -> void:
	var light := _lights[i]
	if light == null or not is_instance_valid(light):
		return
	light.frame = 1 if lit else 0
	light.modulate = _color_lit if lit else COLOR_WARN_OFF


# Lit light breathing at `wave` (0..1 sine sample), alpha floored so it never
# fully vanishes — the PULSE look from the light pattern guide.
func _set_light_pulse(i: int, wave: float) -> void:
	var light := _lights[i]
	if light == null or not is_instance_valid(light):
		return
	light.frame = 1
	var col := _color_lit
	col.a = lerpf(PULSE_MIN_A, _color_lit.a, clampf(wave, 0.0, 1.0))
	light.modulate = col


func _alive_enemies() -> int:
	var count := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			count += 1
	return count

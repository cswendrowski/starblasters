extends HBoxContainer

# Shield HP bar — replaces pip strip. Blue-tinted fill bar.
# Width scales proportionally with shield HP vs max (capped at BAR_MAX_WIDTH).
# Pulses during the 5s regen delay countdown (polls _shield_in_delay on player).
# Shield spec 2026-05-26 rework.

const BAR_HEIGHT: int = 6
const BAR_MAX_WIDTH: int = 80

var _player: Node = null
var _max: int = 10
var _shield: int = 10
var _bar_bg: ColorRect = null
var _bar_fill: ColorRect = null
var _pulse_tween: Tween = null


func _ready() -> void:
	custom_minimum_size = Vector2(BAR_MAX_WIDTH, BAR_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_bar()


func _build_bar() -> void:
	for c in get_children():
		c.queue_free()
	_bar_bg = null
	_bar_fill = null
	# Background track.
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0.1, 0.2, 0.4, 0.7)
	_bar_bg.size = Vector2(BAR_MAX_WIDTH, BAR_HEIGHT)
	_bar_bg.position = Vector2.ZERO
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_bg)
	# Fill.
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color(0.35, 0.65, 1.0, 0.9)
	_bar_fill.size = Vector2(BAR_MAX_WIDTH, BAR_HEIGHT)
	_bar_fill.position = Vector2.ZERO
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_fill)
	_refresh_fill()


func bind_player(p: Node) -> void:
	_player = p
	if p and p.has_signal("shield_changed"):
		if not p.shield_changed.is_connected(_on_shield_changed):
			p.shield_changed.connect(_on_shield_changed)
	if p:
		_max = int(p.max_shield)
		_shield = int(p.shield)
		_refresh_fill()


func _refresh_fill() -> void:
	if _bar_fill == null:
		return
	var ratio: float = float(_shield) / float(max(1, _max))
	_bar_fill.size.x = BAR_MAX_WIDTH * clamp(ratio, 0.0, 1.0)


func _on_shield_changed(max_val, val) -> void:
	_max = int(max_val)
	_shield = int(val)
	_refresh_fill()


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	# Pulse modulate during 5s regen delay countdown.
	var in_delay: bool = _player.get("_shield_in_delay") == true
	if in_delay:
		if _pulse_tween == null or not _pulse_tween.is_valid():
			_start_pulse()
	else:
		_stop_pulse()


func _start_pulse() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		return
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(self, "modulate", Color(1.4, 1.6, 2.0, 1.0), 0.4).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.4).set_trans(Tween.TRANS_SINE)


func _stop_pulse() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
		_pulse_tween = null
	modulate = Color(1, 1, 1, 1)

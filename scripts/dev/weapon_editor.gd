extends "res://scripts/dev/pattern_editor_base.gd"

# Player Weapon Editor — author/edit/preview the cannon Parts that drive
# the ship's primary fire. Inherits the reflection-driven property
# editor from pattern_editor_base, then layers on:
#   - A Preview Mk slider (1..9) — selects which mark to visualize.
#   - DPS readout — effective_damage(mark) / base_cooldown.
#   - Live tracer preview — fires upward at the weapon's cooldown.
#
# Reflection picks up base_damage / dmg_per_mark / base_cooldown /
# base_ammo automatically (anything @export-ed on the cannon script).
# Per-mark scaling uses Part.effective_damage(mark) so non-linear
# formulas (wave_gun) show correct numbers.

const EnergyBlasterScript = preload("res://scripts/parts/basic_blaster_cannon.gd")

const PREVIEW_W := 540
const PREVIEW_H := 760
const TRACER_SPEED := 480.0  # px/s — player bullets fly faster than enemy

@onready var _mark_slider: HSlider = $Body/Center/MarkRow/MarkSlider
@onready var _mark_readout: Label = $Body/Center/MarkRow/MarkReadout
@onready var _dps_value: Label = $Body/Center/DpsRow/DpsValue
@onready var _dummy_player: Node2D = $Body/Preview/PreviewFrame/PreviewContainer/PreviewViewport/DummyPlayer
@onready var _bullets_layer: Node2D = $Body/Preview/PreviewFrame/PreviewContainer/PreviewViewport/BulletsLayer

var _preview_mark: int = 1
var _fire_timer: float = 0.0


func _configure() -> void:
	RESOURCE_DIR = "res://resources/weapons/"
	DEFAULT_SCRIPT = EnergyBlasterScript


func _ready() -> void:
	# Wire the slider signal BEFORE super._ready() — super calls
	# _on_item_selected → _on_pattern_loaded which reads slider state.
	_mark_slider.value_changed.connect(_on_mark_slider_changed)
	super._ready()


# pattern_editor_base hook — fired when a weapon .tres is selected.
func _on_pattern_loaded(res: Resource) -> void:
	_fire_timer = 0.0
	_clear_bullets()
	# Adopt the resource's own mark so the slider mirrors what's authored.
	if res and "mark" in res:
		_preview_mark = int(res.get("mark"))
		_mark_slider.value = _preview_mark
	_refresh_readouts(res)


# Fired by base whenever any reflection-driven field changes (e.g.
# base_damage SpinBox). Refresh DPS + reset preview timing.
func _on_field_changed(res: Resource, _prop_name: String) -> void:
	_refresh_readouts(res)
	_fire_timer = 0.0


func _on_mark_slider_changed(v: float) -> void:
	_preview_mark = int(v)
	_mark_readout.text = "Mk.%d" % _preview_mark
	# Mirror the slider into the resource's mark so saves capture the
	# designer's preview-mark intent (Roman can park balance at Mk.3 etc.).
	var res := _current_resource()
	if res and "mark" in res:
		res.set("mark", _preview_mark)
	_refresh_readouts(res)
	_mark_dirty()


func _refresh_readouts(res: Resource) -> void:
	if res == null or _dps_value == null:
		return
	var dmg: int = -1
	if res.has_method("effective_damage"):
		dmg = int(res.effective_damage(_preview_mark))
	var cooldown: float = -1.0
	if "base_cooldown" in res:
		cooldown = float(res.get("base_cooldown"))
	if dmg < 0 or cooldown <= 0.0:
		_dps_value.text = "—"
		return
	var dps: float = float(dmg) / cooldown
	_dps_value.text = "%d dmg × %.1f/s = %.1f DPS" % [dmg, 1.0 / cooldown, dps]


func _clear_bullets() -> void:
	if _bullets_layer == null:
		return
	for child in _bullets_layer.get_children():
		child.queue_free()


# Per-frame: tick the cooldown clock, emit a tracer when it elapses, and
# advance any in-flight tracers up the preview viewport.
func _process(delta: float) -> void:
	var res := _current_resource()
	if res == null or _bullets_layer == null or _dummy_player == null:
		return
	var cooldown: float = -1.0
	if "base_cooldown" in res:
		cooldown = float(res.get("base_cooldown"))
	if cooldown > 0.0:
		_fire_timer += delta
		if _fire_timer >= cooldown:
			_fire_timer = 0.0
			_spawn_tracer()
	# Advance in-flight tracers; cull when off the top or expired.
	for tr in _bullets_layer.get_children():
		tr.position += Vector2(0, -1) * TRACER_SPEED * delta
		if tr.position.y < -40:
			tr.queue_free()


func _spawn_tracer() -> void:
	var tr := ColorRect.new()
	tr.size = Vector2(6, 14)
	tr.position = _dummy_player.position - tr.size * 0.5
	# Tint by damage so visual punch tracks the number on the form.
	var res := _current_resource()
	var dmg: int = 1
	if res and res.has_method("effective_damage"):
		dmg = int(res.effective_damage(_preview_mark))
	var heat: float = clamp(float(dmg) / 30.0, 0.0, 1.0)
	tr.color = Color(0.45 + 0.55 * heat, 0.85, 1.0 - 0.5 * heat, 1.0)
	_bullets_layer.add_child(tr)

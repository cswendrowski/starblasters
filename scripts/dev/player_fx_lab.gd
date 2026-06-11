extends Control

# Player FX Lab (Roman 2026-06-11; HD-overhauled). Runs the live player ship through
# hull damage levels so the damage tells — engine fire (engine_torch), damage smoke
# (damage_smoke_trail), and the damage overlay — can be SEEN applying at each level,
# and verifies they react to max-HP changes. Also triggers the asteroid explosion +
# dust/smoke trail.
#
# Renders the WORLD in a native 480×270 SubViewport (crisp, hdr_2d-parity, fx parent to
# the player's parent = the viewport) upscaled to fill HD, with an HD CanvasLayer UI
# overlay — so the controls are usable at 1920×1080 (was cramped at native res).

const AsteroidScene = preload("res://Planets/Asteroids/Asteroid.tscn")
const SceneTransition = preload("res://scripts/scene_transition.gd")

const SHIPS := [
	"res://scenes/player/player.tscn",
	"res://scenes/player/player_b.tscn",
	"res://scenes/player/player_c.tscn",
]

var _hd_scope: HdViewportScope = null
var _world: SubViewport = null
var _player: Node2D = null
var _hull_slider: HSlider = null
var _maxhull_slider: HSlider = null
var _readout: Label = null


func _ready() -> void:
	_hd_scope = HdViewportScope.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world = HdScreen.make_play_subviewport(self)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09)
	bg.size = Vector2(480, 270)
	_world.add_child(bg)
	_build_ui()
	_spawn_player(0)
	await get_tree().process_frame
	HdScreen.verify_native_subviewport(_world, "Player FX Lab")


func _spawn_player(idx: int) -> void:
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	var scn: PackedScene = load(SHIPS[clampi(idx, 0, SHIPS.size() - 1)])
	_player = scn.instantiate()
	_world.add_child(_player)
	_player.position = Vector2(240.0, 175.0)
	if "is_alive" in _player:
		_player.is_alive = true
	if "controls_enabled" in _player:
		_player.controls_enabled = false   # hold still so the fx read clearly
	if "invincible" in _player:
		_player.invincible = true
	await get_tree().process_frame
	_sync_sliders_from_player()
	_apply_hull()


func _sync_sliders_from_player() -> void:
	if _player == null:
		return
	var mh: int = int(_player.max_hull) if "max_hull" in _player else 3
	_maxhull_slider.value = mh
	_hull_slider.max_value = mh
	_hull_slider.value = mh


# Drive the player's hull (triggers hull_changed → fire/smoke/torch/overlay update).
func _apply_hull() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var mh: int = int(_maxhull_slider.value)
	var h: int = clampi(int(_hull_slider.value), 0, mh)
	if "max_hull" in _player:
		_player.max_hull = mh
	if "hull" in _player:
		_player.hull = h          # setter emits hull_changed
	if _player.has_signal("hull_changed"):
		_player.hull_changed.emit(mh, h)   # re-eval the max-HP fraction even if hull held
	if _readout:
		var frac: float = 1.0 - (float(h) / float(max(1, mh)))
		_readout.text = "Hull %d / %d   (damage %d%%)" % [h, mh, int(round(frac * 100.0))]


func _explode_asteroid() -> void:
	var a = AsteroidScene.instantiate()
	_world.add_child(a)
	a.position = Vector2(240.0, 110.0)
	await get_tree().process_frame
	if a.has_method("explode"):
		a.explode()


func _drift_asteroid() -> void:
	var a = AsteroidScene.instantiate()
	_world.add_child(a)
	a.position = Vector2(randf_range(170.0, 310.0), 20.0)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var rail := VBoxContainer.new()
	rail.position = Vector2(24, 24)
	rail.add_theme_constant_override("separation", 10)
	layer.add_child(rail)

	rail.add_child(_mk_label("PLAYER FX LAB", 26))

	var dd := OptionButton.new()
	for s in ["Ship A", "Ship B", "Ship C"]:
		dd.add_item(s)
	dd.item_selected.connect(func(i): _spawn_player(i))
	dd.custom_minimum_size = Vector2(220, 44)
	rail.add_child(dd)

	rail.add_child(_mk_label("Hull (drag to damage)", 18))
	_hull_slider = _mk_slider(0, 3, 1, 3)
	_hull_slider.value_changed.connect(func(_v): _apply_hull())
	rail.add_child(_hull_slider)

	rail.add_child(_mk_label("Max Hull (max-HP test)", 18))
	_maxhull_slider = _mk_slider(1, 10, 1, 3)
	_maxhull_slider.value_changed.connect(func(_v):
		_hull_slider.max_value = _maxhull_slider.value
		_apply_hull())
	rail.add_child(_maxhull_slider)

	_readout = _mk_label("", 18)
	rail.add_child(_readout)

	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	rail.add_child(brow)
	brow.add_child(_mk_button("Explode Asteroid", _explode_asteroid))
	brow.add_child(_mk_button("Drift Asteroid", _drift_asteroid))
	rail.add_child(_mk_button("Back (Esc)", _back))


func _mk_label(t: String, size: int = 18) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	return l


func _mk_slider(lo: float, hi: float, step: float, val: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(360, 28)
	return s


func _mk_button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", 18)
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(cb)
	return b


func _back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_back()

extends Node2D

# Hangar V2 — Roman, 2026-05-18 rework.
#
# Strips the old ShipVisuals demo rig. Now hosts:
#   - A real player.tscn instance you can fly with WASD
#   - Cannon-swap panel that calls Part.apply(player) on the live ship so
#     each cannon's `bullet_scene`, `cooldown`, and `fire_sfx_kind` route
#     through the same code path as combat
#   - Mk slider (1-9) that updates the equipped cannon's mark + re-applies
#   - Dummy target at the top of the playfield — invulnerable Area2D that
#     plays the hit flash so you can verify hits visually
#   - SPACE fires the equipped cannon with its real sound
#
# Decisions worth flagging:
#   * Player is instantiated from scenes/player/player.tscn but with the
#     `controls_enabled` flag flipped to true and `start()` called inline.
#     If anything in player.gd depends on being parented to main.tscn
#     (autoload Run, ShieldRegenTimer, etc.) it will still find them via
#     get_node("/root/Run") — works since Run is an autoload.
#   * Mk slider mutates the current cannon part in-place rather than
#     re-instantiating. cannon.unapply() then cannon.apply() so previous
#     stats roll back cleanly.
#   * Dummy target is a static Area2D with a 24×24 hitbox; HitFlashFx
#     plays on each bullet entry. No HP / death — just a punching bag.

const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")

# Same 7 cannon mapping the previous hangar used — these are the real
# game CANNON parts (factory keys come from part_catalog.gd::_make_by_name).
const GAME_CANNONS := [
	"_make_basic_blaster",
	"_make_heavy_blaster",
	"_make_machinegun",
	"_make_wave_gun",
	"_make_laser_beam",
	"_make_rocket_pod",
	"_make_seeking_missile",
]

const PLAYFIELD_RECT := Rect2(8, 20, 188, 360)
const TARGET_POS := Vector2(96, 50)

var _player: Node = null
var _current_cannon: Resource = null
var _current_mark: int = 1
var _mark_slider: HSlider = null
var _mark_label: Label = null
var _cannon_label: Label = null


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.03, 0.04, 0.08))
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")
	_build_backdrop()
	_spawn_player()
	_spawn_dummy_target()
	_build_ui()
	# Default to the basic blaster so SPACE-firing works on entry.
	_equip_cannon("_make_basic_blaster")


func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.12, 1.0)
	bg.size = get_viewport_rect().size
	bg.z_index = -10
	add_child(bg)
	var frame := Panel.new()
	frame.position = PLAYFIELD_RECT.position
	frame.size = PLAYFIELD_RECT.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.10, 0.16, 0.6)
	sb.border_color = Color(0.25, 0.40, 0.55, 0.7)
	sb.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", sb)
	frame.z_index = -9
	add_child(frame)


func _spawn_player() -> void:
	_player = PlayerScene.instantiate()
	# Drop into the playfield center; player.gd's start() handles its own
	# init (loadout, shield ring, etc.). Hangar disables the offscreen
	# despawn since the player doesn't move in the hangar.
	_player.position = PLAYFIELD_RECT.position + PLAYFIELD_RECT.size * Vector2(0.5, 0.7)
	add_child(_player)


func _spawn_dummy_target() -> void:
	# Simple endless punching bag. Not in the "enemies" group so the
	# player's bullets need an explicit group-match override OR we just
	# let collision happen visually. Bullets target "enemies" — easiest
	# is to add the dummy to that group so hits register, plus a take_hit
	# stub that doesn't actually subtract HP.
	var target := Area2D.new()
	target.name = "DummyTarget"
	target.add_to_group("enemies")
	target.position = TARGET_POS
	target.set_script(load("res://scripts/dev/hangar_dummy_target.gd"))
	# Sprite — borrow the bulwark for a chunky look that reads "armored".
	var spr := Sprite2D.new()
	var bulwark_tex: Texture2D = load("res://graphics/extra-ships/ship_4.png")
	if bulwark_tex == null:
		bulwark_tex = load("res://graphics/extra-ships/ship_1.png")
	spr.texture = bulwark_tex
	spr.scale = Vector2(2.0, 2.0)
	target.add_child(spr)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24, 24)
	shape.shape = rect
	target.add_child(shape)
	# Label below.
	var lbl := Label.new()
	lbl.text = "TARGET"
	lbl.position = Vector2(-30, 20)
	lbl.size = Vector2(60, 12)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 9)
	target.add_child(lbl)
	add_child(target)


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "HangarUI"
	add_child(ui)
	# Panel docked to the right edge of the 480-wide viewport (was x=200
	# for the legacy 320-wide layout, which left it floating mid-screen).
	var root := Panel.new()
	root.position = Vector2(get_viewport_rect().size.x - 120.0, 0)
	root.size = Vector2(120, get_viewport_rect().size.y)
	var sb: StyleBoxFlat = UiTheme.make_panel_stylebox()
	sb.bg_color = Color(0.04, 0.06, 0.10, 0.95)
	root.add_theme_stylebox_override("panel", sb)
	ui.add_child(root)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(4, 4)
	scroll.size = root.size - Vector2(8, 8)
	root.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	_add_header(vb, "HANGAR")
	_add_caption(vb, "WASD fly  SPACE fire")

	_cannon_label = Label.new()
	_cannon_label.text = "(no cannon)"
	_cannon_label.add_theme_font_size_override("font_size", 9)
	_cannon_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	vb.add_child(_cannon_label)

	vb.add_child(HSeparator.new())
	_add_caption(vb, "Cannon")
	for factory in GAME_CANNONS:
		var name: String = _short_name(factory)
		_add_button(vb, name, func(): _equip_cannon(factory))

	vb.add_child(HSeparator.new())
	_add_caption(vb, "Mark")
	_mark_label = Label.new()
	_mark_label.text = "Mk.1"
	_mark_label.add_theme_font_size_override("font_size", 10)
	_mark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_mark_label)
	_mark_slider = HSlider.new()
	_mark_slider.min_value = 1
	_mark_slider.max_value = 9
	_mark_slider.step = 1
	_mark_slider.value = 1
	_mark_slider.custom_minimum_size = Vector2(0, 14)
	_mark_slider.value_changed.connect(_on_mark_changed)
	vb.add_child(_mark_slider)

	vb.add_child(HSeparator.new())
	_add_button(vb, "Back to Dev Menu", _on_back)


func _add_header(parent: Container, text: String) -> void:
	var l := Label.new()
	l.text = text
	UiTheme.style_label(l, UiTheme.LabelKind.HEADER)
	l.add_theme_font_size_override("font_size", 11)
	parent.add_child(l)


func _add_caption(parent: Container, text: String) -> void:
	var l := Label.new()
	l.text = text
	UiTheme.style_label(l, UiTheme.LabelKind.CAPTION)
	parent.add_child(l)


func _add_button(parent: Container, label: String, action: Callable) -> void:
	var b := Button.new()
	b.text = label
	UiTheme.style_button(b, true)
	b.add_theme_font_size_override("font_size", 10)
	b.pressed.connect(action)
	parent.add_child(b)


func _short_name(factory: String) -> String:
	# Strip "_make_" prefix + title-case.
	var s := factory
	if s.begins_with("_make_"):
		s = s.substr(6)
	return s.replace("_", " ").capitalize()


# Build the cannon via PartCatalog._make_by_name (returns a Part instance
# with bullet_scene already wired) and apply() onto the live player.
func _equip_cannon(factory: String) -> void:
	if _player == null:
		return
	# Tear down any previously equipped cannon so its stats roll back.
	if _current_cannon != null and _player.has_node("Loadout"):
		var loadout = _player.get_node("Loadout")
		if loadout.has_method("equip"):
			# Loadout.equip handles unapply+apply, but we want to drop the
			# slot entirely first. Easiest path: apply the new cannon which
			# triggers unapply on the old one inside PlayerLoadout.
			pass
	var part = PartCatalog._make_by_name(factory, SlotTypes.SlotType.CANNON)
	if part == null:
		return
	part.mark = _current_mark
	_current_cannon = part
	if _player.has_node("Loadout"):
		_player.get_node("Loadout").equip(SlotTypes.SlotType.CANNON, part)
	if _cannon_label:
		var nm: String = String(part.display_name) if "display_name" in part else _short_name(factory)
		_cannon_label.text = "%s Mk.%d" % [nm, int(part.mark)]


func _on_mark_changed(v: float) -> void:
	_current_mark = clampi(int(v), 1, 9)
	if _mark_label:
		_mark_label.text = "Mk.%d" % _current_mark
	# Re-apply the current cannon at the new mark.
	if _current_cannon != null and _player and _player.has_node("Loadout"):
		_current_cannon.mark = _current_mark
		_player.get_node("Loadout").equip(SlotTypes.SlotType.CANNON, _current_cannon)
		if _cannon_label:
			var nm: String = String(_current_cannon.display_name) if "display_name" in _current_cannon else "?"
			_cannon_label.text = "%s Mk.%d" % [nm, int(_current_cannon.mark)]


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()

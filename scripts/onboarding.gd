extends Control

# Onboarding screen. Shown once after New Game and before the sector map so
# the player gets a tour of the basics: controls, shield regen, shield vs
# hull, bounty, waves, sector map icons.
#
# Six pages, each Next/Prev navigable. The final page's Next sends the player
# into the sector map.

const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

# Icons used in the Sector Map page so we explain what the player will see.
const ICON_COMBAT = preload("res://graphics/sector/sector-battle.png")
const ICON_OUTPOST = preload("res://graphics/sector/sector-station.png")
const ICON_SIGNAL = preload("res://graphics/sector/sector-unknown.png")
const ICON_BOSS = preload("res://graphics/sector/sector-boss.png")
const ICON_HAZARD = preload("res://graphics/sector/sector-hazard.png")

var _pages: Array = []
var _index: int = 0

var _title_label: Label
var _body_label: Label
var _next_btn: Button
var _prev_btn: Button
var _skip_btn: Button
var _page_label: Label
var _icons_row: HBoxContainer


func _ready() -> void:
	_pages = _build_pages()
	_build_ui()
	_render()


func _build_pages() -> Array:
	return [
		{
			"title": "Controls",
			"body": "WASD or Arrow Keys to move.\nSpace to fire your main cannon.\nShift to fire your nose-mounted hardpoint.\nQ / E cycle between weapons.\nEsc opens the pause menu.",
		},
		{
			"title": "Shields & Hull",
			"body": "Your ship has two layers of integrity.\n\nThe SHIELD bar at the top absorbs incoming fire. When it runs out, hits bleed into your HULL.\n\nThe diamond pips next to it are your hull. When the last pip falls, your ship is gone — there's no second chance in a run.",
		},
		{
			"title": "Shield Regen",
			"body": "Shields regenerate automatically a couple of seconds after the last hit.\n\nIf you can disengage for a beat — duck behind cover, juke away from a barrage — your shield will come back. The TAIL part on your ship determines how fast.",
		},
		{
			"title": "Bounty",
			"body": "Every enemy you destroy drops Bounty Credits. You can see your running total at the top-right of the HUD.\n\nSpend bounty at Friendly Outposts on new parts and hull repairs, or on Junk Traders for sketchier deals. Survive deeper into a run and the prices climb — but so do the rewards.",
		},
		{
			"title": "Waves",
			"body": "Combat levels are split into waves. A banner pops at the start of each: WAVE 1 / 7, WAVE 2 / 7, and so on.\n\nMid-level, the wave count tells you how close you are to clearing. The last two waves of every level are the loudest — keep something in reserve.",
		},
		{
			"title": "Sector Map",
			"body": "Between fights you'll see the sector map — a branching graph of nodes you choose between.",
			"icons": true,
		},
	]


func _build_ui() -> void:
	# Render everything in a CanvasLayer so the UI is independent of any
	# parent Node2D transform (the showcase parents this Control under a
	# Node2D, which clipped/sized the prior layout to nothing).
	var vp: Vector2 = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_PASS
	var layer := CanvasLayer.new()
	layer.name = "Layer"
	add_child(layer)

	# Sector-map background — gives the onboarding panel the same painterly
	# void Roman wants throughout the meta scenes.
	var bg := TextureRect.new()
	bg.texture = load("res://graphics/ui/sector_bg.png")
	bg.position = Vector2.ZERO
	bg.size = vp
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)

	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	panel.size = Vector2(280, 320)
	panel.position = Vector2((vp.x - 280.0) * 0.5, (vp.y - 320.0) * 0.5)
	layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.position = Vector2(10, 10)
	vbox.size = panel.size - Vector2(20, 20)
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(_title_label, UiTheme.LabelKind.HEADER)
	vbox.add_child(_title_label)

	_page_label = Label.new()
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(_page_label, UiTheme.LabelKind.CAPTION)
	vbox.add_child(_page_label)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(260, 160)
	UiTheme.style_label(_body_label, UiTheme.LabelKind.BODY)
	vbox.add_child(_body_label)

	_icons_row = HBoxContainer.new()
	_icons_row.add_theme_constant_override("separation", 24)
	_icons_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_icons_row)

	# Bottom row: prev / skip / next.
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 16)
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(nav)

	_prev_btn = Button.new()
	_prev_btn.text = "Back"
	UiTheme.style_button(_prev_btn)
	_prev_btn.pressed.connect(_on_prev)
	nav.add_child(_prev_btn)

	_skip_btn = Button.new()
	_skip_btn.text = "Skip Tutorial"
	UiTheme.style_button(_skip_btn, true)
	# Dev-shortcut green so it reads as an explicit "I've done this" path
	# rather than just another nav button next to Back/Next.
	_skip_btn.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6, 1.0))
	_skip_btn.pressed.connect(_finish)
	nav.add_child(_skip_btn)

	_next_btn = Button.new()
	_next_btn.text = "Next"
	UiTheme.style_button(_next_btn)
	_next_btn.pressed.connect(_on_next)
	nav.add_child(_next_btn)


func _render() -> void:
	var page: Dictionary = _pages[_index]
	_title_label.text = page.get("title", "")
	_body_label.text = page.get("body", "")
	_page_label.text = "%d / %d" % [_index + 1, _pages.size()]
	_prev_btn.disabled = _index == 0
	_next_btn.text = "Sector Map" if _index == _pages.size() - 1 else "Next"
	# Icons row only populated on the sector-map page.
	for c in _icons_row.get_children():
		c.queue_free()
	if page.get("icons", false):
		_add_icon(_icons_row, ICON_COMBAT, "Combat")
		_add_icon(_icons_row, ICON_OUTPOST, "Outpost")
		_add_icon(_icons_row, ICON_SIGNAL, "Signal")
		_add_icon(_icons_row, ICON_HAZARD, "Hazard")
		_add_icon(_icons_row, ICON_BOSS, "Boss")


func _add_icon(parent: Container, tex: Texture2D, label: String) -> void:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.custom_minimum_size = Vector2(24, 24)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	col.add_child(rect)
	var lbl := Label.new()
	lbl.text = label
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(lbl, UiTheme.LabelKind.CAPTION)
	col.add_child(lbl)
	parent.add_child(col)


func _on_next() -> void:
	if _index >= _pages.size() - 1:
		_finish()
		return
	_index += 1
	_render()


func _on_prev() -> void:
	if _index <= 0:
		return
	_index -= 1
	_render()


func _finish() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/sector_map_v2.tscn")

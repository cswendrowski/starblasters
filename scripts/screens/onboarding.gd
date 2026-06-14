extends Control

# Onboarding screen. Shown once after New Game and before the sector map so
# the player gets a tour of the basics: controls, shield regen, shield vs
# hull, bounty, waves, sector map icons.
#
# Six pages, each Next/Prev navigable. The final page's Next sends the player
# into the sector map.

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SectorMapRoute = preload("res://scripts/systems/sector_map_route.gd")
const Strings = preload("res://scripts/strings/strings.gd")

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
var _hd_scope: HdViewportScope = null


func _ready() -> void:
	# Render at HD (1920×1080) like the other menus. Must precede _build_ui so
	# get_viewport_rect() reports the HD size the panel centers against.
	_hd_scope = HdScreen.enter(self)
	_pages = _build_pages()
	_build_ui()
	_render()


func _build_pages() -> Array:
	return [
		{
			"title": Strings.ONBOARDING_CONTROLS_TITLE,
			"body": Strings.ONBOARDING_CONTROLS_BODY,
		},
		{
			"title": Strings.ONBOARDING_PARTS_TITLE,
			"body": Strings.ONBOARDING_PARTS_BODY,
		},
		{
			"title": Strings.ONBOARDING_SHIELDS_TITLE,
			"body": Strings.ONBOARDING_SHIELDS_BODY,
		},
		{
			"title": Strings.ONBOARDING_SHIELD_REGEN_TITLE,
			"body": Strings.ONBOARDING_SHIELD_REGEN_BODY,
		},
		{
			"title": Strings.ONBOARDING_BOUNTY_TITLE,
			"body": Strings.ONBOARDING_BOUNTY_BODY,
		},
		{
			"title": Strings.ONBOARDING_WAVES_TITLE,
			"body": Strings.ONBOARDING_WAVES_BODY,
		},
		{
			"title": Strings.ONBOARDING_SECTOR_MAP_TITLE,
			"body": Strings.ONBOARDING_SECTOR_MAP_BODY,
			"icons": true,
		},
		{
			"title": Strings.ONBOARDING_NODE_TYPES_TITLE,
			"body": Strings.ONBOARDING_NODE_TYPES_BODY,
		},
		{
			"title": Strings.ONBOARDING_MISSION_TITLE,
			"body": Strings.ONBOARDING_MISSION_BODY,
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
	# HD-sized card centered in the 1920×1080 viewport.
	var panel_size := Vector2(980, 680)
	panel.size = panel_size
	panel.position = ((vp - panel_size) * 0.5).round()
	layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.position = Vector2(48, 36)
	vbox.size = panel_size - Vector2(96, 72)
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
	_body_label.custom_minimum_size = Vector2(840, 0)
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(_body_label, UiTheme.LabelKind.BODY)
	vbox.add_child(_body_label)

	_icons_row = HBoxContainer.new()
	_icons_row.add_theme_constant_override("separation", 56)
	_icons_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_icons_row)

	# Bottom row: prev / skip / next.
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 32)
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(nav)

	_prev_btn = Button.new()
	_prev_btn.text = Strings.ONBOARDING_BTN_BACK
	UiTheme.style_button(_prev_btn)
	_prev_btn.custom_minimum_size = Vector2(200, 60)
	_prev_btn.pressed.connect(_on_prev)
	nav.add_child(_prev_btn)

	_skip_btn = Button.new()
	_skip_btn.text = Strings.ONBOARDING_BTN_SKIP
	UiTheme.style_button(_skip_btn, true)
	_skip_btn.custom_minimum_size = Vector2(200, 60)
	# Dev-shortcut green so it reads as an explicit "I've done this" path
	# rather than just another nav button next to Back/Next.
	_skip_btn.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6, 1.0))
	_skip_btn.pressed.connect(_finish)
	nav.add_child(_skip_btn)

	_next_btn = Button.new()
	_next_btn.text = Strings.ONBOARDING_BTN_NEXT
	UiTheme.style_button(_next_btn)
	_next_btn.custom_minimum_size = Vector2(200, 60)
	_next_btn.pressed.connect(_on_next)
	nav.add_child(_next_btn)


func _render() -> void:
	var page: Dictionary = _pages[_index]
	_title_label.text = page.get("title", "")
	_body_label.text = page.get("body", "")
	_page_label.text = "%d / %d" % [_index + 1, _pages.size()]
	_prev_btn.disabled = _index == 0
	_next_btn.text = Strings.ONBOARDING_BTN_BEGIN if _index == _pages.size() - 1 else Strings.ONBOARDING_BTN_NEXT
	# Icons row only populated on the sector-map page.
	for c in _icons_row.get_children():
		c.queue_free()
	if page.get("icons", false):
		_add_icon(_icons_row, ICON_COMBAT, Strings.ONBOARDING_ICON_COMBAT)
		_add_icon(_icons_row, ICON_OUTPOST, Strings.ONBOARDING_ICON_OUTPOST)
		_add_icon(_icons_row, ICON_SIGNAL, Strings.ONBOARDING_ICON_SIGNAL)
		_add_icon(_icons_row, ICON_HAZARD, Strings.ONBOARDING_ICON_HAZARD)
		_add_icon(_icons_row, ICON_BOSS, Strings.ONBOARDING_ICON_BOSS)


func _add_icon(parent: Container, tex: Texture2D, label: String) -> void:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.custom_minimum_size = Vector2(72, 72)
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	SceneTransition.change_scene(get_tree(), SectorMapRoute.SECTOR_MAP_SCENE)

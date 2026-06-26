extends CanvasLayer

# Ship-select modal (Roman 2026-06-09). Shown at the start of a NEW PATROL: the player picks one of
# three hulls (A = default, B / C = alternates) and a livery color (swatch row + Random). Mirrors the
# self-contained options_overlay pattern — a CanvasLayer with a dim scrim + centered panel, opened via
# the static open() factory. On "Begin Patrol" it fires on_confirm(variant:int, color:Color); the
# caller does Run.new_run() + writes the choice + transitions. Cancel just closes (stay on menu).
#
# The ship preview is built by the shared `ShipVisual` builder (body + the real screen-multiply livery
# shader @0.8 + additive engine glow) — the SAME render path every other menu uses, so the picker reads
# exactly like the in-game ship instead of an approximation.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const ShipCatalog = preload("res://scripts/strings/ship_catalog.gd")
const ShipVisual = preload("res://scripts/ui/ship_visual.gd")
const NODE_NAME := "ShipSelectOverlay"

# Per-variant art + display name. Index = Run.ship_variant. The roster (name / tag / sheets) is
# the canonical ShipCatalog; this picker reads it so a new ship shows up here automatically.
const VARIANTS := ShipCatalog.SHIPS

# Livery swatch palette — a spread of saturated, readable hues. Random picks anywhere in HSV space.
const SWATCHES := [
	Color(0.90, 0.16, 0.16),  # red
	Color(0.96, 0.55, 0.13),  # orange
	Color(0.98, 0.85, 0.25),  # gold
	Color(0.45, 0.85, 0.30),  # green
	Color(0.20, 0.80, 0.65),  # teal
	Color(0.25, 0.62, 0.97),  # blue
	Color(0.40, 0.40, 0.92),  # indigo
	Color(0.70, 0.38, 0.95),  # violet
	Color(0.96, 0.40, 0.78),  # pink
	Color(0.92, 0.92, 0.95),  # white
]

const PREVIEW_PX := 112   # on-screen size of each 16px ship preview

var _on_confirm: Callable = Callable()
var _selected_variant: int = 0
var _current_color: Color = Color(0.90, 0.16, 0.16)

var _cards: Array = []          # [{root: PanelContainer, livery_rect: TextureRect, idx: int}]
var _color_dot: ColorRect = null


# Open the modal over `parent`. default_variant / default_color seed the initial selection;
# on_confirm(variant:int, color:Color) fires when the player commits ("Begin Patrol").
static func open(parent: Node, default_variant: int, default_color: Color, on_confirm: Callable) -> CanvasLayer:
	if parent == null:
		return null
	var root: Node = parent.get_tree().root if parent.is_inside_tree() else parent
	# Dedupe — one modal at a time.
	for n in root.get_children():
		if n.name == NODE_NAME and n is CanvasLayer:
			n.queue_free()
	var overlay := load("res://scripts/ui/ship_select_overlay.gd").new() as CanvasLayer
	overlay.name = NODE_NAME
	overlay._selected_variant = clampi(default_variant, 0, VARIANTS.size() - 1)
	overlay._current_color = default_color
	overlay._on_confirm = on_confirm
	root.add_child(overlay)
	return overlay


func _init() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build_ui()
	_refresh_selection()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.COLOR_PANEL_BG
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.set_border_width_all(2)
	sb.set_content_margin_all(34)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)

	var title := _label("SELECT SHIP", UiTheme.FONT_SIZE_TITLE, UiTheme.COLOR_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# --- Ship cards row ---
	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 22)
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(cards_row)
	for i in VARIANTS.size():
		cards_row.add_child(_make_ship_card(i))

	vbox.add_child(_hsep())

	# --- Livery picker ---
	var liv_label := _label("LIVERY", UiTheme.FONT_SIZE_HEADER, UiTheme.COLOR_TEXT)
	vbox.add_child(liv_label)

	var swatch_row := HBoxContainer.new()
	swatch_row.add_theme_constant_override("separation", 10)
	swatch_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(swatch_row)
	for c in SWATCHES:
		swatch_row.add_child(_make_swatch(c))
	# Current-color indicator + Random button on the same row.
	swatch_row.add_child(_vsep())
	_color_dot = ColorRect.new()
	_color_dot.custom_minimum_size = Vector2(40, 40)
	_color_dot.color = _current_color
	swatch_row.add_child(_color_dot)
	var rnd_btn := UiTheme.make_button("Random", true)
	rnd_btn.pressed.connect(_on_random_livery)
	swatch_row.add_child(rnd_btn)

	vbox.add_child(_hsep())

	# --- Confirm / Cancel ---
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)
	var cancel_btn := UiTheme.make_button("Cancel")
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)
	var begin_btn := UiTheme.make_button("Begin Patrol")
	begin_btn.pressed.connect(_on_begin)
	btn_row.add_child(begin_btn)


func _make_ship_card(idx: int) -> PanelContainer:
	var data: Dictionary = VARIANTS[idx]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_stylebox(false))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)

	# Preview: the shared ship visual (body + real screen-multiply livery @0.8 + engine glow), so it
	# matches the in-game ship exactly. Centered + scaled to fill the fixed-size holder.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(PREVIEW_PX, PREVIEW_PX)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var visual := ShipVisual.build(idx, _current_color)
	var sf: float = PREVIEW_PX / 16.0   # ships are 16px native
	visual.scale = Vector2(sf, sf)
	visual.position = Vector2(PREVIEW_PX, PREVIEW_PX) * 0.5
	holder.add_child(visual)
	vb.add_child(holder)

	var name_lbl := _label(String(data["name"]), UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_TEXT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(name_lbl)
	var tag_lbl := _label(String(data["tag"]), UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT)
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tag_lbl)

	# Whole card is clickable to select.
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.pressed.connect(_on_select_variant.bind(idx))
	card.add_child(btn)

	_cards.append({"root": card, "visual": visual, "idx": idx})
	return card


func _make_swatch(c: Color) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(40, 40)
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_border_width_all(2)
	sb.border_color = Color(0, 0, 0, 0.6)
	sb.set_corner_radius_all(4)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.pressed.connect(_on_pick_color.bind(c))
	return b


# ---- Interaction ----------------------------------------------------------

func _on_select_variant(idx: int) -> void:
	_selected_variant = idx
	_refresh_selection()


func _on_pick_color(c: Color) -> void:
	_set_color(c)


func _on_random_livery() -> void:
	# Saturated, bright random hue (matches the seed-random range player.gd uses as its fallback).
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_set_color(Color.from_hsv(rng.randf(), rng.randf_range(0.7, 1.0), rng.randf_range(0.85, 1.0)))


func _set_color(c: Color) -> void:
	_current_color = c
	if _color_dot != null:
		_color_dot.color = c
	for card in _cards:
		ShipVisual.set_tint(card["visual"], c)


func _refresh_selection() -> void:
	for card in _cards:
		var selected: bool = int(card["idx"]) == _selected_variant
		(card["root"] as PanelContainer).add_theme_stylebox_override("panel", _card_stylebox(selected))


func _on_begin() -> void:
	var cb := _on_confirm
	var v := _selected_variant
	var c := _current_color
	queue_free()
	if cb.is_valid():
		cb.call(v, c)


func _on_cancel() -> void:
	queue_free()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_cancel()
		get_viewport().set_input_as_handled()


# ---- Style helpers --------------------------------------------------------

func _card_stylebox(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.16, 0.9) if selected else Color(0.05, 0.07, 0.10, 0.7)
	sb.set_border_width_all(3 if selected else 1)
	sb.border_color = UiTheme.COLOR_ACCENT if selected else UiTheme.COLOR_ACCENT_DIM
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	return sb


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.active_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", UiTheme.COLOR_OUTLINE)
	l.add_theme_constant_override("outline_size", 4)
	return l


func _hsep() -> HSeparator:
	return HSeparator.new()


func _vsep() -> VSeparator:
	return VSeparator.new()

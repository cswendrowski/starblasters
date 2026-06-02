extends RefCounted
class_name UiTheme

# Single source of truth for UI styling across menus, summary screens, and
# overlays. All menu scripts route through these helpers instead of defining
# their own palette + stylebox copies. To re-skin the entire game, change
# values here.
#
# Holo pass removed 2026-05-16 (Roman): "strip out the holo effect and just
# do a clean UI setup." The make_holo_material() helper is retained as a
# no-op shim so existing callers don't crash; it now returns null and the
# assignment `.material = null` is harmless.

# ----- Palette -----------------------------------------------------------
# Clean neutral palette: bright off-white text on dark scenes, cool light-blue
# accent for interactive elements. No teal/cyan glow, no scanlines.
const COLOR_TEXT       := Color(0.95, 0.97, 1.00, 1.0)  # primary text
const COLOR_ACCENT     := Color(0.62, 0.82, 1.00, 1.0)  # buttons, headers, links
const COLOR_ACCENT_DIM := Color(0.32, 0.50, 0.72, 1.0)  # outlines / inactive border
const COLOR_OUTLINE    := Color(0.05, 0.08, 0.12, 1.0)  # text outline — pure dark
const COLOR_BOUNTY     := Color(1.00, 0.86, 0.42, 1.0)  # warm gold — currency
const COLOR_GREEN      := Color(0.55, 1.00, 0.50, 1.0)  # sector map green — weapon UI, node markers
const COLOR_DANGER     := Color(1.00, 0.40, 0.32, 1.0)  # alert red
const COLOR_DANGER_DK  := Color(0.40, 0.05, 0.00, 1.0)  # alert outline
const COLOR_DISABLED   := Color(0.45, 0.50, 0.58, 0.75)
const COLOR_FAINT      := Color(0.70, 0.78, 0.88, 0.70) # version label, captions
const COLOR_WHITE      := Color(1, 1, 1, 1)
const COLOR_PANEL_BG   := Color(0.05, 0.07, 0.11, 0.82) # menu panels — near-black

# Legacy aliases — older scripts reference COLOR_HOLO. Map to the accent.
const COLOR_HOLO := COLOR_ACCENT

# ----- Font sizes --------------------------------------------------------
# HD UI sizes (2026-06-02). All clickable menus render at 1920×1080 (content
# scale swapped per-screen via HdScreen/HdViewportScope), so 1 logical px = 1
# screen px and fonts are sized for that canvas. The in-combat 480×270 HUD does
# NOT use these — every native text surface (wave banner, score counter, the
# one main.tscn label) sets its own explicit size, so retuning here is safe.
const FONT_SIZE_TITLE   := 48
const FONT_SIZE_HEADER  := 30
const FONT_SIZE_BODY    := 22
const FONT_SIZE_BUTTON  := 26
const FONT_SIZE_CAPTION := 16

# ----- Font face ---------------------------------------------------------
# Two faces are preloaded so the player can swap via the Options menu
# without a restart. Pixel Operator is the default — designed for 8/16/24
# pixel sizes and looks correct at our small font sizes. Pixelify Sans is
# a softer TTF alternative with similar pixel-grid characteristics for
# players who prefer it.
const FONT_PIXEL = preload("res://graphics/fonts/PixelOperator.ttf")
const FONT_TTF = preload("res://graphics/fonts/PixelifySans.ttf")


# Look up the active font face from the Settings autoload. Defaults to
# Pixel Operator if Settings hasn't been loaded yet (which would only
# happen during very early scene boot, before autoloads).
#
# TWO Pixel Operator variants:
#  - CRISP (antialiasing/subpixel/hinting off) — for the native 480×270 HUD,
#    which is nearest-upscaled 4× by the canvas stretch. AA-off + upscale =
#    the intended hard pixel look.
#  - SMOOTH (gray antialiasing) — for HD (1920×1080) menus, which render the
#    font at 1:1 (no upscale). AA-off at HD makes non-grid-aligned sizes
#    (22, 26, 30, 18, 36…) render jagged/uneven — the "distorted" menu text.
#    Light AA smooths the letterforms so any size reads cleanly at HD.
# Both cached so the per-call cost is one lookup.
static var _pixel_font_crisp: FontFile = null
static var _pixel_font_smooth: FontFile = null

# Crisp face for the native HUD + the project theme default (so unstyled
# controls and the in-combat HUD keep the hard pixel look).
static func active_font() -> Font:
	if Engine.is_editor_hint():
		return _get_pixel_crisp()
	if _font_is_ttf():
		return FONT_TTF
	return _get_pixel_crisp()


# Smooth face for HD menus. Routed through by style_label/style_button so every
# themed menu control gets clean text at HD. TTF (Pixelify Sans) is already
# smooth, so it's returned as-is when selected.
static func menu_font() -> Font:
	if _font_is_ttf():
		return FONT_TTF
	return _get_pixel_smooth()


static func _font_is_ttf() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("Settings"):
		var settings = tree.root.get_node("Settings")
		if settings and "font_style" in settings:
			return String(settings.font_style) == "ttf"
	return false


static func _get_pixel_crisp() -> FontFile:
	if _pixel_font_crisp != null:
		return _pixel_font_crisp
	_pixel_font_crisp = FONT_PIXEL.duplicate()
	_pixel_font_crisp.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_pixel_font_crisp.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_pixel_font_crisp.hinting = TextServer.HINTING_NONE
	return _pixel_font_crisp


static func _get_pixel_smooth() -> FontFile:
	if _pixel_font_smooth != null:
		return _pixel_font_smooth
	_pixel_font_smooth = FONT_PIXEL.duplicate()
	_pixel_font_smooth.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_pixel_font_smooth.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_pixel_font_smooth.hinting = TextServer.HINTING_NONE
	return _pixel_font_smooth

# ----- Label kinds -------------------------------------------------------
enum LabelKind {
	TITLE,
	HEADER,
	BODY,
	BOUNTY,
	CAPTION,
	DANGER,
	# Outpost-style "Hull: 12/20" right-aligned readout — body weight,
	# accent-tinted, denser outline. Folded in from outpost.gd's local
	# STATUS_VALUE preset 2026-05-26 so the same look applies to the
	# Manage Ship modal + future status surfaces.
	STATUS_VALUE,
	# Outpost / sector-map slot badges ("CANNON", "WING L") — caption
	# size, accent-tinted, thin outline. Folded in from outpost.gd's
	# local SLOT_PILL preset 2026-05-26.
	SLOT_PILL,
}

# ----- Hologram material presets (legacy enum kept for compatibility) ----
enum HoloPreset {
	TITLE,
	OVERLAY,
	HUD,
	NEUTRAL,
}

# No-op shim. The holo shader has been removed from the UI; callers can keep
# calling this and assigning the result to `.material` (which becomes null,
# i.e. "no material"). Safe to delete the call sites at leisure.
static func make_holo_material(_preset: int = HoloPreset.OVERLAY) -> ShaderMaterial:
	return null


# Build the canonical button stylebox set — flat dark fill, bright accent
# border, brighter on hover/press, dim on disabled. `dense` shrinks the
# vertical padding for in-game / pause menus. Returned as a dict keyed by
# Button state name so both style_button() (per-control overrides) and the
# project Theme.tres generator (tools/build_ui_theme.gd) share one source
# of truth — change the look here and both follow.
static func button_styleboxes(dense: bool = false, pad_h: int = 20) -> Dictionary:
	var pad_v: int = 6 if dense else 10

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.16, 0.85)
	sb.border_color = COLOR_ACCENT_DIM
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v

	var sb_hover: StyleBoxFlat = sb.duplicate()
	sb_hover.bg_color = Color(0.14, 0.20, 0.30, 0.92)
	sb_hover.border_color = COLOR_ACCENT

	var sb_pressed: StyleBoxFlat = sb.duplicate()
	sb_pressed.bg_color = Color(0.22, 0.32, 0.46, 0.95)
	sb_pressed.border_color = COLOR_WHITE

	var sb_disabled: StyleBoxFlat = sb.duplicate()
	sb_disabled.bg_color = Color(0.06, 0.08, 0.11, 0.7)
	sb_disabled.border_color = Color(0.25, 0.30, 0.35, 0.6)

	return {
		"normal": sb,
		"hover": sb_hover,
		"pressed": sb_pressed,
		"focus": sb_hover,
		"disabled": sb_disabled,
	}


# Apply the canonical button look. Idempotent. `dense` shrinks vertical
# padding for in-game / pause menus.
#
# NOTE: with the project Theme.tres registered, plain Buttons already get
# this look for free. This helper remains for (a) the `dense` variant and
# (b) callers that want explicit control; the per-control overrides simply
# win over the theme default, so calling it is always safe. `pad_h` shrinks
# the horizontal padding for dense surfaces (e.g. the shop's compact cards),
# where the default 20px would balloon small buttons past their card width.
static func style_button(btn: Button, dense: bool = false, pad_h: int = 20) -> void:
	if btn == null:
		return
	btn.add_theme_font_override("font", menu_font())
	btn.add_theme_font_size_override("font_size", FONT_SIZE_BUTTON)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_color_override("font_hover_color", COLOR_WHITE)
	btn.add_theme_color_override("font_pressed_color", COLOR_ACCENT)
	btn.add_theme_color_override("font_focus_color", COLOR_WHITE)
	btn.add_theme_color_override("font_disabled_color", COLOR_DISABLED)
	btn.flat = false

	var boxes := button_styleboxes(dense, pad_h)
	btn.add_theme_stylebox_override("normal", boxes["normal"])
	btn.add_theme_stylebox_override("hover", boxes["hover"])
	btn.add_theme_stylebox_override("pressed", boxes["pressed"])
	btn.add_theme_stylebox_override("focus", boxes["focus"])
	btn.add_theme_stylebox_override("disabled", boxes["disabled"])


# ----- Shared control kit -------------------------------------------------
# Thin factories for the patterns every menu rebuilds by hand. Route new UI
# through these so a button is always built + styled the same way.

# A styled Button in one call. With the project Theme registered, a plain
# Button already looks right, but make_button() guarantees it (incl. the
# `dense` variant) and gives callers one obvious entry point.
static func make_button(text: String, dense: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	style_button(b, dense)
	return b


# Label + horizontal-fill control on one row ("Fullscreen   [x]"). Appends
# the row to `parent` and returns it. `label_w` pins the label column so
# stacked rows align; 0 lets it size to content + EXPAND_FILL.
static func make_labeled_row(parent: Node, label_text: String, control: Control, label_w: int = 0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label_text
	if label_w > 0:
		lbl.custom_minimum_size = Vector2(label_w, 0)
	else:
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style_label(lbl, LabelKind.BODY)
	row.add_child(lbl)
	row.add_child(control)
	parent.add_child(row)
	return row


# A labelled 0..1 HSlider row with a live "%d%%" readout. Mirrors the
# options-overlay slider; appends to `parent` and returns the HSlider.
static func make_slider_row(parent: Node, label_text: String, initial: float, on_changed: Callable, label_w: int = 96) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(label_w, 0)
	style_label(lbl, LabelKind.BODY)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(80, 14)
	slider.value_changed.connect(on_changed)
	row.add_child(slider)
	var pct := Label.new()
	pct.custom_minimum_size = Vector2(32, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.text = "%d%%" % int(round(initial * 100.0))
	style_label(pct, LabelKind.CAPTION)
	row.add_child(pct)
	slider.value_changed.connect(func(v: float):
		pct.text = "%d%%" % int(round(v * 100.0))
	)
	return slider


# ----- Runtime font swap --------------------------------------------------
# The project Theme.tres carries a static default_font, but the player can
# toggle Pixel Operator ↔ Pixelify Sans live via Options. A static .tres
# can't follow that, so we push the active face into the in-memory project
# theme's `default_font`; theme change propagates to every Control that
# hasn't set its own font override. Call at boot (Settings._ready) and on
# every font toggle (Settings.set_font_style). Cheap + idempotent.
static func apply_font_to_default_theme() -> void:
	var th := ThemeDB.get_project_theme()
	if th != null:
		th.default_font = active_font()


# Convenience: style any Label according to one of the LabelKind presets.
# Idempotent; safe to call from _render() loops.
static func style_label(lbl: Label, kind: int = LabelKind.BODY) -> void:
	if lbl == null:
		return
	lbl.add_theme_font_override("font", menu_font())
	match kind:
		LabelKind.TITLE:
			lbl.add_theme_font_size_override("font_size", FONT_SIZE_TITLE)
			lbl.add_theme_color_override("font_color", COLOR_WHITE)
			lbl.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
			lbl.add_theme_constant_override("outline_size", 6)
		LabelKind.HEADER:
			lbl.add_theme_font_size_override("font_size", FONT_SIZE_HEADER)
			lbl.add_theme_color_override("font_color", COLOR_ACCENT)
			lbl.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
			lbl.add_theme_constant_override("outline_size", 4)
		LabelKind.BODY:
			lbl.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
			lbl.add_theme_color_override("font_color", COLOR_TEXT)
			lbl.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
			lbl.add_theme_constant_override("outline_size", 3)
		LabelKind.BOUNTY:
			lbl.add_theme_font_size_override("font_size", FONT_SIZE_BODY + 4)
			lbl.add_theme_color_override("font_color", COLOR_BOUNTY)
			lbl.add_theme_color_override("font_outline_color", Color(0.18, 0.08, 0.0, 1.0))
			lbl.add_theme_constant_override("outline_size", 4)
		LabelKind.CAPTION:
			lbl.add_theme_font_size_override("font_size", FONT_SIZE_CAPTION)
			lbl.add_theme_color_override("font_color", COLOR_FAINT)
		LabelKind.DANGER:
			lbl.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
			lbl.add_theme_color_override("font_color", COLOR_DANGER)
			lbl.add_theme_color_override("font_outline_color", COLOR_DANGER_DK)
			lbl.add_theme_constant_override("outline_size", 4)
		LabelKind.STATUS_VALUE:
			lbl.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
			lbl.add_theme_color_override("font_color", COLOR_ACCENT)
			lbl.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
			lbl.add_theme_constant_override("outline_size", 3)
		LabelKind.SLOT_PILL:
			lbl.add_theme_font_size_override("font_size", FONT_SIZE_CAPTION)
			lbl.add_theme_color_override("font_color", COLOR_ACCENT)
			lbl.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
			lbl.add_theme_constant_override("outline_size", 2)


# Build a flat dark panel StyleBox for menu backgrounds. Used by panels that
# want a card look on top of the parallax starfield.
static func make_panel_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_PANEL_BG
	sb.border_color = COLOR_ACCENT_DIM
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb


# ----- Shared modal scaffold ---------------------------------------------
# Every in-game modal (Manage Ship, Pause confirm, Pick Screen, No Bounty,
# Test Hazard picker) used to build the same CanvasLayer + dim ColorRect +
# centered PanelContainer + VBox by hand — ~50 lines per modal. Route new
# modals (and migrate old ones at leisure) through this factory.
#
# Returns {layer, panel, vbox, dim} so the caller can append content to
# `vbox`, attach a Cancel handler to `dim` if desired, and free `layer`
# to dismiss. `vbox` already has the standard 8px separation; override
# via `vbox.add_theme_constant_override("separation", N)` if needed.
#
# `min_size` lets the caller widen the panel without hand-rolling
# CenterContainer math. Default (160, 0) matches the Pick Screen modal.
static func make_modal(layer_idx: int = 90, min_size: Vector2 = Vector2(160, 0)) -> Dictionary:
	var layer := CanvasLayer.new()
	layer.layer = layer_idx
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.70)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_PANEL_BG
	sb.border_color = COLOR_ACCENT_DIM
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	if min_size != Vector2.ZERO:
		vbox.custom_minimum_size = min_size
	panel.add_child(vbox)
	return {"layer": layer, "dim": dim, "panel": panel, "vbox": vbox}


# ----- Off-screen guardrail ----------------------------------------------
# Walks `root`'s Control descendants and warns about anyone whose global
# rect extends past the viewport. Debug-only — no-op in release builds so
# the production game pays nothing.
#
# Call at the end of every menu's _build_ui() to catch "I forgot the
# panel is wider than 480 minus margins" bugs at scene-load time instead
# of at playtest time. Warnings include node path + overflow px so the
# offender is easy to find.
static func assert_inside_viewport(root: Node) -> void:
	if not OS.is_debug_build():
		return
	if root == null or not root.is_inside_tree():
		return
	var vp_rect: Rect2 = root.get_viewport().get_visible_rect()
	# Inflate by 1px to absorb single-pixel rounding (which is harmless
	# visually but trips a strict rect contains check).
	vp_rect = vp_rect.grow(1)
	_walk_overflow(root, root, vp_rect)


static func _walk_overflow(root: Node, n: Node, vp_rect: Rect2) -> void:
	if n is Control and _is_ui_control(n):
		var c: Control = n
		# Only flag Controls that are actually drawn; hidden or zero-size
		# layout helpers (VBox spacers, etc.) trip false positives.
		if c.visible and c.size.x > 0.0 and c.size.y > 0.0:
			var r: Rect2 = c.get_global_rect()
			if not vp_rect.encloses(r):
				var overflow := Vector2(
					maxf(r.end.x - vp_rect.end.x, 0.0) + maxf(vp_rect.position.x - r.position.x, 0.0),
					maxf(r.end.y - vp_rect.end.y, 0.0) + maxf(vp_rect.position.y - r.position.y, 0.0),
				)
				# Ignore single-pixel rounding from anchor-centered layouts.
				if overflow.x >= 2.0 or overflow.y >= 2.0:
					push_warning("UI overflow: %s extends past viewport by (%d, %d)px (rect=%s, vp=%s)" % [
						root.get_path_to(c), int(overflow.x), int(overflow.y), r, vp_rect,
					])
	for child in n.get_children():
		_walk_overflow(root, child, vp_rect)


# Filter: only walk Controls that live in a Control-only ancestry. Controls
# embedded under a Node2D subtree (parallax planets, backdrop SubViewport
# wrappers) are scene decoration whose extents are author-intentional —
# warning on those is just noise. The viewport-overflow check is for UI
# tree surfaces (menus, modals, HUD), which always anchor to Control roots.
static func _is_ui_control(n: Node) -> bool:
	var p: Node = n.get_parent()
	while p != null:
		if p is Node2D:
			return false
		p = p.get_parent()
	return true

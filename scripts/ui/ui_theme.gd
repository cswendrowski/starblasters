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
const COLOR_DANGER     := Color(1.00, 0.40, 0.32, 1.0)  # alert red
const COLOR_DANGER_DK  := Color(0.40, 0.05, 0.00, 1.0)  # alert outline
const COLOR_DISABLED   := Color(0.45, 0.50, 0.58, 0.75)
const COLOR_FAINT      := Color(0.70, 0.78, 0.88, 0.70) # version label, captions
const COLOR_WHITE      := Color(1, 1, 1, 1)
const COLOR_PANEL_BG   := Color(0.05, 0.07, 0.11, 0.82) # menu panels — near-black

# Legacy aliases — older scripts reference COLOR_HOLO. Map to the accent.
const COLOR_HOLO := COLOR_ACCENT

# ----- Font sizes --------------------------------------------------------
# 320×400 res rework — font sizes scaled for the smaller canvas.
const FONT_SIZE_TITLE   := 28
const FONT_SIZE_HEADER  := 16
const FONT_SIZE_BODY    := 12
const FONT_SIZE_BUTTON  := 14
const FONT_SIZE_CAPTION := 10

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
# For Pixel Operator we force antialiasing/subpixel/hinting off at
# runtime so the bitmap font renders pixel-perfect even if the import
# cache shipped with antialiasing enabled. Cached so the per-call cost
# is one dictionary lookup.
static var _pixel_font_crisp: FontFile = null

static func active_font() -> Font:
	if Engine.is_editor_hint():
		return _get_pixel_crisp()
	var settings = null
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("Settings"):
		settings = tree.root.get_node("Settings")
	if settings and "font_style" in settings and String(settings.font_style) == "ttf":
		return FONT_TTF
	return _get_pixel_crisp()


static func _get_pixel_crisp() -> FontFile:
	if _pixel_font_crisp != null:
		return _pixel_font_crisp
	_pixel_font_crisp = FONT_PIXEL.duplicate()
	_pixel_font_crisp.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_pixel_font_crisp.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_pixel_font_crisp.hinting = TextServer.HINTING_NONE
	return _pixel_font_crisp

# ----- Label kinds -------------------------------------------------------
enum LabelKind {
	TITLE,
	HEADER,
	BODY,
	BOUNTY,
	CAPTION,
	DANGER,
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


# Apply the canonical button look — flat dark fill, bright accent border,
# brighter border on hover/press, dim on disabled. Idempotent. `dense`
# shrinks vertical padding for in-game / pause menus.
static func style_button(btn: Button, dense: bool = false) -> void:
	if btn == null:
		return
	btn.add_theme_font_override("font", active_font())
	btn.add_theme_font_size_override("font_size", FONT_SIZE_BUTTON)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_color_override("font_hover_color", COLOR_WHITE)
	btn.add_theme_color_override("font_pressed_color", COLOR_ACCENT)
	btn.add_theme_color_override("font_focus_color", COLOR_WHITE)
	btn.add_theme_color_override("font_disabled_color", COLOR_DISABLED)
	btn.flat = false

	var pad_v: int = 6 if dense else 10

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.16, 0.85)
	sb.border_color = COLOR_ACCENT_DIM
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 20
	sb.content_margin_right = 20
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

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_pressed)
	btn.add_theme_stylebox_override("focus", sb_hover)
	btn.add_theme_stylebox_override("disabled", sb_disabled)


# Convenience: style any Label according to one of the LabelKind presets.
# Idempotent; safe to call from _render() loops.
static func style_label(lbl: Label, kind: int = LabelKind.BODY) -> void:
	if lbl == null:
		return
	lbl.add_theme_font_override("font", active_font())
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

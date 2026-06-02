extends SceneTree
# One-shot generator for the project UI Theme resource. Run headless:
#   E:\tools\Godot_v4.6.3\...\Godot.exe --path . --headless --script res://tools/build_ui_theme.gd
#
# Reads UiTheme's palette / font sizes / styleboxes so the saved .tres never
# drifts from code (scripts/ui/ui_theme.gd is the single source of truth).
# Re-run this after changing the palette or button look in UiTheme.
#
# The theme is registered as the project default via gui/theme/custom in
# project.godot, so plain Button/Label/OptionButton/PanelContainer inherit
# the look with no per-control styling calls. The Pixel↔TTF font toggle is
# applied at runtime over default_font (UiTheme.apply_font_to_default_theme).

const OUT_DIR := "res://resources/ui"
const OUT_PATH := "res://resources/ui/starblaster_theme.tres"

func _initialize() -> void:
	if not DirAccess.dir_exists_absolute(OUT_DIR):
		DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var theme := Theme.new()
	# Default font: reference the original .ttf (saves as an ext_resource, not
	# an embedded duplicate). Runtime swaps this for the crisp/AA-off face.
	theme.default_font = UiTheme.FONT_PIXEL
	theme.default_font_size = UiTheme.FONT_SIZE_BODY

	# --- Button ---
	var b := UiTheme.button_styleboxes(false)
	theme.set_stylebox("normal", "Button", b["normal"])
	theme.set_stylebox("hover", "Button", b["hover"])
	theme.set_stylebox("pressed", "Button", b["pressed"])
	theme.set_stylebox("focus", "Button", b["focus"])
	theme.set_stylebox("disabled", "Button", b["disabled"])
	theme.set_font_size("font_size", "Button", UiTheme.FONT_SIZE_BUTTON)
	theme.set_color("font_color", "Button", UiTheme.COLOR_TEXT)
	theme.set_color("font_hover_color", "Button", UiTheme.COLOR_WHITE)
	theme.set_color("font_pressed_color", "Button", UiTheme.COLOR_ACCENT)
	theme.set_color("font_focus_color", "Button", UiTheme.COLOR_WHITE)
	theme.set_color("font_disabled_color", "Button", UiTheme.COLOR_DISABLED)

	# --- OptionButton (same skin as Button) ---
	var ob := UiTheme.button_styleboxes(false)
	theme.set_stylebox("normal", "OptionButton", ob["normal"])
	theme.set_stylebox("hover", "OptionButton", ob["hover"])
	theme.set_stylebox("pressed", "OptionButton", ob["pressed"])
	theme.set_stylebox("focus", "OptionButton", ob["focus"])
	theme.set_stylebox("disabled", "OptionButton", ob["disabled"])
	theme.set_font_size("font_size", "OptionButton", UiTheme.FONT_SIZE_BUTTON)
	theme.set_color("font_color", "OptionButton", UiTheme.COLOR_TEXT)
	theme.set_color("font_hover_color", "OptionButton", UiTheme.COLOR_WHITE)
	theme.set_color("font_pressed_color", "OptionButton", UiTheme.COLOR_ACCENT)
	theme.set_color("font_focus_color", "OptionButton", UiTheme.COLOR_WHITE)
	theme.set_color("font_disabled_color", "OptionButton", UiTheme.COLOR_DISABLED)

	# --- Label (body default; presets via UiTheme.style_label still win) ---
	theme.set_font_size("font_size", "Label", UiTheme.FONT_SIZE_BODY)
	theme.set_color("font_color", "Label", UiTheme.COLOR_TEXT)
	theme.set_color("font_outline_color", "Label", UiTheme.COLOR_OUTLINE)
	theme.set_constant("outline_size", "Label", 3)

	# --- PanelContainer (menu card background) ---
	theme.set_stylebox("panel", "PanelContainer", UiTheme.make_panel_stylebox())

	var err := ResourceSaver.save(theme, OUT_PATH)
	if err != OK:
		push_error("theme save failed: %d" % err)
	else:
		print("wrote ", OUT_PATH)
	quit()

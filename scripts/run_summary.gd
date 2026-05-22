extends Control

# Run summary shown after death. Black backdrop, big title, stats, two
# buttons (New Game + Main Menu) + Quit. Code-driven layout to avoid the
# old .tscn's broken Panel anchors that caused a black-screen-only result.

const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SectorMapRoute = preload("res://scripts/sector_map_route.gd")

@onready var title_label: Label = $Center/Panel/VBox/Title
@onready var stats_label: Label = $Center/Panel/VBox/Stats
@onready var new_game_btn: Button = $Center/Panel/Buttons/NewGameBtn
@onready var menu_btn: Button = $Center/Panel/Buttons/MenuBtn
@onready var quit_btn: Button = $Center/Panel/Buttons/QuitBtn

func _ready() -> void:
	# Force the root + Center to fill the viewport, regardless of parent.
	# When this scene is loaded by change_scene_to_file Godot auto-fills,
	# but when instanced under a Node2D (showcase capture) it stays 0x0.
	var vp: Vector2 = get_viewport_rect().size
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO
	size = vp
	z_index = 100
	# Belt-and-braces: keep the panel visible from the jump. The previous
	# fade-in tween was hiding the menu when SceneTransition's in-wipe ran
	# slow, leaving the player staring at black.
	$Center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$Center.position = Vector2.ZERO
	$Center.size = vp
	$Center.modulate = Color(1, 1, 1, 1)
	$Center.visible = true
	# Sector backdrop so the death screen reads as the same meta state
	# as the main menu / cleared screen (Roman, 2026-05-17).
	if $Bg:
		$Bg.color = Color(0, 0, 0, 0)
	var bg := TextureRect.new()
	bg.name = "SummaryBg"
	bg.texture = load("res://graphics/ui/sector_bg.png")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, 0)
	new_game_btn.text = "New Game"
	menu_btn.text = "Main Menu"
	quit_btn.text = "Quit"
	# Unified styling.
	if title_label:
		UiTheme.style_label(title_label, UiTheme.LabelKind.TITLE)
		title_label.material = UiTheme.make_holo_material(UiTheme.HoloPreset.OVERLAY)
	if stats_label:
		UiTheme.style_label(stats_label, UiTheme.LabelKind.BODY)
		stats_label.material = UiTheme.make_holo_material(UiTheme.HoloPreset.OVERLAY)
	for b in [new_game_btn, menu_btn, quit_btn]:
		UiTheme.style_button(b)
	new_game_btn.pressed.connect(_new_game)
	menu_btn.pressed.connect(_to_menu)
	quit_btn.pressed.connect(_quit)
	_render()


func _style_outline_button(btn: Button) -> void:
	UiTheme.style_button(btn)

func _render() -> void:
	var text := ""
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		text = "Enemies destroyed: %d\nSectors cleared: %d\nMax bounty: %d\nDistance: %d" % [
			run.enemies_killed, run.sectors_cleared, run.max_bounty_earned, int(run.run_distance)
		]
	else:
		text = "No run data."
	stats_label.text = text

func _new_game() -> void:
	if has_node("/root/Run"):
		get_node("/root/Run").new_run()
	SceneTransition.change_scene(get_tree(), SectorMapRoute.SECTOR_MAP_SCENE)

func _to_menu() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")

func _quit() -> void:
	get_tree().quit()

extends CanvasLayer

# Cleared summary screen. Reveals top-down with a brief per-element fade-in
# (total reveal ≈ 2.5s). Tally + button are bottom-anchored so their position
# is consistent regardless of how many enemy types are in the list.
#
# Inputs to populate():
#   enemy_stats: { scene_path: { "spawned": int, "killed": int, "bounty": int,
#                                 "total_bounty": int } }
#   total_bounty: int

const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SECTOR_MAP_SCENE := "res://scenes/sector_map_v2.tscn"

# Cached enemy sprite textures keyed by scene path.
static var _sprite_cache: Dictionary = {}

var _shared_mat: ShaderMaterial = null

func _ready() -> void:
	layer = 90
	_build_material()
	# Painted sector backdrop so the cleared screen reads as the same
	# meta-state as the sector map / main menu (Roman, 2026-05-17).
	if has_node("Bg"):
		var bg: ColorRect = $Bg
		bg.visible = false
	_install_backdrop()
	# Decompress the combat track while the summary holds — and freeze the
	# intensity walk so the music doesn't keep ramping up/down behind the
	# CLEARED screen (Roman, 2026-05-16).
	if has_node("/root/Music"):
		var music = get_node("/root/Music")
		music.ramp_down()
		music.set_walk_frozen(true)

func _build_material() -> void:
	_shared_mat = UiTheme.make_holo_material(UiTheme.HoloPreset.OVERLAY)


func _install_backdrop() -> void:
	# Sector-bg as a fullscreen TextureRect behind everything. Same look
	# as the main menu / sector map / onboarding.
	var bg := TextureRect.new()
	bg.name = "SummaryBg"
	bg.texture = load("res://graphics/ui/sector_bg.png")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, 0)

func populate(enemy_stats: Dictionary, total_bounty: int, hide_tally: bool = false, was_boss: bool = false) -> void:
	var title: Label = $Root/Title
	var list: VBoxContainer = $Root/List
	var total_label: Label = $Root/Bottom/TotalBounty
	var btn: Button = $Root/Bottom/MapBtn

	title.text = "SECTOR CLEARED" if was_boss else "CLEARED!"
	UiTheme.style_label(title, UiTheme.LabelKind.TITLE)
	title.material = _shared_mat
	for c in list.get_children():
		c.queue_free()
	var rows: Array = []
	# Hazards render a stripped-down summary: no enemy tally, no bounty.
	if hide_tally:
		total_label.visible = false
	else:
		total_label.visible = true
		total_label.text = "TOTAL BOUNTY: %d" % total_bounty
		UiTheme.style_label(total_label, UiTheme.LabelKind.BOUNTY)
		total_label.material = _shared_mat
		var keys: Array = enemy_stats.keys()
		keys.sort()
		for path in keys:
			var row := _build_row(path, enemy_stats[path])
			list.add_child(row)
			rows.append(row)

	btn.material = null
	_style_outline_button(btn)
	# Re-label when this is a Test Hazard run so the player knows the button
	# bounces them to the main menu, not a sector map (which doesn't exist
	# for a test launch).
	if has_node("/root/Run") and get_node("/root/Run").test_mode_active:
		btn.text = "[ MAIN MENU ]"
	if not btn.pressed.is_connected(_on_map_pressed):
		btn.pressed.connect(_on_map_pressed)

	# Boss arena clear → endless-mode prompt. Hide the single map button and
	# install a Menu + Next Sector pair right next to the total-bounty line.
	# Buttons live under $Root/Bottom so they ride the same fade-in pass.
	var endless_buttons: Array = []
	if was_boss:
		btn.visible = false
		endless_buttons = _install_endless_buttons(btn.get_parent())

	var reveal_btn = btn
	if not endless_buttons.is_empty():
		# Reveal both buttons in sequence; pick the last one to align with the
		# existing single-button reveal slot.
		reveal_btn = endless_buttons[endless_buttons.size() - 1]
		# Animate the first one alongside.
		endless_buttons[0].modulate.a = 0.0
		var tw0 := create_tween()
		tw0.tween_interval(0.4)
		tw0.tween_property(endless_buttons[0], "modulate:a", 1.0, 0.25)
	_play_reveal(title, rows, total_label if not hide_tally else null, reveal_btn)


# Build a horizontal row with [ Main Menu ] and [ Next Sector ] buttons under
# the cleared summary's bottom anchor. Returned in order so the caller can
# fade them in.
func _install_endless_buttons(bottom: Node) -> Array:
	var row := HBoxContainer.new()
	row.name = "EndlessChoiceRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	bottom.add_child(row)
	var menu_btn := Button.new()
	menu_btn.text = "[ MAIN MENU ]"
	UiTheme.style_button(menu_btn)
	menu_btn.pressed.connect(_on_end_run)
	row.add_child(menu_btn)
	var next_btn := Button.new()
	next_btn.text = "[ NEXT SECTOR ]"
	UiTheme.style_button(next_btn)
	next_btn.pressed.connect(_on_next_sector)
	row.add_child(next_btn)
	return [menu_btn, next_btn]


# End the run — back to main menu, fresh start next time.
func _on_end_run() -> void:
	var root: Control = $Root
	var tw = create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw.finished
	SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")


# Next sector — reset combats_in_sector, reroll the sector_map seed so the
# new map looks fresh, and transition back to the sector_map scene. The
# wave generator will pick up `sectors_cleared` to bump difficulty.
func _on_next_sector() -> void:
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		run.combats_in_sector = 0
		run.visited_nodes = []
		run.current_node_id = ""
		run.current_node_type = -1
		run.run_seed = randi()
		# Drop the cached map so the next sector rolls fresh.
		run.sector_map_cache = {}
	var root: Control = $Root
	var tw = create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw.finished
	SceneTransition.change_scene(get_tree(), "res://scenes/sector_map_v2.tscn")


func _play_reveal(title: Label, rows: Array, total_label, btn: Button) -> void:
	# Start everything invisible, then sequentially fade each element in.
	# Total budget: ~2.5s regardless of how many rows. `total_label` may be
	# null when the caller is hiding the tally (hazards).
	var elements: Array = [title]
	for r in rows:
		elements.append(r)
	if total_label != null:
		elements.append(total_label)
	elements.append(btn)
	for e in elements:
		e.modulate.a = 0.0
	# Cap per-step so total fits 2.5s even with many rows.
	var step: float = clamp(1.8 / float(max(1, elements.size())), 0.18, 0.32)
	var fade: float = 0.25
	for i in elements.size():
		var e = elements[i]
		var tw = create_tween()
		tw.tween_interval(step * float(i))
		tw.tween_property(e, "modulate:a", 1.0, fade).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _build_row(scene_path: String, stats: Dictionary) -> Control:
	var row := HBoxContainer.new()
	# Tighter separation + name/bounty labels capped so the bounty math
	# doesn't overflow the right edge of the 320-wide viewport (Roman,
	# 2026-05-17 playtest: "number killed and bounty value is too far
	# right and off screen").
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Sprite preview — render the actual enemy scene into a tiny SubViewport.
	# Bumped from 36 -> 22 with the sprite scaled down half-size inside it
	# so the enemy art reads centered instead of clipping.
	var preview: Control = _build_scene_preview(scene_path, 22)
	row.add_child(preview)
	# Name + kills
	var name_str := scene_path.get_file().get_basename()
	if name_str.begins_with("enemy_"):
		name_str = name_str.substr(6)
	name_str = name_str.capitalize()
	preview.material = _shared_mat
	var counts := Label.new()
	counts.text = "%s  %d/%d" % [name_str, stats.killed, stats.spawned]
	counts.add_theme_font_size_override("font_size", 11)
	counts.add_theme_color_override("font_color", UiTheme.COLOR_HOLO)
	counts.add_theme_font_override("font", UiTheme.active_font())
	# 320-wide viewport - preview (22) - sep (6) - bounty math (~110) -
	# margins = ~150 left for name/count. Cap so layout doesn't bleed.
	counts.custom_minimum_size = Vector2(140, 0)
	counts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	counts.material = _shared_mat
	row.add_child(counts)
	# Bounty math — right-justified, fixed width so the "= total" lands at
	# a consistent x across rows.
	var bounty_label := Label.new()
	bounty_label.text = "%d×%d=%d" % [stats.bounty, stats.killed, stats.total_bounty]
	bounty_label.add_theme_font_size_override("font_size", 11)
	bounty_label.add_theme_color_override("font_color", UiTheme.COLOR_BOUNTY)
	bounty_label.add_theme_font_override("font", UiTheme.active_font())
	bounty_label.custom_minimum_size = Vector2(70, 0)
	bounty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bounty_label.material = _shared_mat
	row.add_child(bounty_label)
	return row


# Builds a SubViewport-backed preview of the enemy scene. The scene's own
# AnimationPlayer / RESET track / _ready leaves the Sprite2D on whatever
# frame it would have at spawn time, and we screenshot exactly that.
# Pausing process_mode means the enemy doesn't move / shoot / spawn anything
# while it sits in the viewport.
func _build_scene_preview(scene_path: String, size: int) -> Control:
	var packed = load(scene_path)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(size, size)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Sized so a 16px sprite at 3x = 48px fits in the 36px preview window
	# centered horizontally + vertically.
	container.add_child(vp)
	if packed is PackedScene:
		var inst = packed.instantiate()
		# Freeze the enemy entirely — no movement, no shooting, no animation
		# beyond the RESET pose. Position it in the center of the viewport.
		inst.process_mode = Node.PROCESS_MODE_DISABLED
		inst.position = Vector2(float(size) * 0.5, float(size) * 0.5)
		# Roman, 2026-05-17 playtest: show enemies at HALF size in the
		# summary so the sprite reads centered without clipping the row.
		# 16-px native sprite → 8 px effective in the 22-px preview window.
		inst.scale = Vector2(0.5, 0.5)
		vp.add_child(inst)
	return container


func _style_outline_button(btn: Button) -> void:
	UiTheme.style_button(btn)


func _on_map_pressed() -> void:
	var btn: Button = $Root/Bottom/MapBtn
	btn.disabled = true
	# Flicker / fade out, then transition back to the sector map — or the main
	# menu if this was a Test Hazard run launched from the main menu.
	var target := SECTOR_MAP_SCENE
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if run.test_mode_active:
			target = "res://scenes/main_menu.tscn"
			run.test_mode_active = false
	var root: Control = $Root
	var tw = create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw.finished
	SceneTransition.change_scene(get_tree(), target)

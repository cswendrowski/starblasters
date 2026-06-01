extends Control

# Enemy Codex. Two-page view of every enemy the player has encountered
# (Run.encountered_enemies). Left: scrollable list with sprite + name.
# Right: live looping demo of the selected enemy running its default
# pattern in the codex viewport, hologram-shaded.
#
# Roman, 2026-05-16: "build an enemy codex accessible from the main
# menu... two-page view with the left having the list of sprites and
# names, and to right a looping demo of the selected enemy's pattern.
# Whenever an enemy is shown in the clear screen for the first time,
# add them to the codex as well."

const SceneTransition = preload("res://scripts/scene_transition.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

# Static lookup: every enemy scene → display name + entry hint.
const ENTRIES = [
	{"path": "res://scenes/enemies/enemy_dart.tscn",     "name": "Dart",     "tier": "Common", "blurb": "Pure movement, no fire. Teaches you to shoot proactively."},
	{"path": "res://scenes/enemies/enemy_drifter.tscn",  "name": "Drifter",  "tier": "Common", "blurb": "Halves into +drift / -drift squads. Easy spacing puzzle."},
	{"path": "res://scenes/enemies/enemy_firecore.tscn", "name": "Firecore", "tier": "Common", "blurb": "Lazy single-shot chaff. Punish first, sweep second."},
	{"path": "res://scenes/enemies/enemy_hunter_drone.tscn", "name": "Hunter Drone", "tier": "Common", "blurb": "Beelines at the player. Don't let it catch up."},
	{"path": "res://scenes/enemies/enemy_cutter.tscn",   "name": "Cutter",   "tier": "Uncommon", "blurb": "Side-entry strafer. Alternates flanks, fires fast and exits."},
	{"path": "res://scenes/enemies/enemy_weaver.tscn",   "name": "Weaver",   "tier": "Uncommon", "blurb": "Paired center-out arc with aimed shots."},
	{"path": "res://scenes/enemies/enemy_hover.tscn",    "name": "Hover",    "tier": "Uncommon", "blurb": "Loiters at altitude, picks at you with single shots."},
	{"path": "res://scenes/enemies/enemy_skirmisher.tscn", "name": "Skirmisher", "tier": "Uncommon", "blurb": "Advances, retreats, fires aimed bursts. Aggressive."},
	{"path": "res://scenes/enemies/enemy_strafer.tscn",  "name": "Strafer",  "tier": "Common", "blurb": "Head-on pass: dives in, fires a tracer burst, breaks off to the bottom."},
	{"path": "res://scenes/enemies/enemy_frigate.tscn",  "name": "Frigate",  "tier": "Uncommon", "blurb": "Slow advance, burst fire, tough hull."},
	{"path": "res://scenes/enemies/enemy_crystal.tscn",  "name": "Crystal",  "tier": "Rare"},
	{"path": "res://scenes/enemies/enemy_minelayer.tscn", "name": "Minelayer", "tier": "Rare"},
	{"path": "res://scenes/enemies/enemy_interceptor.tscn", "name": "Interceptor", "tier": "Rare"},
	{"path": "res://scenes/enemies/enemy_bulwark.tscn",  "name": "Bulwark",  "tier": "Rare"},
	{"path": "res://scenes/enemies/boss.tscn",            "name": "Commander",  "tier": "Boss"},
	{"path": "res://scenes/enemies/boss_reaver.tscn",     "name": "Lash",       "tier": "Boss"},
	{"path": "res://scenes/enemies/boss_sentinel.tscn",   "name": "Aegis",      "tier": "Boss"},
	{"path": "res://scenes/enemies/boss_howler.tscn",     "name": "Howler",     "tier": "Boss"},
	{"path": "res://scenes/enemies/boss_voidmaw.tscn",    "name": "Voidmaw",    "tier": "Boss"},
	{"path": "res://scenes/enemies/boss_spinwright.tscn", "name": "Spinwright", "tier": "Boss"},
	{"path": "res://scenes/enemies/boss_conductor.tscn",  "name": "Conductor",  "tier": "Boss"},
]
const HOLO_SHADER = preload("res://graphics/hologram.gdshader")

var _preview_holder: Node2D = null
var _preview_enemy: Node = null
var _preview_path: String = ""
var _list_vbox: VBoxContainer = null


func _ready() -> void:
	if has_node("/root/Music"):
		get_node("/root/Music").set_context("menu")
	_build_ui()


func _process(_delta: float) -> void:
	# Wrap the preview enemy back to the top of the pane once it leaves the
	# bottom — keeps the movement/shooting demo looping inside the codex.
	if _preview_enemy != null and is_instance_valid(_preview_enemy) and _preview_enemy is Node2D:
		var n2d: Node2D = _preview_enemy
		if n2d.position.y > 110:
			n2d.position = Vector2(0, -80)


func _build_ui() -> void:
	var vp: Vector2 = get_viewport_rect().size
	size = vp
	# Backdrop.
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.10, 1.0)
	bg.size = vp
	add_child(bg)
	# Title.
	var title := Label.new()
	title.text = "ENEMY CODEX"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(vp.x, 24)
	title.position = Vector2(0, 8)
	UiTheme.style_label(title, UiTheme.LabelKind.HEADER)
	add_child(title)
	# Left column — scrollable list of encountered enemies.
	var left := Panel.new()
	left.add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	left.size = Vector2(140, 220)
	left.position = Vector2(8, 36)
	add_child(left)
	var scroll := ScrollContainer.new()
	scroll.size = left.size - Vector2(12, 12)
	scroll.position = Vector2(6, 6)
	left.add_child(scroll)
	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 4)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_vbox)
	_populate_list()
	# Right column — preview pane.
	var right := Panel.new()
	right.add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	right.size = Vector2(316, 220)
	right.position = Vector2(156, 36)
	add_child(right)
	_preview_holder = Node2D.new()
	_preview_holder.name = "Preview"
	# Center the holder inside the right panel.
	_preview_holder.position = right.position + right.size * 0.5
	add_child(_preview_holder)
	# Back button.
	var back := Button.new()
	back.text = "Back to Menu"
	UiTheme.style_button(back)
	back.position = Vector2(8, 370)
	back.size = Vector2(108, 22)
	back.pressed.connect(func():
		SceneTransition.change_scene(get_tree(), "res://scenes/main_menu.tscn")
	)
	add_child(back)


func _populate_list() -> void:
	if _list_vbox == null:
		return
	for c in _list_vbox.get_children():
		c.queue_free()
	var seen: Dictionary = {}
	if has_node("/root/Run"):
		seen = get_node("/root/Run").encountered_enemies
	# Show ALL entries but grey out the un-encountered ones so the player
	# can see what's left to find without spoiling specifics.
	for entry in ENTRIES:
		var encountered: bool = seen.has(entry["path"])
		var row := Button.new()
		row.text = entry["name"] if encountered else "???"
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UiTheme.style_button(row, true)
		row.disabled = not encountered
		if encountered:
			row.pressed.connect(_on_select.bind(entry))
		_list_vbox.add_child(row)


func _on_select(entry: Dictionary) -> void:
	if _preview_path == String(entry["path"]):
		return
	_preview_path = String(entry["path"])
	_clear_preview()
	var packed = load(entry["path"])
	if packed == null:
		return
	var inst = packed.instantiate()
	if inst is Node2D:
		inst.scale = Vector2(1.0, 1.0)
		# Spawn near the top of the preview pane so its default downward
		# movement reads as motion within the viewport.
		inst.position = Vector2(0, -80)
		# Let the enemy move + shoot in-place. _process below wraps it back
		# to the top when it leaves the bottom so the demo loops forever.
	_apply_hologram_recursive(inst)
	_preview_holder.add_child(inst)
	_preview_enemy = inst


func _clear_preview() -> void:
	if _preview_enemy != null and is_instance_valid(_preview_enemy):
		_preview_enemy.queue_free()
	_preview_enemy = null


# Push a shared hologram ShaderMaterial onto every CanvasItem descendant
# of the preview so the codex entry reads as "scanned simulation".
func _apply_hologram_recursive(n: Node) -> void:
	if n == null:
		return
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = HOLO_SHADER
	mat.set_shader_parameter("holo_color", Color(0.55, 1.0, 0.95, 1.0))
	mat.set_shader_parameter("alpha", 0.92)
	mat.set_shader_parameter("scanline_freq", 110.0)
	mat.set_shader_parameter("scanline_strength", 0.28)
	mat.set_shader_parameter("scanline_scroll_speed", 1.0)
	mat.set_shader_parameter("chromatic_offset", 0.0008)
	mat.set_shader_parameter("jitter_amount", 0.0015)
	mat.set_shader_parameter("flicker_amount", 0.06)
	mat.set_shader_parameter("flicker_speed", 14.0)
	mat.set_shader_parameter("glow", 1.1)
	mat.set_shader_parameter("damage_level", 0.0)
	mat.set_shader_parameter("disruption", 0.0)
	mat.set_shader_parameter("dissolve", 0.0)
	mat.set_shader_parameter("uv_offset", Vector2.ZERO)
	_apply_mat(n, mat)


func _apply_mat(n: Node, mat: ShaderMaterial) -> void:
	if n is CanvasItem:
		(n as CanvasItem).material = mat
	for c in n.get_children():
		_apply_mat(c, mat)

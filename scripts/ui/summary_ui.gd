extends RefCounted

# SummaryUi (Roman 2026-06-11) — shared building blocks for the clear / run-end /
# defeat summary screens, so they stop copy-pasting the backdrop, the M:SS formatter,
# and the enemy-sprite preview. Preload-const (NOT class_name — a fresh global class
# doesn't resolve under headless `-s` until the cache regenerates):
#
#   const SummaryUi = preload("res://scripts/ui/summary_ui.gd")
#
# The enemy preview reuses the CODEX look (clone the hull + glowmap out of the scene,
# add a soft dropshadow — no live SubViewport) so the tally reads the way the codex
# renders enemies. Static, not spinning: a dense kill list shouldn't have N spinners.

const EnemyRoster = preload("res://scripts/levels/enemy_roster.gd")

# Size buckets for sectioning the kill tally. Roster sizes are
# small / medium / large / huge; huge folds into the LARGE section.
const SECTION_ORDER := ["large", "medium", "small"]   # heaviest first
const SECTION_TITLE := {"large": "LARGE", "medium": "MEDIUM", "small": "SMALL"}


# The roster size string for an enemy scene ("small"/"medium"/"large"/"huge"),
# defaulting to "medium" when the scene isn't a roster entry (bosses, hazards).
static func size_for_scene(scene_path: String) -> String:
	var e: Dictionary = EnemyRoster.entry_for_scene(scene_path)
	return String(e.get("size", "medium"))


# The display SECTION bucket for a scene ("large" folds huge in).
static func section_for_scene(scene_path: String) -> String:
	var sz := size_for_scene(scene_path)
	if sz == "large" or sz == "huge":
		return "large"
	if sz == "small":
		return "small"
	return "medium"


static func fmt_mmss(secs: float) -> String:
	var s: int = int(round(secs))
	return "%d:%02d" % [s / 60, s % 60]


# Fullscreen painted sector backdrop (same look as the menu / sector map). Adds it
# behind everything on `host` and returns it.
static func install_backdrop(host: Node) -> TextureRect:
	var bg := TextureRect.new()
	bg.name = "SummaryBg"
	bg.texture = load("res://graphics/ui/sector_bg.png")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(bg)
	host.move_child(bg, 0)
	return bg


# Codex-style enemy preview: a `px`×`px` Control holding the cloned hull (+ glowmap)
# with a soft dropshadow, scaled to fit. Loads + instantiates the scene for its
# sprites only (never added to the tree → no _ready/movement/shaders), then frees it.
static func make_enemy_preview(scene_path: String, px: int) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(px, px)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var packed = load(scene_path)
	if not (packed is PackedScene):
		return box
	var inst = packed.instantiate()
	var hull := _grab_first_sprite(inst, "Sprite2D")
	if hull == null:
		inst.free()
		return box
	var glow = inst.get_node_or_null("GlowMask")
	var holder := Node2D.new()
	holder.position = Vector2(px * 0.5, px * 0.5)
	box.add_child(holder)
	# Fit the sprite's single frame into ~78% of the window, clamped so 16px chaff
	# isn't blown up huge and a 48px cruiser isn't clipped.
	var fw: float = maxf(1.0, float(hull.texture.get_width()) / float(maxi(1, hull.hframes)))
	var fh: float = maxf(1.0, float(hull.texture.get_height()) / float(maxi(1, hull.vframes)))
	var s: float = clampf(float(px) * 0.78 / maxf(fw, fh), 0.5, 2.6)
	holder.scale = Vector2(s, s)
	var shadow := _clone_sprite(hull)
	shadow.modulate = Color(0, 0, 0, 0.32)
	shadow.position = Vector2(2, 3)
	shadow.z_index = -2
	holder.add_child(shadow)
	holder.add_child(_clone_sprite(hull))
	if glow is Sprite2D:
		holder.add_child(_clone_sprite(glow))
	inst.free()
	return box


static func _grab_first_sprite(inst, preferred: String) -> Sprite2D:
	var n = inst.get_node_or_null(preferred)
	if n is Sprite2D:
		return n
	return _search_sprite(inst)


static func _search_sprite(node) -> Sprite2D:
	for c in node.get_children():
		if c is Sprite2D:
			return c
	for c in node.get_children():
		var r := _search_sprite(c)
		if r != null:
			return r
	return null


static func _clone_sprite(src: Sprite2D) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = src.texture
	sp.hframes = src.hframes
	sp.vframes = src.vframes
	sp.frame = src.frame
	sp.flip_h = src.flip_h
	sp.flip_v = src.flip_v
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sp

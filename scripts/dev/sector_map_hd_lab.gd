extends Control

# DEV SANDBOX — HD sector-map prototype. NOT in the live game flow.
# Architecture (docs/sector_map_hd_scope_2026-06-02.md, refined 06-02b):
#   - The real sector_map_v3 is instanced INTO a 480×270 SubViewport, shown
#     upscaled 4× (nearest). The SubViewport keeps ONLY the chunky PIXEL OBJECTS:
#     the _draw background (fill + starfield + glitter) and the instanced
#     celestial bodies (planets / stars / asteroids).
#   - EVERYTHING ELSE is re-hosted into a 1920×1080 HD overlay at (marker × 4):
#     text labels, POI icons, boss nodes + rings, route lines, buttons, menus.
#     "Read-and-rehost": the instance generates names/positions/types as usual;
#     we walk it, hide its Label/Sprite2D-icon/Line2D-route/boss nodes, and
#     rebuild crisp HD copies from their text/region/points × 4.
#   - Hit-testing is HD-native: POI/boss hit regions are the map's data × 4,
#     tested against the HD mouse directly (no ÷4 indirection).
#
# Iterate here; the live port comes later (Roman: lock the look first).

const SceneTransition := preload("res://scripts/scene_transition.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const HdScreenLib := preload("res://scripts/ui/hd_screen.gd")
const SECTOR_MAP_SCENE := preload("res://scenes/sector_map_v3.tscn")
const ICON_STRIP := preload("res://graphics/ui/sector_icons.png")
const NODE_STRIP := preload("res://graphics/ui/sector_nodes.png")
# Higher-res glyphs (white-on-transparent) — crisper than the 32px strip tiles
# when rendered at HD. Keyed by the strip's icon index (see sector_map_v3:
# ICON_OUTPOST=0, ICON_COMBAT=2, ICON_BOSS=3, ICON_HAZARD=4, ICON_SIGNAL=5).
const HIRES_GLYPHS := {
	0: preload("res://graphics/sector/sector-station.png"),  # outpost
	2: preload("res://graphics/sector/sector-battle.png"),   # combat
	3: preload("res://graphics/sector/sector-boss.png"),     # boss
	4: preload("res://graphics/sector/sector-hazard.png"),   # hazard
	5: preload("res://graphics/sector/sector-unknown.png"),  # signal
}

const NATIVE := Vector2i(480, 270)
const SCALE := 4.0  # 1920 / 480
const COLOR_BOSS := Color(1.0, 0.30, 0.25, 1.0)
const COLOR_NODE_GREEN := Color(0.55, 1.0, 0.50, 1.0)  # matches sector_map_v3
# Boss marker sizing (tunable) — dot + icon enlarged to fill the progress ring.
const BOSS_RING_RADIUS := 52.0
const BOSS_DOT_PX := 92.0
const BOSS_ICON_PX := 64.0

var _hd_scope: HdViewportScope = null
var _map: Node2D = null            # the instanced live sector map (in SubViewport)
var _overlay: Control = null
var _gfx: Node2D = null            # HD route lines + boss rings live here
var _depart_btn: Button = null
var _readout: Label = null
var _hd_poi_hits: Array = []       # [{id, pos(HD), radius(HD)}]
var _hd_boss_hits: Array = []
# HD node icons that mirror the live map's hover behaviour:
# [{tr, center(HD), radius(HD), icon_rest, rest_tint, hover_tint}]
var _hover_icons: Array = []
var _boss_dots: Array = []          # [{pos(HD), color}] — for ring tinting


func _ready() -> void:
	_hd_scope = HdScreenLib.enter(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seed_sector_if_needed()
	_build_subviewport_map()
	_build_overlay()
	_rehost_to_hd()


# Only new_run() — NOT start_new_sector(). The instanced sector_map_v3._ready
# generates the sector itself via _ensure_sector_cache; pre-generating here too
# double-rolls the boss pool → modulo-by-zero in run_state._pick_row_bosses.
func _seed_sector_if_needed() -> void:
	var run := get_node_or_null("/root/Run")
	if run == null:
		return
	var cache: Dictionary = run.sector_map_cache
	var has_rows: bool = cache.has("rows") and not (cache.get("rows", []) as Array).is_empty()
	if not has_rows:
		run.new_run()
		run.bounty = 1200


func _build_subviewport_map() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var sub := SubViewport.new()
	sub.name = "MapViewport"
	sub.size = NATIVE
	sub.transparent_bg = false
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.gui_disable_input = true
	sub.handle_input_locally = false
	add_child(sub)

	_map = SECTOR_MAP_SCENE.instantiate()
	sub.add_child(_map)

	var inner_btns := _map.get_node_or_null("BottomBtnLayer")
	if inner_btns != null:
		inner_btns.visible = false

	var view := TextureRect.new()
	view.name = "MapView"
	view.texture = sub.get_texture()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "HdOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	var hdr := Label.new()
	hdr.text = "SECTOR MAP — HD LAB (dev)   ·   click a POI, then DEPART"
	UiTheme.style_label(hdr, UiTheme.LabelKind.CAPTION)
	hdr.position = Vector2(24, 12)
	_overlay.add_child(hdr)

	var back := UiTheme.make_button("‹ Dev Menu", true)
	back.position = Vector2(24, 40)
	back.pressed.connect(func(): SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn"))
	_overlay.add_child(back)

	_readout = Label.new()
	UiTheme.style_label(_readout, UiTheme.LabelKind.BODY)
	_readout.position = Vector2(24, 110)
	_readout.text = "selected: (none)"
	_overlay.add_child(_readout)

	var manage := UiTheme.make_button("MANAGE SHIP")
	_place_at_marker(manage, "manage_ship_button", Vector2(260, 64))
	manage.pressed.connect(_open_manage_ship)
	_overlay.add_child(manage)

	var options := UiTheme.make_button("OPTIONS")
	_place_at_marker(options, "options_button", Vector2(220, 64))
	options.pressed.connect(_open_options)
	_overlay.add_child(options)

	_depart_btn = UiTheme.make_button("DEPART")
	_place_at_marker(_depart_btn, "selected_node_label/depart_button", Vector2(220, 64))
	_depart_btn.disabled = true
	_depart_btn.pressed.connect(func(): _toast("Depart — selected '%s'" % _selected_id()))
	_overlay.add_child(_depart_btn)


func _place_at_marker(ctrl: Control, marker_path: String, size: Vector2) -> void:
	ctrl.custom_minimum_size = size
	ctrl.size = size
	ctrl.position = _marker_hd(marker_path) - size * 0.5


func _marker_hd(marker_path: String) -> Vector2:
	if _map != null and _map.has_node(marker_path):
		var m := _map.get_node(marker_path) as Node2D
		if m != null:
			return m.global_position * SCALE
	return Vector2(960, 1000)


# ---- Read-and-rehost: pull labels / icons / routes / bosses into HD ---------

func _rehost_to_hd() -> void:
	if _map == null:
		return
	await get_tree().process_frame  # let the instance's layout resolve sizes
	if not is_instance_valid(_map):
		return
	_gfx = Node2D.new()
	_gfx.name = "HdMapGfx"           # Node2D so Line2D rings/routes draw in canvas
	_overlay.add_child(_gfx)
	_walk_rehost(_map)               # labels, routes, boss dots (NODE_STRIP)
	_rehost_hover_icons()            # POI + boss icons (ICON_STRIP) via _planet_hovers
	_rehost_boss_rings()
	_build_hd_hit_regions()


func _walk_rehost(node: Node) -> void:
	for child in node.get_children():
		if child is Label:
			_rehost_label(child as Label)
		elif child is Sprite2D and _is_node_strip(child as Sprite2D):
			_rehost_boss_dot(child as Sprite2D)
		# Routes (Line2D) are intentionally NOT rehosted — they stay in the
		# SubViewport so they render BEHIND the planets/stars (an HD overlay
		# line would draw over the whole composited map). Chunky thick bands
		# read fine.
		_walk_rehost(child)


# Boss "dot" marker sprites use NODE_STRIP (the POI/boss ICONS use ICON_STRIP and
# are handled via _planet_hovers, which carries their hover/tint/alpha state).
func _is_node_strip(s: Sprite2D) -> bool:
	var t = s.texture
	return t is AtlasTexture and t.atlas == NODE_STRIP


func _rehost_label(orig: Label) -> void:
	if not orig.visible or orig.text == "":
		return
	var hd := Label.new()
	hd.text = orig.text
	hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Conform to the UI font scale: the top-center sector header reads as a
	# HEADER; everything else (POI / star / boss / status) as BODY.
	var kind := UiTheme.LabelKind.HEADER if orig.global_position.y < 30.0 else UiTheme.LabelKind.BODY
	UiTheme.style_label(hd, kind)
	if orig.label_settings != null:
		hd.add_theme_color_override("font_color", orig.label_settings.font_color)
	# Center the (larger) HD text on the original's visual centre via a wide
	# centered box, so longer HD text doesn't drift off the anchor.
	var c := (orig.global_position + orig.size * 0.5) * SCALE
	var box := Vector2(700, 52)
	hd.custom_minimum_size = box
	hd.size = box
	hd.position = c - box * 0.5
	_overlay.add_child(hd)
	orig.visible = false


# Build an HD TextureRect centred on a 480-space point × 4, at the given square
# footprint. `smooth` = linear filtering (for the hi-res glyphs); else nearest
# (for the pixel-strip tiles).
func _hd_icon(tex: Texture2D, footprint: float, center480: Vector2, smooth: bool) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if smooth else CanvasItem.TEXTURE_FILTER_NEAREST
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# IGNORE_SIZE so the rect's footprint wins — otherwise a 512px hi-res glyph
	# uses its native size as the min and renders huge.
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.custom_minimum_size = Vector2(footprint, footprint)
	tr.size = Vector2(footprint, footprint)
	tr.position = center480 * SCALE - Vector2(footprint, footprint) * 0.5
	return tr


func _atlas_copy(src: AtlasTexture) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = src.atlas
	t.region = src.region
	return t


# Boss "dot" markers (NODE_STRIP): static, colored by lock state (green
# available / red locked / dim-green defeated). Preserve the original modulate.
func _rehost_boss_dot(orig: Sprite2D) -> void:
	if not orig.visible:
		return
	# The boss dot is the NODE_STRIP circle — no hi-res version, keep it crisp-
	# nearest. Enlarged to better fill the progress ring.
	var tr := _hd_icon(_atlas_copy(orig.texture as AtlasTexture), BOSS_DOT_PX, orig.global_position, false)
	tr.modulate = orig.modulate
	_overlay.add_child(tr)
	_boss_dots.append({"pos": orig.global_position * SCALE, "color": orig.modulate})
	orig.visible = false


# POI + boss ICONS come from _planet_hovers, which carries each one's hover
# behaviour. Rebuild them HD and replicate the live rest/hover tint + alpha
# (driven in _process): uncompleted POIs rest invisible (alpha 0) and reveal
# green on hover; completed POIs rest soft green; boss icons stay visible.
func _rehost_hover_icons() -> void:
	var hovers = _map.get("_planet_hovers")
	if hovers == null:
		return
	for e in hovers:
		var icon = e.get("icon")
		if icon == null or not (icon is Sprite2D) or not (icon.texture is AtlasTexture):
			continue
		var center480: Vector2 = e.get("center", Vector2.ZERO)
		# Prefer the higher-res glyph (keyed by the strip icon index); fall back
		# to the 32px strip tile. White-on-transparent, so modulate still tints it.
		var src := icon.texture as AtlasTexture
		var idx := int(round(src.region.position.x / 32.0))
		# Boss icon (index 3) enlarged to fill the ring; POIs keep their footprint.
		var footprint := BOSS_ICON_PX if idx == 3 else 32.0 * (icon as Sprite2D).scale.x * SCALE
		var use_hires: bool = HIRES_GLYPHS.has(idx)
		var tex: Texture2D = HIRES_GLYPHS[idx] if use_hires else _atlas_copy(src)
		var tr := _hd_icon(tex, footprint, center480, use_hires)
		var rest_tint: Color = e.get("rest_tint", Color.WHITE)
		var icon_rest: float = float(e.get("icon_rest", 0.0))
		tr.modulate = Color(rest_tint.r, rest_tint.g, rest_tint.b, icon_rest)
		_overlay.add_child(tr)
		_hover_icons.append({
			"tr": tr,
			"center": center480 * SCALE,
			"radius": float(e.get("radius", 14.0)) * SCALE,
			"icon_rest": icon_rest,
			"rest_tint": rest_tint,
			"hover_tint": e.get("hover_tint", COLOR_NODE_GREEN),
		})
		(icon as Sprite2D).visible = false  # hide the chunky original


# Mirror the live map's hover fade (sector_map_v3._process): lerp each icon
# toward hover_tint @ 0.9 when the HD mouse is within its radius, else
# rest_tint @ icon_rest.
func _process(delta: float) -> void:
	if _hover_icons.is_empty():
		return
	var m := get_global_mouse_position()
	for h in _hover_icons:
		var hovered: bool = m.distance_to(h.center) <= float(h.radius)
		var tgt: Color = h.hover_tint if hovered else h.rest_tint
		tgt.a = 0.9 if hovered else float(h.icon_rest)
		h.tr.modulate = (h.tr.modulate as Color).lerp(tgt, delta * 8.0)


func _rehost_boss_rings() -> void:
	# Hide the inner ring node, then draw crisp HD rings at each boss dot,
	# tinted to match the dot's lock-state color (green available / red locked).
	var ringnode = _map.get("_boss_ring_node")
	if ringnode != null and is_instance_valid(ringnode):
		ringnode.visible = false
	for d in _boss_dots:
		var c: Color = d.color
		_add_hd_ring(d.pos, BOSS_RING_RADIUS, Color(c.r, c.g, c.b, 0.85))


func _add_hd_ring(center: Vector2, radius: float, color: Color) -> void:
	var ring := Line2D.new()
	var pts := PackedVector2Array()
	var segs := 44
	for i in range(segs + 1):
		var a := TAU * float(i) / float(segs)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	ring.points = pts
	ring.width = 3.0
	ring.default_color = color
	_gfx.add_child(ring)


func _build_hd_hit_regions() -> void:
	_hd_poi_hits.clear()
	_hd_boss_hits.clear()
	var pois = _map.get("_poi_hits")
	if pois != null:
		for hit in pois:
			_hd_poi_hits.append({"id": hit.id, "pos": (hit.pos as Vector2) * SCALE, "radius": float(hit.radius) * SCALE})
	var bosses = _map.get("_boss_entries")
	if bosses != null:
		for b in bosses:
			_hd_boss_hits.append({"id": b.id, "pos": (b.pos as Vector2) * SCALE, "radius": 16.0 * SCALE})


# ---- Input (HD-native) ------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_open_options()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var m := get_global_mouse_position()
		for hit in _hd_poi_hits:
			if m.distance_to(hit.pos) <= float(hit.radius):
				if _map.has_method("_on_poi_selected"):
					_map._on_poi_selected(String(hit.id))
				_after_select()
				return
		for b in _hd_boss_hits:
			if m.distance_to(b.pos) <= float(b.radius):
				if _map.has_method("_on_boss_selected"):
					_map._on_boss_selected(String(b.id))
				_after_select()
				return


func _after_select() -> void:
	var id := _selected_id()
	_depart_btn.disabled = id == ""
	_readout.text = "selected: %s" % (id if id != "" else "(none)")


func _selected_id() -> String:
	if _map == null:
		return ""
	var sid = _map.get("_selected_node_id")
	return String(sid) if sid != null else ""


func _open_manage_ship() -> void:
	# Return here (the lab) when Done is pressed; in the live game the sector map
	# sets this to itself.
	var run := get_node_or_null("/root/Run")
	if run != null:
		run.set_meta("manage_ship_return", "res://scenes/dev/sector_map_hd_lab.tscn")
	SceneTransition.change_scene(get_tree(), "res://scenes/manage_ship.tscn")


func _open_options() -> void:
	var OptionsOverlay := load("res://scripts/ui/options_overlay.gd")
	if OptionsOverlay:
		OptionsOverlay.open(self)


var _toast_lbl: Label = null
func _toast(text: String) -> void:
	if _toast_lbl == null:
		_toast_lbl = Label.new()
		UiTheme.style_label(_toast_lbl, UiTheme.LabelKind.HEADER)
		_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_toast_lbl.position = Vector2(-400, 150)
		_toast_lbl.size = Vector2(800, 40)
		_overlay.add_child(_toast_lbl)
	_toast_lbl.text = text
	_toast_lbl.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(_toast_lbl, "modulate:a", 0.0, 0.5)

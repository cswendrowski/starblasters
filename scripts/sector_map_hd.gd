extends Control

# LIVE HD sector map host. Ported from the approved prototype
# scripts/dev/sector_map_hd_lab.gd (see docs/sector_map_hd_PORT_HANDOFF.md).
#
# Architecture: the real sector_map_v3 is instanced INTO a 480×270 SubViewport
# (in EMBEDDED mode), shown upscaled 4× (nearest). The SubViewport keeps ONLY
# the chunky PIXEL OBJECTS: the _draw background (fill + starfield + glitter) and
# the instanced celestial bodies (planets / stars / asteroids) + the route
# Line2Ds (they must render BEHIND the planets — an HD line would draw over them).
# EVERYTHING ELSE is re-hosted into a 1920×1080 HD overlay at (marker × 4):
# text labels, POI icons, boss dots + rings, buttons, menus. Hit-testing is
# HD-native (POI/boss hit regions = the map's data × 4, vs the HD mouse).
#
# This host owns ALL chrome + input; the embedded map exposes its data/selection
# API (_poi_hits / _boss_entries / _on_poi_selected / _on_boss_selected /
# _on_depart_pressed) and runs its own _ready side-effects (sector gen, hull
# regen, save, music) exactly once.

const SceneTransition := preload("res://scripts/scene_transition.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const HdScreenLib := preload("res://scripts/ui/hd_screen.gd")
const SectorNode := preload("res://scripts/sector_node.gd")
const SECTOR_MAP_SCENE := preload("res://scenes/sector_map_v3.tscn")
const MANAGE_SHIP_SCENE := "res://scenes/manage_ship.tscn"
const OUTPOST_SCENE := "res://scenes/outpost.tscn"
const SELF_SCENE := "res://scenes/sector_map_hd.tscn"
const NODE_STRIP := preload("res://graphics/ui/sector_nodes.png")
# Higher-res glyphs (white-on-transparent) — crisper than the 32px strip tiles
# at HD. Keyed by the strip's icon index (sector_map_v3: ICON_OUTPOST=0,
# ICON_COMBAT=2, ICON_BOSS=3, ICON_HAZARD=4, ICON_SIGNAL=5).
const HIRES_GLYPHS := {
	0: preload("res://graphics/sector/sector-station.png"),  # outpost
	2: preload("res://graphics/sector/sector-battle.png"),   # combat
	3: preload("res://graphics/sector/sector-boss.png"),     # boss
	4: preload("res://graphics/sector/sector-hazard.png"),   # hazard
	5: preload("res://graphics/sector/sector-unknown.png"),  # signal
}

const NATIVE := Vector2i(480, 270)
const SCALE := 4.0  # 1920 / 480
const COLOR_NODE_GREEN := Color(0.55, 1.0, 0.50, 1.0)  # matches sector_map_v3
const COLOR_SELECTED := Color(0.75, 1.0, 0.75, 1.0)
const COLOR_WARN := Color(1.0, 0.40, 0.35, 1.0)
# Boss marker sizing (tunable) — dot + icon enlarged to fill the progress ring.
const BOSS_RING_RADIUS := 52.0
const BOSS_DOT_PX := 92.0
const BOSS_ICON_PX := 64.0

var _hd_scope: HdViewportScope = null
var _map: Node2D = null            # the instanced live sector map (in SubViewport)
var _overlay: Control = null
var _gfx: Node2D = null            # HD route lines + boss rings live here
var _depart_btn: Button = null
var _sel_label: Label = null       # HD copy of the selected-node designation
var _warn_label: Label = null      # red "no bounty to spend" heads-up
var _hd_poi_hits: Array = []       # [{id, pos(HD), radius(HD)}]
var _hd_boss_hits: Array = []
# HD node icons that mirror the live map's hover behaviour:
# [{tr, center(HD), radius(HD), icon_rest, rest_tint, hover_tint}]
var _hover_icons: Array = []
var _boss_dots: Array = []          # [{pos(HD), color}] — for ring tinting
# Selection feedback: a green ring at the chosen node + its icon kept lit. On a
# new selection the old ring cross-fades out and the old icon falls back to its
# rest alpha (invisible for an uncompleted POI).
var _selected_ring: Line2D = null
var _selected_icon_tr: TextureRect = null  # the kept-lit icon (identity-compared)
var _selected_visual_id: String = ""


func _ready() -> void:
	_hd_scope = HdScreenLib.enter(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The root must be transparent to the mouse so empty-space clicks fall
	# through to _unhandled_input (HD-native POI/boss hit-testing). A default
	# STOP root would swallow every click that isn't on a button. Buttons keep
	# their own STOP filter, so they still receive clicks.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_subviewport_map()
	_build_overlay()
	_rehost_to_hd()


func _build_subviewport_map() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never swallow node clicks
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
	# Flag BEFORE add_child so the embedded map's _ready skips its own buttons,
	# clear-color tint, and _unhandled_input transitions (host owns all chrome).
	_map.set("_embedded", true)
	sub.add_child(_map)

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

	var visit := UiTheme.make_button("VISIT OUTPOST")
	_place_at_marker(visit, "visit_outpost_button", Vector2(260, 64))
	visit.pressed.connect(_open_outpost)
	_overlay.add_child(visit)

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
	_depart_btn.pressed.connect(_on_depart)
	_overlay.add_child(_depart_btn)

	# Selected-node designation (HD copy of the chunky bottom-center label).
	_sel_label = Label.new()
	UiTheme.style_label(_sel_label, UiTheme.LabelKind.BODY)
	_sel_label.add_theme_color_override("font_color", COLOR_SELECTED)
	_sel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sel_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sel_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_label_at_marker(_sel_label, "selected_node_label", Vector2(0, 0))
	_sel_label.text = ""
	_overlay.add_child(_sel_label)

	# No-bounty heads-up — a red line over the selected label (shown only when an
	# outpost is selected with 0 bounty). Optional `no_bounty_warning` marker can
	# be added later for precise placement; until then it sits just above the
	# selected-node label.
	_warn_label = Label.new()
	UiTheme.style_label(_warn_label, UiTheme.LabelKind.BODY)
	_warn_label.add_theme_color_override("font_color", COLOR_WARN)
	_warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_warn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var has_warn_marker: bool = _map != null and _map.has_node("no_bounty_warning")
	var warn_anchor := "no_bounty_warning" if has_warn_marker else "selected_node_label"
	var warn_off := Vector2.ZERO if has_warn_marker else Vector2(0, -16)
	_center_label_at_marker(_warn_label, warn_anchor, warn_off)
	_warn_label.text = "WARNING: NO BOUNTY TO SPEND"
	_warn_label.visible = false
	_overlay.add_child(_warn_label)


func _place_at_marker(ctrl: Control, marker_path: String, size: Vector2) -> void:
	ctrl.custom_minimum_size = size
	ctrl.size = size
	ctrl.position = _marker_hd(marker_path) - size * 0.5


# Center a (wide, fixed-box) label on a 480-space marker × 4 with an optional
# 480-space offset, so longer HD text stays centered on the anchor.
func _center_label_at_marker(lbl: Label, marker_path: String, offset480: Vector2) -> void:
	var box := Vector2(760, 52)
	lbl.custom_minimum_size = box
	lbl.size = box
	lbl.position = _marker_hd(marker_path) + offset480 * SCALE - box * 0.5


func _marker_hd(marker_path: String) -> Vector2:
	if _map != null and _map.has_node(marker_path):
		var m := _map.get_node(marker_path) as Node2D
		if m != null:
			return m.global_position * SCALE
	return Vector2(960, 1000)


# ---- Read-and-rehost: pull labels / icons / bosses into HD -------------------

func _rehost_to_hd() -> void:
	if _map == null:
		return
	await get_tree().process_frame  # let the instance's layout resolve sizes
	if not is_instance_valid(_map):
		return
	_gfx = Node2D.new()
	_gfx.name = "HdMapGfx"           # Node2D so Line2D rings/routes draw in canvas
	_overlay.add_child(_gfx)
	_walk_rehost(_map)               # labels, boss dots (NODE_STRIP)
	_rehost_hover_icons()            # POI + boss icons (ICON_STRIP) via _planet_hovers
	_rehost_boss_rings()
	_build_hd_hit_regions()
	# Hide the chunky in-SubViewport selected-node label; we mirror it in HD.
	var chunky_sel = _map.get("_selected_node_lbl")
	if chunky_sel != null and is_instance_valid(chunky_sel):
		(chunky_sel as Label).visible = false


func _walk_rehost(node: Node) -> void:
	for child in node.get_children():
		if child is Label:
			_rehost_label(child as Label)
		elif child is Sprite2D and _is_node_strip(child as Sprite2D):
			_rehost_boss_dot(child as Sprite2D)
		# Routes (Line2D) are intentionally NOT rehosted — they stay in the
		# SubViewport so they render BEHIND the planets/stars (an HD overlay
		# line would draw over the whole composited map).
		_walk_rehost(child)


# Boss "dot" marker sprites use NODE_STRIP (the POI/boss ICONS use ICON_STRIP and
# are handled via _planet_hovers, which carries their hover/tint/alpha state).
func _is_node_strip(s: Sprite2D) -> bool:
	var t = s.texture
	return t is AtlasTexture and t.atlas == NODE_STRIP


func _rehost_label(orig: Label) -> void:
	if not orig.visible or orig.text == "":
		return
	# The chunky selected-node label is rebuilt as an HD copy by us; skip it here.
	if _map != null and orig == _map.get("_selected_node_lbl"):
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
		# The selected node's icon stays lit (treated as permanently hovered) so
		# the player can see what they've chosen; everything else fades on hover.
		var is_selected: bool = h.tr == _selected_icon_tr
		var hovered: bool = is_selected or m.distance_to(h.center) <= float(h.radius)
		var tgt: Color = h.hover_tint if hovered else h.rest_tint
		tgt.a = 0.9 if hovered else float(h.icon_rest)
		h.tr.modulate = (h.tr.modulate as Color).lerp(tgt, delta * 8.0)


func _rehost_boss_rings() -> void:
	# Hide the inner V3 ring node, then draw crisp HD PROGRESS rings at each boss.
	# Mirrors sector_map_v3._draw_boss_rings (~:1187): a filled arc from 12-o'clock
	# spanning done/total of the row's POIs, plus a dim remainder. Iterates
	# _boss_entries (carries row_idx + pos + lock state) rather than _boss_dots so
	# each ring is matched to the correct row's completion count.
	var ringnode = _map.get("_boss_ring_node")
	if ringnode != null and is_instance_valid(ringnode):
		ringnode.visible = false
	var run = get_node("/root/Run")
	var rows: Array = run.sector_map_cache.get("rows", [])
	var entries = _map.get("_boss_entries")
	if entries == null:
		return
	for b in entries:
		var row_idx: int = int(b.get("row_idx", -1))
		if row_idx < 0 or row_idx >= rows.size():
			continue
		var center: Vector2 = (b.get("pos", Vector2.ZERO) as Vector2) * SCALE
		# done/total — computed exactly like _draw_boss_rings (:1200-1208).
		var pois: Array = rows[row_idx].pois
		var total: int = pois.size()
		if total <= 0:
			continue
		var done: int = 0
		for poi in pois:
			if poi.completed:
				done += 1
		# Tint: green when the boss is available (all POIs done) / defeated, red
		# while locked — matches the V3 boss-dot lock-state coloring.
		var available: bool = bool(b.get("unlocked", false)) or bool(b.get("defeated", false))
		var base: Color = COLOR_NODE_GREEN if available else COLOR_WARN
		var filled := Color(base.r, base.g, base.b, 0.85)
		var unfilled := Color(base.r, base.g, base.b, 0.22)
		_add_hd_progress_ring(center, BOSS_RING_RADIUS, float(done) / float(total), filled, unfilled)


func _add_hd_ring(center: Vector2, radius: float, color: Color) -> void:
	_gfx.add_child(_make_ring(center, radius, color))


# Parent a two-arc progress ring: a filled arc from 12-o'clock spanning
# `fill_frac` of the circle + a dim remainder. fill_frac in [0,1].
func _add_hd_progress_ring(center: Vector2, radius: float, fill_frac: float, filled: Color, unfilled: Color) -> void:
	var f: float = clampf(fill_frac, 0.0, 1.0)
	var start_angle: float = -PI * 0.5            # 12-o'clock (matches V3 :1212)
	var fill_end: float = start_angle + f * TAU
	if f > 0.0:
		_gfx.add_child(_make_arc(center, radius, start_angle, fill_end, filled))
	if f < 1.0:
		_gfx.add_child(_make_arc(center, radius, fill_end, start_angle + TAU, unfilled))


# Build (but don't parent) a Line2D arc from `a0` to `a1` (radians) at an HD point.
func _make_arc(center: Vector2, radius: float, a0: float, a1: float, color: Color) -> Line2D:
	var arc := Line2D.new()
	var pts := PackedVector2Array()
	# Scale segment count with arc length so partial arcs stay smooth (44 segs / full circle).
	var span: float = absf(a1 - a0)
	var segs: int = maxi(2, int(ceil(44.0 * span / TAU)))
	for i in range(segs + 1):
		var a: float = lerpf(a0, a1, float(i) / float(segs))
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	arc.points = pts
	arc.width = 3.0
	arc.default_color = color
	return arc


# Build (but don't parent) a circular Line2D ring centered at an HD point.
func _make_ring(center: Vector2, radius: float, color: Color) -> Line2D:
	var ring := Line2D.new()
	var pts := PackedVector2Array()
	var segs := 44
	for i in range(segs + 1):
		var a := TAU * float(i) / float(segs)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	ring.points = pts
	ring.width = 3.0
	ring.default_color = color
	return ring


# Paint selection feedback at the chosen node: a green ring (sized to match the
# boss progress rings) that fades in, plus keeping the node's icon lit. A new
# selection cross-fades the old ring out and releases the old icon back to its
# rest alpha. `hd_pos` is the node center in HD space.
func _select_visual(id: String, hd_pos: Vector2) -> void:
	if id == _selected_visual_id:
		return  # re-click of the already-selected node — leave its ring as-is
	_selected_visual_id = id
	# Cross-fade the previous ring out.
	if _selected_ring != null and is_instance_valid(_selected_ring):
		_fade_and_free_ring(_selected_ring)
	# New ring, faded in from transparent.
	var ring := _make_ring(hd_pos, BOSS_RING_RADIUS, Color(COLOR_NODE_GREEN.r, COLOR_NODE_GREEN.g, COLOR_NODE_GREEN.b, 0.9))
	ring.modulate.a = 0.0
	_gfx.add_child(ring)
	_selected_ring = ring
	var tw := ring.create_tween()
	tw.tween_property(ring, "modulate:a", 1.0, 0.2)
	# Keep this node's icon lit (matched by HD center). The old icon, no longer
	# the selected one, drifts back to its rest alpha in _process.
	_selected_icon_tr = null
	for h in _hover_icons:
		if (h.center as Vector2).distance_to(hd_pos) < 2.0:
			_selected_icon_tr = h.tr
			break


func _fade_and_free_ring(ring: Line2D) -> void:
	var tw := ring.create_tween()
	tw.tween_property(ring, "modulate:a", 0.0, 0.2)
	tw.tween_callback(ring.queue_free)


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
				# Only paint the selection ring if the map actually took it (the
				# node wasn't already completed); _selected_node_id reflects that.
				if _selected_id() == String(hit.id):
					_select_visual(String(hit.id), hit.pos)
				return
		for b in _hd_boss_hits:
			if m.distance_to(b.pos) <= float(b.radius):
				if _map.has_method("_on_boss_selected"):
					_map._on_boss_selected(String(b.id))
				_after_select()
				if _selected_id() == String(b.id):
					_select_visual(String(b.id), b.pos)
				return


func _after_select() -> void:
	var id := _selected_id()
	_depart_btn.disabled = id == ""
	# Mirror the chunky designation label the embedded map just set.
	var chunky_sel = _map.get("_selected_node_lbl")
	if chunky_sel != null and is_instance_valid(chunky_sel):
		_sel_label.text = String((chunky_sel as Label).text)
	# No-bounty heads-up: only when an outpost is selected with 0 bounty.
	_warn_label.visible = _is_no_bounty_outpost(id)


func _is_no_bounty_outpost(id: String) -> bool:
	if id == "":
		return false
	var run := get_node_or_null("/root/Run")
	if run == null:
		return false
	var node = run.find_sector_node(id)
	if node == null:
		return false
	if int(node.get("node_type")) != int(SectorNode.NodeType.OUTPOST):
		return false
	return int(run.bounty) <= 0


func _selected_id() -> String:
	if _map == null:
		return ""
	var sid = _map.get("_selected_node_id")
	return String(sid) if sid != null else ""


func _on_depart() -> void:
	# The embedded map owns the real routing (combat / outpost / signal / hazard
	# / boss) AND the SceneTransition. Our HD scope is a child of this host and
	# frees on the scene swap (under the fade's black cover), restoring native
	# content_scale for native combat — the same implicit teardown manage_ship
	# relies on.
	if _map != null and _map.has_method("_on_depart_pressed"):
		_map._on_depart_pressed()


func _open_manage_ship() -> void:
	var run := get_node_or_null("/root/Run")
	if run != null:
		run.set_meta("manage_ship_return", SELF_SCENE)
	SceneTransition.change_scene(get_tree(), MANAGE_SHIP_SCENE)


# Visit the persistent outpost hub (Roman 2026-06-08). The outpost reads only Run
# stats + its persisted stock/charges; it returns to the sector map on Leave (via
# SectorMapRoute, already SELF_SCENE). No node-state is set — it's not a POI.
func _open_outpost() -> void:
	SceneTransition.change_scene(get_tree(), OUTPOST_SCENE)


func _open_options() -> void:
	var OptionsOverlay := load("res://scripts/ui/options_overlay.gd")
	if OptionsOverlay:
		# The sector map is the one screen with no separate pause menu, so its
		# Options is where "Exit to Main Menu" belongs (leaving here is safe —
		# the run is saved on every map visit; Resume Patrol drops back here).
		OptionsOverlay.open(self, true)

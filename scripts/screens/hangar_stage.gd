extends Node2D

# Authorable hangar stage (Roman 2026-06-21) — the SHARED dock stage as a SCENE you tune in the
# editor (scenes/hangar_stage.tscn): the plate art, runway light markers, ambient fill lights, Marker2D
# slots (pad / lifter-idle / ship-park / crate zones). Graduated from hangar_plate.gd.
#
# Both outpost_arrival + patrol_start instance it into their native 480×270 SubViewport, position/
# animate the node (the plate is CENTRED on this node's origin), read the slot markers, and drive the
# dynamic layer (the cinematic, the parked/landing ships, the lifter) in code. The behaviour a scene
# can't hold lives HERE: the runway pulse (this `_process`) + the marker API. `scene_dim` is a VALUE
# the screen applies to the SubViewportContainer (the HD wrapper OUTSIDE this scene) — a scene can't
# dim its own viewport output.
#
# AUTHORING: open scenes/hangar_stage.tscn. Move the RunwayMarkers (12 Marker2D) onto the art's amber
# squares; the pixel + light are generated on them at runtime (pulse phase = each marker's Y). Place
# the Slots markers for the screens to read. Tune the exports in the inspector.

const PointLightFx = preload("res://scripts/effects/point_light_fx.gd")
const HangarClutter = preload("res://scripts/screens/hangar_clutter.gd")

@export_group("Runway lights")
@export var runway_speed: float = 0.9
@export var runway_pixel_size: float = 2.0   # 2px amber squares
@export var runway_dark: Color = Color(0.15, 0.08, 0.0)    # off (additive → faint)
@export var runway_lit: Color = Color(1.0, 0.66, 0.12)     # on  (additive → glow)
@export var runway_light_color: Color = Color(1.0, 0.70, 0.16)
@export var runway_light_energy: float = 0.7
@export var runway_light_scale: float = 0.12
@export_group("Lighting")
@export var scene_dim: float = 0.6     # bay dim — drives the in-scene CanvasModulate (authored value wins on load)
@export_group("Clutter")
@export var clutter_amount: int = 8    # how many ClutterZones get a pile (default; screen can override)

const RUNWAY_K := TAU
const LIGHT_TEX_SIZE := 64

var _light_tex: Texture2D = null
var _cmod: CanvasModulate = null    # the in-scene bay dim (authored; tuned via set_scene_dim)
var _pixels: Array = []
var _lights: Array = []
var _v: Array = []
var _t: float = 0.0
var _clutter: Node2D = null
var _key_light: PointLight2D = null   # lazily-created central key light (light_shadow_fx "key" mode)


func _ready() -> void:
	_light_tex = PointLightFx.make_texture(LIGHT_TEX_SIZE)
	_cmod = get_node_or_null("CanvasModulate")
	if _cmod != null:
		scene_dim = _cmod.color.r   # adopt the authored CanvasModulate dim as the source of truth
	_build_runway()


# Generate a bright-amber ADDITIVE square + an amber point light on each RunwayMarkers Marker2D.
func _build_runway() -> void:
	var markers := _runway_markers()
	if markers.is_empty():
		return
	var ymin: float = markers[0].position.y
	var ymax: float = ymin
	for m in markers:
		ymin = minf(ymin, m.position.y)
		ymax = maxf(ymax, m.position.y)
	var span: float = maxf(ymax - ymin, 0.001)
	var s := runway_pixel_size / 2.0
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for m in markers:
		var pix := Polygon2D.new()
		pix.polygon = PackedVector2Array([Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)])
		pix.color = runway_dark
		pix.material = add_mat
		m.add_child(pix)
		_pixels.append(pix)
		var lt := PointLightFx.make(Vector2.ZERO, runway_light_color, runway_light_scale, _light_tex)
		m.add_child(lt)
		_lights.append(lt)
		_v.append((m.position.y - ymin) / span)   # 0 (top) .. 1 (bottom) for the travelling pulse


func _runway_markers() -> Array:
	var out := []
	var n := get_node_or_null("RunwayMarkers")
	if n != null:
		for c in n.get_children():
			if c is Marker2D:
				out.append(c)
	return out


# Pulse the runway bottom→top: a travelling amber band (sharpened by pow) over dim amber.
func _process(delta: float) -> void:
	if _pixels.is_empty():
		return
	_t += delta
	for i in _pixels.size():
		var s: float = 0.5 + 0.5 * sin(_t * runway_speed + float(_v[i]) * RUNWAY_K)
		var lit: float = pow(s, 2.5)
		var pix = _pixels[i]
		if is_instance_valid(pix):
			pix.color = runway_dark.lerp(runway_lit, lit)
		var lt = _lights[i]
		if is_instance_valid(lt):
			lt.energy = lit * runway_light_energy


# (Ambient fill lights are fully authored under FillLights in the editor — position/color/energy/
# texture — so the script no longer touches them.)


# ---- API (read by the screens) -------------------------------------------

func set_runway_speed(v: float) -> void:
	runway_speed = v


func get_scene_dim() -> float:
	return scene_dim


func set_scene_dim(v: float) -> void:
	scene_dim = v
	if _cmod != null and is_instance_valid(_cmod):
		_cmod.color = Color(v, v, v, 1.0)


func plate_size() -> Vector2:
	var p := get_node_or_null("Plate")
	if p != null and p is Sprite2D and (p as Sprite2D).texture != null:
		return (p as Sprite2D).texture.get_size()
	return Vector2(218, 270)


# A slot marker's LOCAL position (relative to this node = plate centre). The screen adds its own
# placement offset to convert to viewport/native coords.
func slot(name: String) -> Vector2:
	var n := get_node_or_null("Slots/" + name)
	return (n as Node2D).position if n != null and n is Node2D else Vector2.ZERO


# All Slots markers whose name starts with `prefix` (e.g. "Park", "Crate"), in name order, as LOCAL
# positions.
func slots_prefixed(prefix: String) -> Array:
	var out := []
	var s := get_node_or_null("Slots")
	if s == null:
		return out
	var matches := []
	for c in s.get_children():
		if c is Node2D and String(c.name).begins_with(prefix):
			matches.append(c)
	matches.sort_custom(func(a, b): return String(a.name) < String(b.name))
	for c in matches:
		out.append((c as Node2D).position)
	return out


# ---- Clutter (screen-driven; seed controls re-roll-on-refresh vs stable-on-revisit) ---------------

# Scatter randomized crate piles at a random subset of the authored ClutterZones. Re-callable (clears
# the previous clutter first). `amount` < 0 → use the `clutter_amount` export (a screen can lower it,
# e.g. as the shop has more to store). Children of this node, so the clutter rides the plate.
func scatter_clutter(seed_value: int, amount: int = -1, make_shadows: bool = true) -> void:
	if _clutter != null and is_instance_valid(_clutter):
		_clutter.queue_free()
	_clutter = Node2D.new()
	_clutter.name = "Clutter"
	add_child(_clutter)
	var n: int = amount if amount >= 0 else clutter_amount
	HangarClutter.populate(_clutter, _zone_positions("ClutterZones"), seed_value, n, -5, -6, 1, 4, 0.0, make_shadows)


# HOOK: extra crate piles flanking the pad (FlankL/FlankR markers), `per_side` crates each. Production
# scales `per_side` by the parked ship's parts/ammo/weapons; for now the caller passes a default.
# `make_shadows` mirrors scatter_clutter (off when light_shadow_fx projects the shadows).
func flank_pile(seed_value: int, per_side: int, make_shadows: bool = true) -> void:
	if per_side <= 0:
		return
	if _clutter == null or not is_instance_valid(_clutter):
		_clutter = Node2D.new()
		_clutter.name = "Clutter"
		add_child(_clutter)
	var z := _zone_positions_named(["Slots/FlankL", "Slots/FlankR"])
	HangarClutter.populate(_clutter, z, seed_value ^ 0x5A5A5A, z.size(), -5, -6, per_side, per_side + 1, 0.0, make_shadows)


# ---- Light-derived shadow prototype hooks (light_shadow_fx) ----------------------------------------

# The current clutter container (crate sprites), so a caller can register them as shadow casters.
func clutter_node() -> Node2D:
	return _clutter


# The authored 2×3 FillLights (PointLight2D) — the multi-shadow source set.
func fill_lights() -> Array:
	var out: Array = []
	var n := get_node_or_null("FillLights")
	if n != null:
		for c in n.get_children():
			if c is PointLight2D:
				out.append(c)
	return out


# Lazily-created central KEY light at the bay centre (stage origin). Off (energy 0) until a caller
# raises it; both lights the bay and acts as the single shadow source in the prototype's "key" mode.
func ensure_key_light() -> PointLight2D:
	if _key_light == null or not is_instance_valid(_key_light):
		var tex := PointLightFx.make_texture(256)
		# Upper-centre (not dead-centre) so shadows fall consistently DOWN — and the landed ship on the
		# pad isn't sitting on top of it (which would throw its shadow upward). Position only matters as
		# a shadow origin; it's kept at energy 0 (no illumination) by the screens.
		_key_light = PointLightFx.make(Vector2(0, -90), Color(0.85, 0.9, 1.0), 1.8, tex)
		_key_light.name = "KeyLight"
		add_child(_key_light)
	return _key_light


func _zone_positions(group: String) -> Array:
	var out := []
	var n := get_node_or_null(group)
	if n != null:
		for c in n.get_children():
			if c is Node2D:
				out.append((c as Node2D).position)
	return out


func _zone_positions_named(paths: Array) -> Array:
	var out := []
	for p in paths:
		var n := get_node_or_null(p)
		if n != null and n is Node2D:
			out.append((n as Node2D).position)
	return out

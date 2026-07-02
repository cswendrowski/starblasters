extends RefCounted

# Shared player-ship VISUAL builder (Roman 2026-06-24). One source of truth for how a player ship
# looks OUTSIDE gameplay — every menu (ship select, outpost, codex, loading, patrol start) builds its
# ship through this so the livery reads identically to the in-game ship, instead of each screen
# reconstructing the layers and diverging (flat modulate vs the real shader, etc.).
#
# Mirrors the gameplay scene's Ship/Body/Livery/GlowMask: body (full-bright) + a Livery child running
# the SAME screen-multiply `livery_color.gdshader` at the SAME 0.8 opacity (so the livery is the body
# shaded THROUGH the tint, never a flat fill) + an additive engine glow. The gameplay scenes stay the
# reference; this matches them. Reference impl this was factored from: patrol_start._build_ships.
#
# Build returns a Node2D ("ShipVisual") centered at its origin, native (16px) scale — the caller
# positions + scales it, and adds any scene-specific extras (drop shadow, engine markers, dimming).

const ShipCatalog = preload("res://scripts/strings/ship_catalog.gd")
const LiveryShader = preload("res://scenes/player/livery_color.gdshader")
const LIVERY_OPACITY := 0.8
const ENGINE_GLOW_COLOR := Color(0.0, 0.827, 1.0)   # #00d3ff — matches the in-game engine glowmask
const FRAME_NEUTRAL := 1                            # middle frame of the 3-frame bank strip


# Build the visual for `variant`, livery-tinted to `tint`. `glow_alpha` lights the additive engine
# glow (0 = unlit/parked, ~0.6–1.0 = lit). Layers: Body (z 0) + Livery child (z +1, screen-multiply)
# + Glow (z +1, additive). The livery material + glow sprite are exposed via meta for live retint /
# engine-glow animation (set_tint / get_glow).
static func build(variant: int, tint: Color, glow_alpha: float = 1.0) -> Node2D:
	var ship: Dictionary = ShipCatalog.get_ship(variant)
	var root := Node2D.new()
	root.name = "ShipVisual"

	var body := _sprite(String(ship["body"]))
	root.add_child(body)

	# Each ship needs its OWN back-buffer copy. The livery samples hint_screen_texture (the body
	# behind it), but Godot's AUTOMATIC copy only refreshes for the first screen-reading item drawn
	# per frame — so in a multi-ship layout (the ship-select card row) every ship after the first
	# samples a stale buffer that lacks its body → screen_tex is black → black livery. An explicit
	# BackBufferCopy drawn right after this body (and before its livery) forces a fresh capture so
	# each livery multiplies its own hull. (Single-ship menus work without it, but this is harmless.)
	var bbc := BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	body.add_child(bbc)

	var mat := make_livery_material(tint)
	var livery := _sprite(String(ship["livery"]))
	livery.material = mat
	body.add_child(livery)   # drawn AFTER the BackBufferCopy, so it samples its own body

	var glow := _sprite(String(ship["engine"]))
	glow.modulate = Color(ENGINE_GLOW_COLOR.r, ENGINE_GLOW_COLOR.g, ENGINE_GLOW_COLOR.b, glow_alpha)
	var gm := CanvasItemMaterial.new()
	gm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = gm
	root.add_child(glow)

	root.set_meta("livery_mat", mat)
	root.set_meta("glow", glow)
	root.set_meta("body", body)
	return root


# Dock-cinematic ship assembly (Roman 2026-07-02 refactor) — the shared body/livery/glow stack the
# outpost + patrol dock screens both hand-built. Builds a host Node2D containing: body (Sprite2D), a
# livery Sprite2D (screen-multiply material, WHITE modulate), an additive engine-glow Sprite2D tinted
# ENGINE_GLOW_COLOR, and one Marker2D per engine nozzle (named "Engine{i}"). Returns the host plus refs
# {body, livery, glow, markers} so each screen can apply its own extras (damage overlay, drop shadow,
# trail, point lights) and adjust draw order without diverging on the core layers.
#
# The two screens differ in a few structural details, parameterized here to preserve each EXACTLY:
#   `livery_under_body` — patrol parents the livery UNDER the body (child); outpost keeps it a sibling.
#   `body_z`            — patrol sets the body z_index to -2; outpost leaves it at 0.
#   `glow_alpha`        — patrol starts the glow at alpha 0 (parked/unlit); outpost at full color (lit).
# `data` is a ShipCatalog ship dict (its `body`/`livery`/`engine`/`engines` keys).
static func build_dock_ship(data: Dictionary, livery_color: Color, livery_under_body: bool = false, body_z: int = 0, glow_alpha: float = 1.0) -> Dictionary:
	var host := Node2D.new()

	var body := _dock_layer(String(data["body"]), Color.WHITE, false)
	if body_z != 0:
		body.z_index = body_z
	host.add_child(body)

	var livery := _dock_layer(String(data["livery"]), Color.WHITE, false)
	livery.material = make_livery_material(livery_color)
	if livery_under_body:
		body.add_child(livery)
	else:
		host.add_child(livery)

	var glow := _dock_layer(String(data["engine"]), ENGINE_GLOW_COLOR, true)
	glow.modulate.a = glow_alpha
	host.add_child(glow)

	var markers: Array = []
	for i in (data["engines"] as Array).size():
		var mk := Marker2D.new()
		mk.name = "Engine%d" % i
		mk.position = data["engines"][i]
		host.add_child(mk)
		markers.append(mk)

	return {"host": host, "body": body, "livery": livery, "glow": glow, "markers": markers}


# A dock ship sprite layer: frame-1 of the 3-frame bank, nearest filter, tint, optional additive blend.
static func _dock_layer(path: String, tint: Color, additive: bool) -> Sprite2D:
	var spr := _sprite(path)
	spr.modulate = tint
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		spr.material = m
	return spr


# The configured screen-multiply livery ShaderMaterial — the ONE place the livery look is defined
# (shader + 0.8 opacity). Scenes that build their own ship layers (the outpost / patrol cinematics,
# which carry damage overlays + dimming the plain builder tree doesn't) call this so their livery
# reads identically to build()'s. The livery Sprite2D must keep modulate=WHITE (the tint lives in
# the shader) and be drawn AFTER its body so the screen-multiply samples the body behind it.
static func make_livery_material(tint: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = LiveryShader
	mat.set_shader_parameter("tint_color", tint)
	mat.set_shader_parameter("opacity", LIVERY_OPACITY)
	mat.set_shader_parameter("fade", 1.0)
	return mat


# Live-retint an already-built visual (the ship-select swatch row, outpost recolor, etc.).
static func set_tint(visual: Node, tint: Color) -> void:
	if visual != null and is_instance_valid(visual) and visual.has_meta("livery_mat"):
		(visual.get_meta("livery_mat") as ShaderMaterial).set_shader_parameter("tint_color", tint)


# The additive engine-glow Sprite2D, for callers that animate its alpha (parked vs lit).
static func get_glow(visual: Node) -> Sprite2D:
	if visual != null and is_instance_valid(visual) and visual.has_meta("glow"):
		return visual.get_meta("glow") as Sprite2D
	return null


static func _sprite(path: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(path)
	s.hframes = 3
	s.frame = FRAME_NEUTRAL
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return s

extends Area2D

# Asteroid Stronghold (Roman 2026-07-13) — an INDESTRUCTIBLE drifting asteroid that carries
# destructible "building" enemies. The rock is terrain: it is NOT in the "enemies" group, so player
# bullets pass through it (they only hit the buildings, which ARE in "enemies"); it deals contact
# damage to the player from its own side (like scripts/enemies/asteroid.gd) and drifts off the bottom.
# Buildings ride the rock as static parented children (see stronghold_building_palette.gd); a killed
# building leaves an inert husk that rides off with the rock (enemy_core_building_turret.gd).
#
# Prefabs are authored in the Asteroid Stronghold editor (scripts/dev/asteroid_stronghold_editor.gd)
# and baked into scripts/levels/asteroid_strongholds.gd via Copy-GDScript. Consumption by the
# asteroid_field hazard is a DEFERRED follow-up — this scene just renders + runs a prefab via
# configure(). The rock-visual builder is static so the editor shares the exact near-layer look.

const Palette := preload("res://scripts/enemies/stronghold_building_palette.gd")
const ASTEROID_SCENE := "res://Planets/Asteroids/Asteroid.tscn"

# "Ground" altitude: the whole prefab (rock + buildings) sorts BELOW the play-area actors. Gameplay
# actors live in the default canvas at z_index 0; death VFX floor is z -4 (death_dust) / -3 (blasts);
# player bullets -1. -5 clears all of them, and the parallax backdrop sits on its own negative
# CanvasLayers (-10..-1) so a negative z here still renders above it. Child buildings inherit via
# z_as_relative (their own +1 overlay frames land at -4, still under the actors). Mirrors the boss
# under-layer pattern (physics_boss.gd UNDER_LAYER_Z), just deeper so it also clears explosions.
const GROUND_Z := -5

# Shadow band for a gameplay-scale foreground rock (full-size shadow, 8px offset) — matches Asteroid Lab.
const SHADOW_BAND := "near"

@export var drift_speed: float = 40.0
@export var damage_on_collide: int = 2

var _size: float = 120.0
var _visual: Node = null
var screensize: Vector2 = Vector2(480, 270)


func _ready() -> void:
	screensize = get_viewport_rect().size
	z_index = GROUND_Z
	area_entered.connect(_on_area_entered)


# Build a stronghold from a prefab dict:
#   { "asteroid": { seed, size, roundness, dither, tint:[r,g,b], drift_speed },
#     "buildings": [ { type, x, y }, ... ] }
func configure(prefab: Dictionary) -> void:
	var ast: Dictionary = prefab.get("asteroid", {})
	_size = float(ast.get("size", 120.0))
	drift_speed = float(ast.get("drift_speed", drift_speed))
	# Rock visual, centered on this Area2D's origin.
	_visual = build_rock_visual(self, ast)
	move_child(_visual, 0)   # keep the rock behind the buildings
	_apply_shadow(_visual)   # receive the asteroid drop-shadows if the combat rig is present
	# Contact hitbox ~ the rock's body.
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = _size * 0.45
	cs.shape = circle
	add_child(cs)
	# Buildings — static parented children at their authored offsets. They inherit the rock's ground z
	# (GROUND_Z, from the root) so ships/bullets fly over them; their DEATH VFX render foreground + at the
	# correct WORLD position because enemy_core_building_turret._fx_parent() routes the burst/debris to
	# the current scene (origin, z 0) rather than this holder — which rides the rock at a non-origin
	# position and (with ExplosionFx.play setting global before reparenting) would fling them off-screen.
	var holder := Node2D.new()
	holder.name = "Buildings"
	add_child(holder)
	for b in prefab.get("buildings", []):
		if not (b is Dictionary):
			continue
		var t := String(b.get("type", ""))
		if Palette.is_type(t):
			Palette.spawn(t, holder, Vector2(float(b.get("x", 0.0)), float(b.get("y", 0.0))), float(b.get("rot", 0.0)))


func _process(delta: float) -> void:
	position.y += drift_speed * delta
	if position.y > screensize.y + _size:
		queue_free()


# Contact: damage the player (mirrors asteroid.gd::_on_area_entered) but DO NOT slow the rock or kick
# the ship — a big stronghold is an immovable anchor, not a billiards rock.
func _on_area_entered(area: Area2D) -> void:
	if area.has_method("take_damage") and "hull" in area:
		area.take_damage(damage_on_collide)


# Bind the rock into the asteroid drop-shadow system (scripts/parallax/asteroid_shadow_rig.gd), the
# same way layer_stellar / asteroid_lab do: one-shot bind of the rig's live screen-space mask texture
# + band strength onto the rock's ShaderMaterial. SCREEN_UV in Asteroids.gdshader tracks the rock as it
# drifts, so no per-frame update. No-op when no rig is in the tree (shadow_strength stays 0 = unchanged)
# — the rig exists on asteroid-field nodes (backdrop_coordinator asteroid_shadows + has_asteroids). If a
# stronghold is spawned before the backdrop builds the rig, shadows simply won't apply that frame.
func _apply_shadow(visual: Node) -> void:
	if visual == null or not is_inside_tree():
		return
	var rig: Node = get_tree().get_first_node_in_group("asteroid_shadow_rig")
	if rig == null or not rig.has_method("mask_texture") or not rig.has_method("band_strength"):
		return
	var inner := visual.get_node_or_null("Asteroid")
	if inner == null or not (inner is CanvasItem) or not (inner.material is ShaderMaterial):
		return
	var mat := inner.material as ShaderMaterial
	mat.set_shader_parameter("shadow_mask", rig.mask_texture(SHADOW_BAND))
	mat.set_shader_parameter("shadow_strength", rig.band_strength(SHADOW_BAND))


# ---------------------------------------------------------------- rock visual (shared with editor)

# Instance the procgen Asteroid scene with the NEAR-LAYER look (jagged, dithered, tinted), centered on
# `parent`'s origin. Inlines scripts/parallax/layer_stellar.gd::_spawn_asteroid's pixel-parity recipe
# (LayerPlanet._apply_pixel_parity is a non-static instance method, so we can't reuse it directly).
# Returns the visual node (a PixelPlanets Control), or null.
static func build_rock_visual(parent: Node, ast: Dictionary) -> Node:
	var ps := load(ASTEROID_SCENE) as PackedScene
	if ps == null:
		return null
	var a := ps.instantiate()
	var sz: float = float(ast.get("size", 120.0))
	# PlanetKit scenes ship full-rect anchors that collapse under some parents — reset to a 100×100 box.
	if a is Control:
		a.anchor_left = 0.0; a.anchor_top = 0.0
		a.anchor_right = 0.0; a.anchor_bottom = 0.0
		a.offset_left = 0.0; a.offset_top = 0.0
		a.offset_right = 100.0; a.offset_bottom = 100.0
		a.size = Vector2(100, 100)
		a.custom_minimum_size = Vector2(100, 100)
		a.pivot_offset = Vector2.ZERO
	var sf := sz / 100.0
	a.scale = Vector2(sf, sf)
	a.modulate = Color.WHITE
	a.position = Vector2(-sz * 0.5, -sz * 0.5)   # center on parent origin
	parent.add_child(a)   # add_child FIRST so _ready inits the ColorRect children
	# Per-instance material so seed/pixels/colors don't write to the shared inline material.
	var inner := a.get_node_or_null("Asteroid")
	if inner != null and inner is CanvasItem and inner.material != null:
		inner.material = inner.material.duplicate()
	if a.has_method("set_seed"):
		a.set_seed(int(ast.get("seed", 0)))
	if a.has_method("set_rotates"):
		a.set_rotates(float(int(ast.get("seed", 0)) % 100) / 100.0)   # fixed noise-field angle (no spin tick)
	if a.has_method("set_colors"):
		a.set_colors(_tint_ramp(_tint_color(ast)))
	if a.has_method("set_pixels"):
		a.set_pixels(maxf(sz, 16.0))
	# Pixel parity: set_pixels resized the inner ColorRect to sz×sz — reset to 100×100 so node scale
	# alone controls the footprint. Then apply the near-layer shader look.
	if inner is Control:
		inner.size = Vector2(100, 100)
		inner.position = Vector2.ZERO
		if inner.material is ShaderMaterial:
			var m := inner.material as ShaderMaterial
			m.set_shader_parameter("draw_outline", false)
			m.set_shader_parameter("roundness", float(ast.get("roundness", 0.0)))
			# COMBAT recipe, not the backdrop one this builder was copied from (layer_stellar): combat-scale
			# rocks that MOVE must NOT dither — the checkerboard samples raw UV so it shifts as the rock drifts,
			# moiréing into "odd colours" (the exact reason asteroid.gd + asteroid_fragment.gd force it false).
			m.set_shader_parameter("should_dither", false)
	# The rock is a PixelPlanets Control tree — Controls default to mouse_filter STOP and would EAT
	# clicks over the rock (the editor places buildings there; combat has no use for it either). Make
	# the whole visual click-through so mouse events fall through to the tool's _unhandled_input.
	_disable_mouse_recursive(a)
	return a


static func _disable_mouse_recursive(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_disable_mouse_recursive(c)


static func _tint_color(ast: Dictionary) -> Color:
	var t: Variant = ast.get("tint", null)
	if t is Array and (t as Array).size() >= 3:
		return Color(float(t[0]), float(t[1]), float(t[2]))
	return Color(0.70, 0.66, 0.60)


# Build the Asteroids.gdshader `colors` ramp (light → mid → dark), matching layer_stellar._tint_ramp.
static func _tint_ramp(base: Color) -> PackedColorArray:
	return PackedColorArray([base.lightened(0.35), base, base.darkened(0.45)])

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
@export var damage_on_collide: int = 2   # RETIRED 2026-07-18 (fly-over altitude model) — kept for saved-scene compat

# --- Boss/miniboss encounter (a prefab with role != "normal") ---
signal locked_in()                          # emitted ONCE the base has drifted fully into view
signal health_changed(cur: int, mx: int)    # aggregate structure HP, drives the boss health bar
signal cleared()                            # all structures destroyed

# Where an encounter locks: rock-CENTRE hold height as a fraction of screen height (size-independent so
# even a 400px boss rock locks; matches the editor's 50%-height preview so authored buildings stay framed).
const HOLD_FRAC := 0.45

var _size: float = 120.0
var _visual: Node = null
var screensize: Vector2 = Vector2(480, 270)

var _role: String = "normal"
var _locked: bool = false
var _drift_stashed: float = 0.0
var _hp_max: int = 0
var _bld_total: int = 0
var _bld_dead: int = 0
var _alive_hp: Dictionary = {}   # building node -> last-reported current hp


func _ready() -> void:
	screensize = get_viewport_rect().size
	z_index = GROUND_Z
	# Contact damage RETIRED (2026-07-18 altitude model): the stronghold is GROUND (z -5) — every
	# ship, the player's included, flies OVER it (the flyover drop shadows sell the altitude). The
	# old contact hit read as damage from an invincible unseen source — and once a boss/miniboss
	# rock LOCKS mid-screen the overlap is unavoidable (Roman: "unplayable"). Monitoring off: this
	# Area2D scans for nothing now (buildings carry their own hitboxes; bullets ignore the anchor).
	monitoring = false


# Build a stronghold from a prefab dict:
#   { "asteroid": { seed, size, roundness, dither, tint:[r,g,b], drift_speed },
#     "buildings": [ { type, x, y }, ... ] }
func configure(prefab: Dictionary) -> void:
	var ast: Dictionary = prefab.get("asteroid", {})
	_size = float(ast.get("size", 120.0))
	drift_speed = float(ast.get("drift_speed", drift_speed))
	_role = String(prefab.get("role", "normal"))
	# POI field colour (Roman 2026-07-18): in-game, the prefab rock tints to the SAME per-node
	# asteroid colour the loose rocks + backdrop belt use (Run meta "asteroid_base_color", set at
	# node depart) — the authored prefab tint is an EDITOR preview default, not canon; a prefab must
	# not arrive violet in an amber field. Same brighten-normalize as asteroid.gd so prefab + loose
	# rocks read as one family of lit foreground bodies. The EDITOR calls build_rock_visual directly
	# (no configure), so the tint knob there still previews the authored value.
	var run = get_node_or_null("/root/Run")
	if run != null and run.has_meta("asteroid_base_color"):
		var base: Color = run.get_meta("asteroid_base_color")
		var mx: float = maxf(base.r, maxf(base.g, base.b))
		base = base * (0.82 / maxf(mx, 0.01))
		ast = ast.duplicate()
		ast["tint"] = [base.r, base.g, base.b]
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
		if not Palette.is_type(t):
			continue
		var inst := Palette.spawn(t, holder, Vector2(float(b.get("x", 0.0)), float(b.get("y", 0.0))), float(b.get("rot", 0.0)))
		# Encounter HP aggregation: track every structure so the boss health bar = Σ structure HP.
		if inst != null and "max_health" in inst:
			_register_building(inst)


func _process(delta: float) -> void:
	# Encounter lock-in: once a miniboss/boss base has drifted fully into view, freeze it in place and
	# fire locked_in (the field then stops the parallax, shows the bar, raises music). Once only.
	if not _locked and _role != "normal" and position.y >= screensize.y * HOLD_FRAC:
		_locked = true
		_drift_stashed = drift_speed
		drift_speed = 0.0
		locked_in.emit()
	position.y += drift_speed * delta
	if position.y > screensize.y + _size:
		queue_free()


# (Contact damage retired 2026-07-18 — see _ready. The ship flies over the ground plane.)


# ---------------------------------------------------------------- encounter (boss / miniboss)

func role() -> String:
	return _role


# Aggregate max HP (Σ structure HP) — the boss health bar's max, read at lock-in.
func max_hp() -> int:
	return _hp_max


# True once every structure is destroyed — the director.boss_gate contract for the BOSS finale. Guards on
# _bld_total > 0 so a structureless prefab never auto-clears (author contract: encounters need >= 1 building).
func is_defeated() -> bool:
	return _bld_total > 0 and _bld_dead >= _bld_total


# Release the frozen rock so a cleared MINIBOSS husk drifts off again (restores the pre-lock speed).
func release_drift() -> void:
	drift_speed = _drift_stashed if _drift_stashed > 0.0 else 40.0


func _register_building(b: Node) -> void:
	var mh: int = maxi(1, int(b.max_health))
	_hp_max += mh
	_bld_total += 1
	_alive_hp[b] = mh
	if b.has_signal("health_changed"):
		b.health_changed.connect(_on_bld_hp.bind(b))
	if b.has_signal("died"):
		b.died.connect(_on_bld_died.bind(b))


# health_changed fires on every hit incl. the lethal one (cur < 1) BEFORE died, so we hold each building's
# current HP and re-sum; the lethal hit zeroes it, then died erases it — no double-count.
func _on_bld_hp(cur: int, _mx: int, b: Node) -> void:
	if _alive_hp.has(b):
		_alive_hp[b] = maxi(0, cur)
		_emit_hp()


func _on_bld_died(_v: int, b: Node) -> void:
	if not _alive_hp.has(b):
		return
	_alive_hp.erase(b)
	_bld_dead += 1
	_emit_hp()
	if _bld_dead >= _bld_total and _bld_total > 0:
		cleared.emit()


func _emit_hp() -> void:
	var cur := 0
	for v in _alive_hp.values():
		cur += int(v)
	health_changed.emit(cur, _hp_max)


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
			# Honor the prefab's authored dither (editor toggle). The stronghold rock wears the NEAR-LAYER
			# look (layer_stellar leaves dither at the shader default = on), NOT the gameplay-rock look
			# (asteroid.gd forces it off). Default on so existing prefabs keep the dithered near-layer feel.
			m.set_shader_parameter("should_dither", bool(ast.get("dither", true)))
	# The rock is a PixelPlanets Control tree — Controls default to mouse_filter STOP and would EAT
	# clicks over the rock (the editor places buildings there; combat has no use for it either). Make
	# the whole visual click-through so mouse events fall through to the tool's _unhandled_input.
	_disable_mouse_recursive(a)
	# Ground stack (2026-07-18): the rock FACE pins ABSOLUTELY below the building drop-shadow plane.
	# Buildings self-pin abs GROUND_Z (-5); their BuildingShadow carriers ride at -2 RELATIVE → -7;
	# so the rock must sit at -8 or the shadows (and, at -5/-6, the buildings themselves in some
	# hosts) render underneath it. Absolute, so every host — editor world (z 0) or the stronghold
	# root (-5) — gets the same stack: rock -8 < shadows -7 < buildings -5..-4 < rocks -1 < actors 0.
	# (Parallax backdrop lives on its own negative CanvasLayers, so -8 still draws above it.)
	if a is CanvasItem:
		(a as CanvasItem).z_as_relative = false
		(a as CanvasItem).z_index = GROUND_Z - 3
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

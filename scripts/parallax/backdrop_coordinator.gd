extends Node2D

@export var drift_speed: float = 22.0
@export var planet_size: float = 240.0
@export var planet_size_variance: float = 0.35
@export var tint_alpha: float = 0.09
@export var use_warp_streaks: bool = true
@export var warp_streak_count: int = 14
@export var warp_streak_speed: float = 750.0
@export var forced_planet_idx: int = -1
@export var pixel_density: float = 1.0
@export var asteroid_presence: float = 0.65

# Planet-to-tint mapping from V1 PLANET_TINT. Read galaxy_backdrop.gd for the exact colors.
const PLANET_TINT := {
	0: Color(1.0, 0.45, 0.20),  # LavaWorld
	1: Color(0.60, 0.85, 1.0),  # IceWorld
	2: Color(0.85, 0.65, 0.40), # DryTerran
	3: Color(0.65, 0.80, 0.55), # GasPlanet
	4: Color(0.70, 0.70, 0.75), # NoAtmosphere
	5: Color(0.45, 0.75, 0.55), # LandMasses
	6: Color(0.10, 0.10, 0.15), # BlackHole — skip tint
	7: Color(0.55, 0.45, 0.80), # Galaxy
	8: Color(1.00, 0.95, 0.75), # Star — skip tint
}
const SKIP_TINT := [6, 8]

var _layer_stars: Node = null
var _layer_planet: Node = null
var _layer_stellar_far: Node = null
var _layer_stellar_mid: Node = null
var _layer_stellar_near: Node = null
var _layer_streaks: Node = null
var _layer_composite: Node = null
var _scroll_layers: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer_stars         = get_node_or_null("LayerStars")
	_layer_planet        = get_node_or_null("LayerPlanet")
	_layer_stellar_far   = get_node_or_null("LayerStellarFar")
	_layer_stellar_mid   = get_node_or_null("LayerStellarMid")
	_layer_stellar_near  = get_node_or_null("LayerStellarNear")
	_layer_streaks       = get_node_or_null("LayerStreaks")
	_layer_composite     = get_node_or_null("LayerComposite")
	_scroll_layers = [_layer_planet, _layer_stellar_far, _layer_stellar_mid, _layer_stellar_near]
	_populate()


func _populate() -> void:
	var run_node := get_node_or_null("/root/Run")
	var stellar: Dictionary = {}
	if run_node and "current_stellar" in run_node:
		stellar = run_node.current_stellar

	var rng := RandomNumberGenerator.new()
	# Deterministic per-run seed in gameplay (from Run); a fresh time-based
	# seed everywhere else (tuner "Generate New", capture tool) so each
	# regeneration actually varies instead of repeating one fixed backdrop.
	var seed_val := int(Time.get_ticks_usec())
	if run_node:
		var rs := 12345 if not "run_seed" in run_node else int(run_node.run_seed)
		var sc := 0 if not "sectors_cleared" in run_node else int(run_node.sectors_cleared)
		seed_val = rs + sc * 9973
	rng.seed = abs(seed_val)

	# Planet
	var planet_idx := forced_planet_idx
	if planet_idx < 0:
		planet_idx = stellar.get("planet_idx", rng.randi() % 9)
	var size_mult := rng.randf_range(1.0 - planet_size_variance, 1.0 + planet_size_variance)
	var actual_size := planet_size * size_mult

	if _layer_planet != null:
		_layer_planet.set("pixel_density", pixel_density)
		if _layer_planet.has_method("spawn_planet"):
			_layer_planet.spawn_planet(planet_idx, actual_size, rng, "")
		# Attach POI moons if present
		if _layer_planet.has_method("attach_moons"):
			var moons: Array = stellar.get("moons", [])
			if not moons.is_empty():
				_layer_planet.attach_moons(moons)

	# Stellar layers
	var has_asteroids: bool = stellar.get("has_asteroids", rng.randf() < asteroid_presence)
	for layer in _scroll_layers:
		if layer != null and layer.has_method("populate"):
			if has_asteroids:
				layer.populate(rng)
			else:
				layer.populate(rng)  # still populate, asteroid_count handles density

	# Warp streaks
	if _layer_streaks != null:
		_layer_streaks.set("streak_count", warp_streak_count)
		_layer_streaks.set("streak_speed", warp_streak_speed)
		_layer_streaks.set("enabled", use_warp_streaks)

	# Tints
	_apply_tints(planet_idx)
	_setup_composite(planet_idx)


func _apply_tints(planet_idx: int) -> void:
	var base_tint: Color = PLANET_TINT.get(planet_idx, Color.WHITE)
	var skip := planet_idx in SKIP_TINT

	_set_modulate(_layer_stellar_far,  base_tint.lerp(Color.WHITE, 0.75) if not skip else Color.WHITE)
	_set_modulate(_layer_stellar_mid,  base_tint.lerp(Color.WHITE, 0.60) if not skip else Color.WHITE)
	_set_modulate(_layer_stellar_near, base_tint.lerp(Color.WHITE, 0.45) if not skip else Color.WHITE)


func _set_modulate(layer: Node, color: Color) -> void:
	if layer == null:
		return
	if "modulate_color" in layer:
		layer.modulate_color = color
	else:
		var cm := layer.get_node_or_null("CanvasModulate") as CanvasModulate
		if cm:
			cm.color = color


func _setup_composite(planet_idx: int) -> void:
	if _layer_composite == null:
		return
	var base_tint: Color = PLANET_TINT.get(planet_idx, Color.WHITE)
	var skip := planet_idx in SKIP_TINT
	var grade_color := Color.WHITE.lerp(base_tint, tint_alpha) if not skip else Color.WHITE

	var cm := _layer_composite.get_node_or_null("CanvasModulate") as CanvasModulate
	if cm:
		cm.color = grade_color

	var grade := _layer_composite.get_node_or_null("GradeRect") as ColorRect
	if grade and grade.material == null:
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		grade.material = mat

	var vignette := _layer_composite.get_node_or_null("Vignette") as Sprite2D
	if vignette and vignette.texture == null:
		var mat2 := CanvasItemMaterial.new()
		mat2.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		vignette.material = mat2
		var grad := Gradient.new()
		grad.colors = PackedColorArray([Color(1,1,1,1), Color(0.74, 0.74, 0.74, 1)])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 64
		tex.height = 64
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to   = Vector2(1.0, 0.5)
		vignette.texture = tex


func _process(delta: float) -> void:
	var drift_delta := drift_speed * delta
	for layer in _scroll_layers:
		if layer != null and layer.has_method("scroll"):
			layer.scroll(drift_delta * float(layer.get("scroll_rate") if "scroll_rate" in layer else 1.0))
	if _layer_stars != null and _layer_stars.has_method("scroll_stars"):
		_layer_stars.scroll_stars(drift_delta)

extends RefCounted
class_name AsteroidBakeCache
## Bake-once cache for background/debris asteroid atlases, used by the flagged baked-asteroid
## paths (layer_stellar backdrop + asteroid_fragment death chunks).
##
## 1:1 pixel rule: a baked sprite must be DISPLAYED at the px it was BAKED at, or it resizes
## and the pixel art blurs. So we bake a SET of native-size buckets; each consumer quantizes
## its desired size to the nearest bucket and renders at scale 1.0. Sizes above the top bucket
## fall back to the live procedural rock (a shader rock renders at pixels=size, so it is
## inherently 1:1) — that doubles as the LOD "hero" tier for the big rare rocks.
##
## Purpose: the #116172 pipeline-burst crash test for asteroid POIs (removes the live
## Asteroids.gdshader from the dense backdrop + the 3-6 procgen death chunks) AND the
## death-time frame drop (chunks become cheap sprites). Default OFF.

const ASTEROID_SCENE := "res://Planets/Asteroids/Asteroid.tscn"
# Display-size buckets (px). Each baked at its native size for 1:1. Small + many is exactly
# where baking pays off (chunks, far/near backdrop); big + rare stays live above the top.
const BUCKETS: Array = [16, 24, 32, 48, 64]

static var enabled: bool = false
static var _atlases: Dictionary = {}   # bucket_px:int -> {texture, variants, frames, frame_px}


static func is_ready() -> bool:
	return _atlases.size() >= BUCKETS.size()


static func max_bucket() -> int:
	return int(BUCKETS[BUCKETS.size() - 1])


# Nearest-size bucket atlas for a desired px. {} if not baked yet.
static func get_atlas_for_size(px: float) -> Dictionary:
	if _atlases.is_empty():
		return {}
	var best_b: int = int(BUCKETS[0])
	var best_d: float = absf(px - float(best_b))
	for b in BUCKETS:
		var d: float = absf(px - float(b))
		if d < best_d:
			best_d = d
			best_b = int(b)
	return _atlases.get(best_b, {})


static func clear() -> void:
	_atlases = {}


## Bake every size bucket once (idempotent). `host` must be a live node — the bake spins up a
## temporary SubViewport under it. ~a few seconds cold (production should run it behind a load
## step). Safe to await more than once.
static func ensure_baked(host: Node, variants: int = 10, frames: int = 24) -> void:
	if is_ready():
		return
	var scene := load(ASTEROID_SCENE) as PackedScene
	if scene == null:
		return
	for b in BUCKETS:
		var bucket: int = int(b)
		if _atlases.has(bucket):
			continue
		var fpx := bucket
		var configure := func(inst, variant_idx: int):
			if inst is Control:
				inst.anchor_left = 0.0; inst.anchor_top = 0.0
				inst.anchor_right = 0.0; inst.anchor_bottom = 0.0
				inst.offset_left = 0.0; inst.offset_top = 0.0
				inst.offset_right = 100.0; inst.offset_bottom = 100.0
				inst.size = Vector2(100, 100)
				inst.custom_minimum_size = Vector2(100, 100)
				inst.pivot_offset = Vector2.ZERO
			if inst.has_method("set_seed"):
				inst.set_seed(hash(variant_idx) % 10000)
			# NEUTRAL grey rock — the hue comes from the consumer's modulate (the POI asteroid
			# colour, shunted from the sector map's realistic palette), so every baked rock in a
			# POI shares its colour. The per-variant grey value just varies light vs dark rocks.
			if inst.has_method("set_colors"):
				var g: float = lerp(0.55, 0.85, fmod(float(variant_idx) * 0.41 + 0.13, 1.0))
				var c := Color(g, g, g)
				inst.set_colors(PackedColorArray([c.lightened(0.30), c, c.darkened(0.42)]))
			# pixels == bake px == display px → 1:1.
			if inst.has_method("set_pixels"):
				inst.set_pixels(float(fpx))
			var inner = inst.get_node_or_null("Asteroid")
			if inner is Control:
				inner.size = Vector2(100, 100)
				inner.position = Vector2.ZERO
				var rt := fmod(float(variant_idx) * 0.618 + 0.21, 1.0)
				var rnd: float = lerp(0.40, 0.78, rt)
				if inner.material is ShaderMaterial:
					var m := inner.material as ShaderMaterial
					m.set_shader_parameter("draw_outline", false)
					m.set_shader_parameter("roundness", rnd)
					m.set_shader_parameter("size", lerp(8.0, 1.5, rnd))
					m.set_shader_parameter("octaves", 3)
					var ang := deg_to_rad(225.0)
					m.set_shader_parameter("light_origin", Vector2(0.5 + 0.45 * cos(ang), 0.5 + 0.45 * sin(ang)))
				# Atlas stays neutral (modulate white) — the consumer applies the POI colour.
				inner.modulate = Color(1.0, 1.0, 1.0, 1.0)
		var atlas: Dictionary = await SpriteBaker.bake_variant_atlas(host, scene, configure, variants, fpx, frames)
		if not atlas.is_empty():
			_atlases[bucket] = atlas

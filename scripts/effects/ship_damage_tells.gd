extends Node2D

# ShipDamageTells — progressive battle-damage tells for a ship. Attach as a child of the ship
# (at its origin), call setup() once, then set_damage(0→1) as HP drops. The escalation scales
# with how many markers the ship carries, so a big multi-engine ship racks up dramatically more
# tells than a 1-marker chaff (which shows a single spark before it pops) — yet even a grazed
# ship shows the overlay + first spark:
#   • the damage_noise overlay sensitivity ramps with damage;
#   • spark trails light up marker-by-marker (Engine* first / favoured, sprite CENTRE last as
#     the fallback + a guaranteed tell);
#   • past BURN_THRESHOLD a burning trail ignites at one marker;
#   • at 1.0 the body disintegrates from a marker and explodes into debris + embers.
#
# Built for the Shader Lab Ship-Damage panel; designed to drop onto enemy_base later
# (take_hit → set_damage(1 - health/max_health), self_explode = false so the enemy's own
# explode() owns death).

signal destroyed

const SparkTrailFx = preload("res://scripts/effects/spark_trail_fx.gd")
const BURNING_TRAIL := preload("res://scenes/effects/burning_trail.tscn")
const ShipDebrisEmber = preload("res://scripts/effects/ship_debris_ember.gd")
const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")
const BurnFx = preload("res://scripts/burn_fx.gd")
const DAMAGE_SHADER = preload("res://graphics/damage_noise.gdshader")
const DAMAGE_NOISE_TEX = preload("res://resources/noise_damage.tres")
const DAMAGE_EDGE_TEX = preload("res://resources/edge_distance_flat.tres")

const MAX_SENS := 0.85          # damage-overlay sensitivity at full damage
const SPARK_START := 0.12       # damage fraction where the first (engine) spark lights
const BURN_THRESHOLD := 0.6     # damage fraction where the burning trail ignites
const SPARK_AMOUNT_CAP := 50    # per-marker spark particle cap (many enemies on screen)

# Tunable damage-tell suite (Roman 2026-06-12) — setup()'s cfg overrides these (the Ship-Damage
# panel tunes them PER SIZE category). Defaults reproduce the current behavior.
const DEFAULT_CFG := {
	"max_sens": MAX_SENS,
	"spark_start": SPARK_START,
	"burn_threshold": BURN_THRESHOLD,
	"spark_amount": float(SPARK_AMOUNT_CAP),
	"expl_size": 1.0,        # death explosion boom size (× size_scale)
	"expl_density": 1.0,     # death explosion boom-count multiplier
	"expl_shockwave": 1.0,   # death shockwave reach
	"debris": 1.0,           # death debris count multiplier
}

var self_explode: bool = true   # false = the caller (enemy_base) owns the explosion; we just disintegrate

var _cfg: Dictionary = DEFAULT_CFG.duplicate()
var _sprite: Sprite2D = null
var _mat: ShaderMaterial = null
var _sparks: Array = []          # [{pos: Vector2, parts: GPUParticles2D, lit: bool}]
var _burn_parts: GPUParticles2D = null
var _size_scale: float = 1.0
var _level: float = 0.0
var _destroyed: bool = false


func setup(ship: Node2D, sprite: Sprite2D, size_scale: float = 1.0, cfg: Dictionary = {}) -> void:
	_cfg = DEFAULT_CFG.duplicate()
	_cfg.merge(cfg, true)
	_sprite = sprite
	_size_scale = maxf(0.5, size_scale)
	# Damage overlay — reuse the ship's own damage_noise material if it has one, else install it.
	if _sprite != null and is_instance_valid(_sprite):
		if _sprite.material is ShaderMaterial and (_sprite.material as ShaderMaterial).shader == DAMAGE_SHADER:
			_mat = _sprite.material
		else:
			_mat = _make_damage_material()
			_sprite.material = _mat
	# Markers: ANY marker is eligible, WEIGHTED toward engines (Roman 2026-06-11). Engines come
	# FIRST (so the progressive sparks light them first) AND carry a higher random-pick weight;
	# muzzles / cannons / turrets are normal weight; the sprite CENTRE is the always-present
	# fallback (a guaranteed tell on a markerless ship).
	var marker_data: Array = []
	if ship != null:
		for m in ship.find_children("Engine*", "Marker2D", true, false):
			if m is Node2D:
				marker_data.append({"pos": to_local((m as Node2D).global_position), "weight": 3.0})
		for pat in ["Muzzle*", "cannon_*", "Turret*"]:
			for m in ship.find_children(pat, "Marker2D", true, false):
				if m is Node2D:
					marker_data.append({"pos": to_local((m as Node2D).global_position), "weight": 1.0})
	marker_data.append({"pos": Vector2.ZERO, "weight": 1.0})   # centre — always present
	# One spark emitter per marker, off until lit.
	for md in marker_data:
		var inst := SparkTrailFx.spawn(self, md["pos"])
		var parts := SparkTrailFx.particles(inst)
		if parts != null:
			parts.local_coords = false
			parts.amount = mini(parts.amount, int(_cfg["spark_amount"]))
			parts.emitting = false
		_sparks.append({"pos": md["pos"], "weight": float(md["weight"]), "parts": parts, "lit": false})
	# Pre-place the burning trail at a weighted-random marker (engines favoured).
	var bm: Vector2 = _pick_weighted_marker()
	var bt: Node2D = BURNING_TRAIL.instantiate()
	bt.position = bm
	add_child(bt)
	_burn_parts = SparkTrailFx.particles(bt)
	if _burn_parts != null:
		_burn_parts.local_coords = false
		_burn_parts.emitting = false


func set_damage(t: float) -> void:
	if _destroyed:
		return
	_level = clampf(t, 0.0, 1.0)
	if _mat != null:
		_mat.set_shader_parameter("sensitivity", _level * float(_cfg["max_sens"]))
	# Sparks light marker-by-marker across [spark_start, burn_threshold]. More markers → a longer
	# escalation (big ships); a single-marker ship lights its one spark at spark_start.
	var ss: float = float(_cfg["spark_start"])
	var bt_thr: float = float(_cfg["burn_threshold"])
	var n: int = _sparks.size()
	for i in n:
		var thresh: float = ss
		if n > 1:
			thresh = lerpf(ss, bt_thr, float(i) / float(n - 1))
		_set_spark(i, _level >= thresh)
	# Burning trail past the threshold (reversible, so the lab slider can play both ways).
	if _burn_parts != null and is_instance_valid(_burn_parts):
		_burn_parts.emitting = _level >= bt_thr
	if _level >= 1.0:
		_destroy()


func _set_spark(i: int, lit: bool) -> void:
	var s: Dictionary = _sparks[i]
	if bool(s["lit"]) == lit:
		return
	s["lit"] = lit
	if s["parts"] != null and is_instance_valid(s["parts"]):
		s["parts"].emitting = lit


func _destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	var world: Vector2 = global_position
	if _sprite != null and is_instance_valid(_sprite):
		world = _sprite.global_position
		# Disintegrate from a weighted-random marker (engines favoured) — bias the burn origin
		# toward that marker's side.
		var mk: Vector2 = _pick_weighted_marker()
		var origin := Vector2(0.5, 0.5)
		if mk.length() > 0.1:
			origin += mk.normalized() * 0.3
		origin.x = clampf(origin.x, 0.0, 1.0)
		origin.y = clampf(origin.y, 0.0, 1.0)
		BurnFx.apply_burn(_sprite, 0.5, Color(0, 0, 0, 0), origin)
	# Stop the tells.
	for s in _sparks:
		if s["parts"] != null and is_instance_valid(s["parts"]):
			s["parts"].emitting = false
	if _burn_parts != null and is_instance_valid(_burn_parts):
		_burn_parts.emitting = false
	if self_explode:
		_spawn_death_vfx(world)
	destroyed.emit()


# Explosion + burning debris (debris + embers via ShipDebrisEmber), spawned into the ship's
# PARENT so they survive the ship's removal. Bigger ships throw more pieces.
func _spawn_death_vfx(world: Vector2) -> void:
	var container: Node = null
	var ship: Node = get_parent()
	if ship != null:
		container = ship.get_parent()
	if container == null:
		container = get_tree().current_scene if get_tree() != null else null
	if container == null:
		return
	# Death blast via the centralized explosion system — size + density + shockwave scale with the
	# ship size and the tuned config (Roman 2026-06-12).
	ExplosionFx.play_config(world, {
		"type": "basic",
		"size": (1.0 + 0.4 * _size_scale) * float(_cfg["expl_size"]),
		"density": maxi(1, int(round((1.0 + _size_scale * 0.6) * float(_cfg["expl_density"])))),
		"area": 6.0 + _size_scale * 5.0,
		"shockwave": float(_cfg["expl_shockwave"]) * clampf(_size_scale, 0.6, 2.5),
		"glow": 1.2,
	}, container)
	# Debris count scales strongly with ship size — a big ship leaves a lot more behind
	# (Roman 2026-06-11): ~5 pieces for chaff, up to ~16 for the largest hulls.
	var pieces: int = clampi(int(round((2.0 + _size_scale * 4.0) * float(_cfg["debris"]))), 3, 20)
	for i in pieces:
		var ang := randf_range(0.15, PI - 0.15)
		var spd := randf_range(50.0, 130.0)
		ShipDebrisEmber.spawn(container, world, {
			"velocity": Vector2(cos(ang), sin(ang)) * spd,
			"spin": randf_range(-6.0, 6.0),
			"piece_scale": randf_range(0.8, 1.4) * clampf(_size_scale, 0.7, 1.8),
		})


# Weighted-random marker pick (engines favoured, weight 3 vs 1). Falls back to centre.
func _pick_weighted_marker() -> Vector2:
	if _sparks.is_empty():
		return Vector2.ZERO
	var total: float = 0.0
	for s in _sparks:
		total += float(s["weight"])
	if total <= 0.0:
		return _sparks[0]["pos"]
	var r: float = randf() * total
	for s in _sparks:
		r -= float(s["weight"])
		if r <= 0.0:
			return s["pos"]
	return _sparks[_sparks.size() - 1]["pos"]


func _make_damage_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = DAMAGE_SHADER
	mat.set_shader_parameter("sensitivity", 0.0)
	mat.set_shader_parameter("noise_texture", DAMAGE_NOISE_TEX)
	mat.set_shader_parameter("edge_distance_map", DAMAGE_EDGE_TEX)
	mat.set_shader_parameter("noise_seed", float(randi() % 999))
	mat.set_shader_parameter("max_strength", 0.9)
	mat.set_shader_parameter("edge_bias_strength", 0.3)
	mat.set_shader_parameter("details_opacity", 0.1)
	mat.set_shader_parameter("edge_color", Color("494e55"))
	mat.set_shader_parameter("details_color", Color("cacaca"))
	return mat

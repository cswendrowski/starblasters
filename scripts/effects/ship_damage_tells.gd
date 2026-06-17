extends Node2D

# ShipDamageTells — progressive battle-damage tells for a ship. Attach as a child of the ship
# (at its origin), call setup() once, then set_damage(0→1) as HP drops. The escalation scales
# with how many markers the ship carries, so a big multi-engine ship racks up dramatically more
# tells than a 1-marker chaff (which shows a single spark before it pops) — yet even a grazed
# ship shows the overlay + first spark:
#   • the damage_noise overlay sensitivity ramps with damage;
#   • spark trails light up marker-by-marker (Engine* first / favoured, sprite CENTRE last as
#     the fallback + a guaranteed tell);
#   • past BURN_THRESHOLD burning trails ignite progressively — a chaff gets one, a big ship gets
#     several, each at a later threshold, optionally preceded by a TORCH fire that the trail masks
#     as it takes over (intro: a small ball-burst or a 50%→100% scale-in);
#   • at 1.0 the body disintegrates from a marker and explodes into debris + embers.
#
# Built for the Shader Lab Ship-Damage panel; designed to drop onto enemy_base later
# (take_hit → set_damage(1 - health/max_health), self_explode = false so the enemy's own
# explode() owns death).

signal destroyed

const SparkTrailFx = preload("res://scripts/effects/spark_trail_fx.gd")
const BURNING_TRAIL := preload("res://scenes/effects/burning_trail.tscn")
const TORCH_SHADER := preload("res://graphics/torch_fire.gdshader")
const ShipDebrisEmber = preload("res://scripts/effects/ship_debris_ember.gd")
const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")
const BurnFx = preload("res://scripts/effects/burn_fx.gd")
const DAMAGE_SHADER = preload("res://graphics/damage_noise.gdshader")
const DAMAGE_NOISE_TEX = preload("res://resources/noise_damage.tres")
const DAMAGE_EDGE_TEX = preload("res://resources/edge_distance_flat.tres")

const MAX_SENS := 0.85          # damage-overlay sensitivity at full damage
const SPARK_START := 0.12       # damage fraction where the first (engine) spark lights
const BURN_THRESHOLD := 0.6     # damage fraction where the FIRST burning trail ignites
const SPARK_AMOUNT_CAP := 50    # per-marker spark particle cap (many enemies on screen)

# Progressive burning trails (Roman 2026-06-12). Bigger ships ignite MULTIPLE trails as the hull
# fails — each at a later threshold spread across [burn_threshold, TRAIL_THR_TOP]. A TORCH fire can
# precede each trail by `torch_lead` and is removed under cover of the trail's intro. Two intros
# (burst / scale-in) mask the particle start; pick one specifically or let it randomize per trail.
const TRAIL_THR_TOP := 0.92        # damage fraction at which the LAST trail ignites
const BURN_INTRO_BURST := 0
const BURN_INTRO_SCALE := 1
const BURN_INTRO_RANDOM := 2
const BURN_SCALE_IN_TIME := 0.28   # scale-in tween duration (seconds)
const TRAIL_SCALE_MIN := 0.5       # scale-in starts at 50% sprite size (per Roman's spec)

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
	"burn_trails": 1.0,      # number of progressive burning trails (small 1 → large 3+)
	"torch_lead": 0.12,      # dmg fraction a torch fire precedes its trail (0 = no torch)
	"burn_intro": 2.0,       # trail intro: 0 burst, 1 scale-in, 2 random per-trail
	# Marker-bias weights (Shader Lab → Markers, Roman 2026-06-17): random-pick weight per marker
	# category for the damage tells. 0 = that category is NOT eligible. Defaults reproduce the prior
	# hardcoded behavior EXACTLY — engines favoured (3), muzzle/turret normal (1), centre fallback (1);
	# thruster/launcher were not gathered before (0), now tunable on.
	"w_engine": 3.0,
	"w_thruster": 0.0,
	"w_muzzle": 1.0,
	"w_launcher": 0.0,
	"w_turret": 1.0,
	"w_centre": 1.0,
}

var self_explode: bool = true   # false = the caller (enemy_base) owns the explosion; we just disintegrate

var _cfg: Dictionary = DEFAULT_CFG.duplicate()
var _sprite: Sprite2D = null
var _mat: ShaderMaterial = null
var _sparks: Array = []          # [{pos: Vector2, parts: GPUParticles2D, lit: bool}]
var _burn_slots: Array = []      # [{pos, trail, parts, torch, trail_thr, torch_thr, lit, intro}]
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
	# Markers: ANY marker is eligible, WEIGHTED per category via _cfg["w_*"] (Roman 2026-06-11,
	# made tunable 2026-06-17). Categories are gathered in this ORDER (engines first) so the
	# progressive sparks light engines first; a category at weight 0 is skipped entirely. The
	# sprite CENTRE is the always-present fallback (a guaranteed tell on a markerless ship).
	var marker_specs: Array = [
		{"patterns": ["Engine*"],            "weight": float(_cfg["w_engine"])},
		{"patterns": ["Thruster*"],          "weight": float(_cfg["w_thruster"])},
		{"patterns": ["Muzzle*", "cannon_*"], "weight": float(_cfg["w_muzzle"])},
		{"patterns": ["Launcher*"],          "weight": float(_cfg["w_launcher"])},
		{"patterns": ["Turret*"],            "weight": float(_cfg["w_turret"])},
	]
	var marker_data: Array = []
	if ship != null:
		for spec in marker_specs:
			var w: float = float(spec["weight"])
			if w <= 0.0:
				continue
			for pat in spec["patterns"]:
				for m in ship.find_children(pat, "Marker2D", true, false):
					if m is Node2D:
						marker_data.append({"pos": to_local((m as Node2D).global_position), "weight": w})
	marker_data.append({"pos": Vector2.ZERO, "weight": maxf(0.001, float(_cfg["w_centre"]))})   # centre — always present
	# One spark emitter per marker, off until lit.
	for md in marker_data:
		var inst := SparkTrailFx.spawn(self, md["pos"])
		var parts := SparkTrailFx.particles(inst)
		if parts != null:
			parts.local_coords = false
			parts.amount = mini(parts.amount, int(_cfg["spark_amount"]))
			parts.emitting = false
		_sparks.append({"pos": md["pos"], "weight": float(md["weight"]), "parts": parts, "lit": false})
	# Progressive burning-trail slots (one per marker; more on bigger ships, each with an optional
	# torch precursor). Built after the sparks so it can draw from the same weighted markers.
	_build_burn_slots()


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
	_update_burn_slots()
	if _level >= 1.0:
		_destroy()


func _set_spark(i: int, lit: bool) -> void:
	var s: Dictionary = _sparks[i]
	if bool(s["lit"]) == lit:
		return
	s["lit"] = lit
	if s["parts"] != null and is_instance_valid(s["parts"]):
		s["parts"].emitting = lit


# ── Progressive burning trails ─────────────────────────────────────────────────────────────────

# Build one burning-trail slot per requested trail, each pinned to a distinct weighted marker. The
# slots ignite later and later (across [burn_threshold, TRAIL_THR_TOP]) so a big ship's fire spreads
# as it dies; each may carry a torch precursor that the trail masks when it takes over.
func _build_burn_slots() -> void:
	var want: int = clampi(int(round(float(_cfg["burn_trails"]))), 1, maxi(1, _sparks.size()))
	var lead: float = maxf(0.0, float(_cfg["torch_lead"]))
	var bt_thr: float = float(_cfg["burn_threshold"])
	var intro: int = int(round(float(_cfg["burn_intro"])))
	var positions: Array = _pick_distinct_markers(want)
	for i in positions.size():
		var pos: Vector2 = positions[i]
		var trail_thr: float = bt_thr
		if positions.size() > 1:
			trail_thr = lerpf(bt_thr, TRAIL_THR_TOP, float(i) / float(positions.size() - 1))
		var torch_thr: float = maxf(float(_cfg["spark_start"]), trail_thr - lead)
		var bt: Node2D = BURNING_TRAIL.instantiate()
		bt.position = pos
		add_child(bt)
		var parts: GPUParticles2D = SparkTrailFx.particles(bt)
		if parts != null:
			parts.local_coords = false
			parts.emitting = false
		var torch: ColorRect = _make_torch(pos) if lead > 0.0 else null
		_burn_slots.append({
			"pos": pos, "trail": bt, "parts": parts, "torch": torch,
			"trail_thr": trail_thr, "torch_thr": torch_thr, "lit": false, "intro": intro,
		})


# Drive the burn slots each damage update. Reversible (so the lab slider replays both ways): a slot
# lights its trail once damage reaches trail_thr, extinguishes if it drops back. The torch shows only
# in its [torch_thr, trail_thr) window — once the trail lights, the torch is gone, masked by the intro.
func _update_burn_slots() -> void:
	for slot in _burn_slots:
		var trail_thr: float = float(slot["trail_thr"])
		var lit: bool = bool(slot["lit"])
		if _level >= trail_thr and not lit:
			_ignite_trail(slot)
		elif _level < trail_thr and lit:
			_extinguish_trail(slot)
		var torch = slot["torch"]
		if torch != null and is_instance_valid(torch):
			torch.visible = (_level >= float(slot["torch_thr"])) and not bool(slot["lit"])


func _ignite_trail(slot: Dictionary) -> void:
	slot["lit"] = true
	# Drop the torch in the same frame — the trail's intro covers its removal.
	var torch = slot["torch"]
	if torch != null and is_instance_valid(torch):
		torch.visible = false
	if _resolve_intro(int(slot["intro"])) == BURN_INTRO_BURST:
		_burn_intro_burst(slot)
		var parts: GPUParticles2D = slot["parts"]
		if parts != null and is_instance_valid(parts):
			parts.emitting = true
	else:
		_burn_intro_scale(slot)


func _extinguish_trail(slot: Dictionary) -> void:
	slot["lit"] = false
	var parts: GPUParticles2D = slot["parts"]
	if parts != null and is_instance_valid(parts):
		parts.emitting = false
	var trail = slot["trail"]
	if trail != null and is_instance_valid(trail):
		trail.scale = Vector2.ONE


func _resolve_intro(intro: int) -> int:
	if intro == BURN_INTRO_RANDOM:
		return BURN_INTRO_BURST if (randi() % 2 == 0) else BURN_INTRO_SCALE
	return intro


# Burst intro: a small single ball explosion at the trail marker pops as the particles start, hiding
# the cold-start "pop-in" of the emitter.
func _burn_intro_burst(slot: Dictionary) -> void:
	var trail = slot["trail"]
	var world: Vector2 = (trail.global_position if (trail != null and is_instance_valid(trail)) else global_position)
	var container: Node = _vfx_container()
	if container == null:
		return
	ExplosionFx.play_config(world, {
		"type": "ball", "size": 0.5 * clampf(_size_scale, 0.7, 1.6), "density": 1,
		"area": 0.0, "shockwave": 0.0, "glow": 0.9, "sparks": 0.4, "debris": 0.0,
		"light": false, "sound": false,
	}, container)


# Scale-in intro: the trail emitter grows from 50% to full over a short tween while emitting, so the
# fire eases in instead of snapping on.
func _burn_intro_scale(slot: Dictionary) -> void:
	var trail = slot["trail"]
	var parts: GPUParticles2D = slot["parts"]
	if parts != null and is_instance_valid(parts):
		parts.emitting = true
	if trail == null or not is_instance_valid(trail):
		return
	trail.scale = Vector2.ONE * TRAIL_SCALE_MIN
	var tw: Tween = trail.create_tween()
	tw.tween_property(trail, "scale", Vector2.ONE, BURN_SCALE_IN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# Pick `n` DISTINCT markers, weighted toward engines, without replacement. Falls back to fewer if the
# ship has fewer markers than requested.
func _pick_distinct_markers(n: int) -> Array:
	var pool: Array = []
	for s in _sparks:
		pool.append({"pos": s["pos"], "weight": float(s["weight"])})
	var out: Array = []
	while out.size() < n and not pool.is_empty():
		var total: float = 0.0
		for e in pool:
			total += float(e["weight"])
		var r: float = randf() * maxf(total, 0.0001)
		var idx: int = pool.size() - 1
		for j in pool.size():
			r -= float(pool[j]["weight"])
			if r <= 0.0:
				idx = j
				break
		out.append(pool[idx]["pos"])
		pool.remove_at(idx)
	return out


# A standalone torch-fire plume (torch_fire.gdshader) at a hull marker — the same proven setup as the
# player engine torch (flipped 180° so the plume reads off the marker), sized to the ship.
func _make_torch(local_pos: Vector2) -> ColorRect:
	var sz := Vector2(16, 22) * clampf(_size_scale, 0.7, 1.6)
	var t := ColorRect.new()
	t.size = sz
	t.position = local_pos - Vector2(sz.x * 0.5, sz.y * 0.25)
	t.pivot_offset = sz * 0.5
	t.rotation = PI
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.color = Color(0, 0, 0, 0)
	t.z_index = 1
	var mat := ShaderMaterial.new()
	mat.shader = TORCH_SHADER
	mat.set_shader_parameter("pixelSize", 0.02)
	mat.set_shader_parameter("toColor", Color.html("894400"))
	mat.set_shader_parameter("fromColor", Color.html("f06007"))
	mat.set_shader_parameter("sparkColor", Color.html("ffa435"))
	mat.set_shader_parameter("smokeColor", Color.html("050505"))
	mat.set_shader_parameter("speed", 5.0)
	mat.set_shader_parameter("sparkSpeed", 0.25)
	mat.set_shader_parameter("aspectRatio", sz.x / sz.y)
	mat.set_shader_parameter("size", Vector2(0.06, 0.6))
	mat.set_shader_parameter("alpha", 0.95)
	mat.set_shader_parameter("timeOffset", randf_range(0.0, 1000.0))
	mat.set_shader_parameter("seedOffset", randf_range(0.0, 100.0))
	t.material = mat
	t.visible = false
	add_child(t)
	return t


# The world container death/intro VFX spawn into (the ship's PARENT) so they survive the ship.
func _vfx_container() -> Node:
	var ship: Node = get_parent()
	var container: Node = ship.get_parent() if ship != null else null
	if container == null:
		container = get_tree().current_scene if get_tree() != null else null
	return container


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
	for slot in _burn_slots:
		var bp = slot["parts"]
		if bp != null and is_instance_valid(bp):
			bp.emitting = false
		var tc = slot["torch"]
		if tc != null and is_instance_valid(tc):
			tc.visible = false
	if self_explode:
		_spawn_death_vfx(world)
	destroyed.emit()


# Explosion + burning debris (debris + embers via ShipDebrisEmber), spawned into the ship's
# PARENT so they survive the ship's removal. Bigger ships throw more pieces.
func _spawn_death_vfx(world: Vector2) -> void:
	var container: Node = _vfx_container()
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
			# Piece scale is FIXED (~1×), per the convention "debris count scales with
			# enemy size, piece scale fixed at 1×" — bigger ships throw MORE pieces (above),
			# not BIGGER ones. The old `* clampf(_size_scale, 0.7, 1.8)` inflated big-enemy
			# debris up to ~2.5×, reading larger than the canon explosion-path debris
			# (Shader Lab parity, Roman 2026-06-17).
			"piece_scale": randf_range(0.8, 1.4),
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

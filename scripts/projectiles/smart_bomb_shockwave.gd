extends Node2D

# Smart Bomb shockwave — an expanding radial energy ring released from the
# player. The leading edge travels at the clarity speed ceiling (8 px/frame =
# 480 px/s) and the wave keeps expanding until it is entirely off-screen, then
# frees itself.
#
# As the radius grows it sweeps over enemies + enemy bullets:
#   - Enemy bullets inside the radius are cancelled.
#   - Each enemy is damaged ONCE, when the leading edge first reaches it. The
#     damage IGNORES SHIELDS (simple per-pip shield + ShieldComponent charges
#     are zeroed before the hit), so it one-shots any large non-tough enemy or
#     smaller. Tough / huge / bosses survive on HP alone.
#   - Bosses are bitten through the normal take_hit() path so their phase /
#     shield logic stays intact (the wave never one-shots them anyway).

const ClarityRules = preload("res://scripts/systems/clarity.gd")
const BaseMissileC = preload("res://scripts/projectiles/base_missile.gd")
const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")

# Leading-edge travel speed — the 8 px/frame motion-clarity ceiling.
const SPEED: float = ClarityRules.ABS_MAX_SPEED   # 480 px/s
# Expand well past the 480x270 viewport diagonal so the wave clears the screen
# (and the side gutters) before it dies.
const MAX_RADIUS: float = 620.0

var _damage: int = 18
var _origin: Vector2 = Vector2.ZERO
var _radius: float = 0.0
var _hit: Dictionary = {}   # enemy instance_id -> true (damage-once bookkeeping)


# Call BEFORE adding to the tree (origin is applied in _ready so a deferred
# add — e.g. from the death-bomb during a physics callback — positions safely).
func configure(damage: int, origin: Vector2) -> void:
	_damage = max(1, damage)
	_origin = origin


func _ready() -> void:
	global_position = _origin
	z_index = 50
	# Additive blend so the overlapping rings read as a bright energy wave.
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m


func _process(delta: float) -> void:
	_radius += SPEED * delta
	_sweep()
	queue_redraw()
	if _radius >= MAX_RADIUS:
		queue_free()


func _sweep() -> void:
	var tree := get_tree()
	if tree == null:
		return
	# Damage every enemy the leading edge has newly reached. Missiles/rockets are
	# PROJECTILES, not combatants — destroy them on contact instead of running them
	# through the enemy damage path (Roman 2026-06-08).
	for e in tree.get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e):
			continue
		if e is BaseMissileC:
			if e.global_position.distance_to(global_position) <= _radius:
				_destroy_missile(e)
			continue
		var id: int = e.get_instance_id()
		if _hit.has(id):
			continue
		if e.global_position.distance_to(global_position) <= _radius:
			_hit[id] = true
			_damage_enemy(e)
	# Cancel projectiles inside the wave: enemy bullets (queue_free) + any missile/rocket
	# that's tagged into "bullets" too. Missiles already handled in the enemies pass above,
	# so skip BaseMissile here to avoid a double pop.
	for b in tree.get_nodes_in_group("bullets"):
		if b == null or not is_instance_valid(b) or b is BaseMissileC:
			continue
		if b.global_position.distance_to(global_position) <= _radius:
			b.queue_free()


func _damage_enemy(e) -> void:
	# Off-screen / recycling enemies aren't valid targets — the panic bomb clears what's ON screen,
	# not an enemy mid-parallax-flyback or already gone off an edge (Roman 2026-06-10).
	if e.has_method("is_recycling") and e.is_recycling():
		return
	if e.has_method("is_fully_offscreen") and e.is_fully_offscreen():
		return
	# Bosses: bite via the normal path so phase/shield gates fire correctly.
	var path: String = String(e.scene_file_path) if "scene_file_path" in e else ""
	if path.find("boss") != -1:
		if e.has_method("take_hit"):
			e.take_hit(_damage)
		return
	# POOL shield (sapper banked-steal, ShieldComponent.Mode.POOL): the wave does NOT
	# auto-strip it. It chews the banked damage pool and deals only the remainder to hull,
	# bypassing the enemy's take_hit so the sapper's "redirect damage to the player" never
	# fires for a panic bomb. Net: a well-fed sapper (pool >= our damage) survives; a
	# starved one dies. (No POOL shields exist until the sapper migration lands — forward
	# compatible; see docs/shield_unification_2026-06-08.md.)
	var pool = _find_pool_shield(e)
	if pool != null:
		var remainder: int = int(pool.on_hit(e, _damage))
		if remainder > 0:
			_deal_hull(e, remainder)
		return
	# Everyone else: deal damage straight to HULL, bypassing take_hit. This is what makes the
	# bomb IGNORE SHIELDS — a CHARGE ShieldComponent (corporate / bulwark / mine / chaff /
	# sector) is never consumed because the hit never reaches the component pipeline. The
	# normal death pipeline (explode -> bounty + VFX) still runs when it's fatal.
	# (Previously this stripped _charges then routed through take_hit; bypassing entirely is
	# robust against any shield variant — fixes the post-unification corpo-shield regression.)
	_deal_hull(e, _damage)


# Destroy a missile/rocket the wave swept over — a small pop, then free. They're 1-HP
# ordnance, so the bomb clears them outright rather than damaging them as combatants.
func _destroy_missile(m) -> void:
	if not is_instance_valid(m):
		return
	ExplosionFx.play(m.global_position, 0.4, false, null, null, false)  # silent — smart bomb has its own detonation SFX
	m.queue_free()


# A ShieldComponent in POOL mode (the sapper's banked-steal shield), or null.
func _find_pool_shield(e):
	if "_components" in e and e._components is Array:
		for comp in e._components:
			if comp != null and comp.has_method("is_pool") and comp.is_pool():
				return comp
	return null


# Deal damage straight to hull, bypassing take_hit (and thus any bespoke take_hit
# redirect), running the normal death pipeline if it's fatal.
func _deal_hull(e, dmg: int) -> void:
	if "health" in e:
		e.health -= dmg
		if "max_health" in e and e.has_signal("health_changed"):
			e.health_changed.emit(e.health, e.max_health)
		if e.health < 1 and e.has_method("explode"):
			e.explode()
	elif e.has_method("take_hit"):
		e.take_hit(dmg)


func _draw() -> void:
	var fade: float = clampf(1.0 - _radius / MAX_RADIUS, 0.0, 1.0)
	if fade <= 0.0:
		return
	# Faint pressure fill behind the rings.
	draw_circle(Vector2.ZERO, _radius, Color(0.40, 0.70, 1.0, 0.06 * fade))
	# Softer trailing ring just inside the leading edge.
	if _radius > 10.0:
		draw_arc(Vector2.ZERO, _radius - 7.0, 0.0, TAU, 96, Color(0.50, 0.80, 1.0, 0.5 * fade), 6.0, true)
	# Bright leading edge.
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 96, Color(0.85, 0.95, 1.0, 0.9 * fade), 3.0, true)

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

const ClarityRules = preload("res://scripts/clarity.gd")

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
	# Damage every enemy the leading edge has newly reached.
	for e in tree.get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e):
			continue
		var id: int = e.get_instance_id()
		if _hit.has(id):
			continue
		if e.global_position.distance_to(global_position) <= _radius:
			_hit[id] = true
			_damage_enemy(e)
	# Cancel enemy bullets inside the wave.
	for b in tree.get_nodes_in_group("bullets"):
		if b != null and is_instance_valid(b):
			if b.global_position.distance_to(global_position) <= _radius:
				b.queue_free()


func _damage_enemy(e) -> void:
	# Bosses: bite via the normal path so phase/shield gates fire correctly.
	var path: String = String(e.scene_file_path) if "scene_file_path" in e else ""
	if path.find("boss") != -1:
		if e.has_method("take_hit"):
			e.take_hit(_damage)
		return
	# Non-boss: strip shields, then deal full damage through take_hit so hull/
	# health bookkeeping + death VFX + bounty run normally for every enemy kind.
	# Simple per-pip shield (chaff `max_shield`):
	if "shield" in e:
		e.shield = 0
	# Charge-shields (ShieldComponent: corporate faction, bulwark, sapper, and the
	# universal crystal in corporate levels). The damage pipeline reads the per-instance
	# RUNTIME array `_components` (enemy_base dups the authored `components` template into
	# it in _ready), so zeroing `components` alone was a no-op — the live shield kept its
	# charges and absorbed the bomb. Zero `_charges` on every ShieldComponent in the
	# runtime array (and the template, harmless) so the wave truly ignores shields.
	for arr_name in ["_components", "components"]:
		if arr_name in e and e.get(arr_name) is Array:
			for comp in e.get(arr_name):
				if comp != null and "_charges" in comp:
					comp._charges = 0
	if e.has_method("take_hit"):
		e.take_hit(_damage)


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

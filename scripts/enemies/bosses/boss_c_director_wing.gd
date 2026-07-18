extends "res://scripts/enemies/bosses/boss_part.gd"

# WING CANNON behaviour for the Corporate Director. The wing cannons are AUTHORED sub-scene instances
# (boss_c_director_wingcannon.tscn) placed under the boss Body; Roman ships them SCRIPT-LESS on purpose
# (template shells with a Body sprite, a capsule hitbox, and a Muzzle marker), so the Director attaches
# THIS script at runtime (set_script + init_wing) — see boss_c_director._build_wing_cannons.
#
# It makes each a destructible 100hp emplacement (extends boss_part → take_hit / hp) that fires a thin
# CORPO BeamEmitter out its muzzle (1px white core + teal + blue outer layers, HDR) and gates the
# Director's Laser Lane maneuver. On death (Roman 2026-07-07) it STOPS firing + HIDES the live cannon +
# goes non-hittable; the Director then reveals the matching body-mounted DestroyedL/R overlay sprite (the
# cannon art itself no longer swaps to a destroyed frame — the destroyed state is a separate body overlay).

const BeamEmitterC = preload("res://scripts/enemies/beam_emitter.gd")
const CORP_FACTION := 2   # Factions.Id.CORPORATE — the beam takes the corpo faction laser colour

var part_hp: int = 100
var _beam = null
var _built: bool = false


# Turn the script-less scene shell into a live wing part. Idempotent — the Director calls it after
# set_script(); _ready() also calls it (for standalone / scene-scripted use).
func init_wing(hp_val: int = 100) -> void:
	if _built:
		return
	_built = true
	part_hp = hp_val
	hp = hp_val
	max_hp = hp_val
	is_hazard = true
	leave_trail = false
	smart_bomb_cap = 20
	if not is_in_group("enemies"):
		add_to_group("enemies")
	_build_beam()


func _ready() -> void:
	init_wing(part_hp)


func _build_beam() -> void:
	_beam = BeamEmitterC.new()
	_beam.autostart = false
	_beam.target_group = "player"
	_beam.endpoint = BeamEmitterC.Endpoint.RAY
	_beam.aim_mode = BeamEmitterC.AimMode.LOCAL_FORWARD   # fires out the nose (local up) → down the lane when the boss faces the player
	_beam.forward_local = Vector2(0, -1)
	_beam.emitter_offset = _muzzle_local()               # emit from the authored barrel-tip marker
	_beam.faction = CORP_FACTION                         # BeamEmitter tints the outer layers to the corpo laser colour; core stays white
	_beam.sfx_profile = "boss"                           # large blasts + power flutters + field loops 4/5 (Roman 2026-07-15)
	_beam.telegraph_width = 1.5                          # (telegraph colour auto-derives from the faction hue)
	_beam.envelope = true                                # grow-in thin→full, shrink+flicker out
	_beam.cycle = BeamEmitterC.Cycle.LOOP_WINDUP
	_beam.idle_time = 0.2
	_beam.windup_time = 0.9
	_beam.firing_time = 2.2
	_beam.cooldown_time = 1.0
	_beam.reach = 540.0
	_beam.dps = 3.0
	_beam.hit_radius = 6.0
	# A thin beam: widths widest→narrowest, alphas kept by the faction tint (soft outer glow, bright core).
	_beam.layers = [
		{"width": 3.0, "color": Color(1, 1, 1, 0.35)},
		{"width": 2.0, "color": Color(1, 1, 1, 0.7)},
		{"width": 1.0, "color": Color(1, 1, 1, 1)},
	]
	add_child(_beam)


# The authored Muzzle marker's offset in THIS part's local frame (the Body sprite is offset in the scene,
# so sum the local transform chain). Falls back to a barrel-tip default.
func _muzzle_local() -> Vector2:
	var m := find_child("Muzzle*", true, false) as Node2D
	if m == null:
		return Vector2(0, -16)
	var off: Vector2 = m.position
	var p: Node = m.get_parent()
	while p != null and p != self and p is Node2D:
		off += (p as Node2D).position
		p = p.get_parent()
	return off


func set_active(on: bool) -> void:
	if _destroyed or _beam == null or not is_instance_valid(_beam):
		return
	if on:
		_beam.begin()
	else:
		_beam.fade_out()   # graceful shrink+flicker OUT (matches the lane laser), not a hard cut


func is_destroyed() -> bool:
	return _destroyed


# Death: stop firing + HIDE the live cannon + go non-hittable, blast once, notify the boss (which reveals
# the body's DestroyedL/R overlay). NOT freed — a hidden husk the boss frees on its own death.
func destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	if _beam != null and is_instance_valid(_beam):
		_beam.stop()
	set_deferred("monitorable", false)
	visible = false
	part_destroyed.emit(self)   # the Director reveals the DestroyedCannon overlay + plays instakill+blowout


# The sub-scene may ship MoveTimer/ShootTimer wired to these (enemy-template leftovers); stubs so the
# .tscn timeout connections resolve once the script is attached.
func _on_timer_timeout() -> void:
	pass


func _on_shoot_timer_timeout() -> void:
	pass

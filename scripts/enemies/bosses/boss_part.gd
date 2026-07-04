extends Area2D

# Reusable DESTRUCTIBLE BOSS PART (turret / pod / arm / weak-point), the
# standardized generalization of conductor_satellite.gd. Owns its own HP, takes
# hits from player fire, and on death plays an explosion, optionally leaves a
# burning trail at its mount, emits part_destroyed, and frees itself.
#
# Path-based (no class_name), mirroring boss_base — bosses reference it via
# preload. A part is a child of the boss (often parented to a Marker2D mount) so
# it rides the hull. It joins "enemies" so player bullets collide, but is flagged
# is_hazard so it does NOT gate wave-clear on its own (the boss is the combatant);
# the boss frees surviving parts on death via BossBase.free_parts().
#
# A part is purely the destructible shell + VFX. Any behaviour (a turret's barrel
# aim/fire) is layered on top by the boss / a coordinator — see boss_shepherd.gd.

signal part_destroyed(part)

const ShipDamageTellsC = preload("res://scripts/effects/ship_damage_tells.gd")

var hp: int = 30
var max_hp: int = 30
var boss_ref: Node2D = null
var is_hazard: bool = true          # don't gate wave-clear (boss is the combatant)
# Leave a persistent burning/smoke trail at the mount on death. `trail_fall` adds
# downward drift so it reads as motion while the boss holds + jiggles (per spec).
var leave_trail: bool = true
var trail_fall: float = 40.0
# Opt-in progressive damage tells (Roman 2026-07-01): the damage-noise overlay ramps as HP drops and a
# spark trail lights at `damage_tell_spark_start` fraction of lost HP. Set BEFORE _ready(). The battleship
# turrets + lasers use it; default off keeps the Shepherd's parts unchanged. `_tells` is capped below 1.0
# so it never runs its own disintegrate — the part's destroy() owns death.
var wants_damage_tells: bool = false
var damage_tell_spark_start: float = 0.5
var _tells = null
# Smart-bomb resistance (Roman 2026-07-01): a smart-bomb shockwave hits via take_smart_bomb(); the part
# takes at most this many HP (so it isn't one-shot). -1 = no cap (normal full damage, e.g. the Shepherd).
var smart_bomb_cap: int = -1

var _destroyed: bool = false


func _ready() -> void:
	add_to_group("enemies")
	if wants_damage_tells:
		_install_damage_tells()


# Attach a ShipDamageTells driver on this part's sprite (self_explode=false — destroy() owns death).
# Sparks light at 50% lost HP by default; a single burning trail near death. No-op if there's no sprite.
func _install_damage_tells() -> void:
	var spr := _first_sprite(self)
	if spr == null:
		return
	_tells = ShipDamageTellsC.new()
	_tells.self_explode = false
	add_child(_tells)
	_tells.setup(self, spr, 1.0, {
		"spark_start": damage_tell_spark_start,
		"burn_threshold": 0.8, "burn_trails": 1.0, "torch_lead": 0.0, "spark_amount": 24.0,
	})


# Configure on spawn. `host` is the boss (for find_player fallbacks + cleanup).
func setup(host: Node2D, part_hp: int) -> void:
	boss_ref = host
	hp = part_hp
	max_hp = part_hp


# Smart-bomb entry point (smart_bomb_shockwave calls this if present). Caps the damage so a boss part
# takes DECENT-but-survivable damage from a panic bomb instead of being one-shot. `smart_bomb_cap` < 0
# means no cap (full damage). Routes through take_hit so death/VFX/tracking all fire normally.
func take_smart_bomb(damage: int) -> bool:
	var d: int = damage if smart_bomb_cap < 0 else mini(damage, smart_bomb_cap)
	return take_hit(d)


# Player-fire entry point (matches the EnemyBase contract bullets call).
func take_hit(damage: int = 1) -> bool:
	if _destroyed:
		return false
	hp -= damage
	_flash()
	# Drive the damage tells (overlay + sparks), capped below 1.0 so they never self-destruct — the
	# part's own destroy() owns death.
	if _tells != null and is_instance_valid(_tells):
		_tells.set_damage(clampf(1.0 - float(hp) / float(maxi(1, max_hp)), 0.0, 0.99))
	if hp <= 0:
		destroy()
		return true
	return false


# Blow the part: explosion at its position, optional burning trail at the mount,
# notify the boss, free. Idempotent.
func destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	if _tells != null and is_instance_valid(_tells):
		_tells.quiet()   # stop the overlay/spark tells; death VFX below (or a subclass override) takes over
	var tree := get_tree()
	var scene: Node = tree.current_scene if tree != null else null
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	if ExplosionFx != null:
		# "Small circle explode" (Shepherd brief). scene defaults to current_scene.
		ExplosionFx.play(global_position, 0.8, false, scene, ExplosionFx.scene_for("small_circle"))
	if leave_trail:
		_spawn_burn_trail()
	part_destroyed.emit(self)
	queue_free()


# White hit flash on the part's first Sprite2D. Recurses so a barrel nested under a firing node (e.g.
# an EnemyTurret child, as the battleship builds them) still flashes; a direct-child barrel (the
# Shepherd's boss_turret_part) is found first, so that path is unchanged.
func _flash() -> void:
	var spr := _first_sprite(self)
	if spr != null:
		var HitFlashFx = load("res://scripts/effects/hit_flash_fx.gd")
		HitFlashFx.flash(spr, HitFlashFx.FLASH_WHITE)


func _first_sprite(n: Node) -> Sprite2D:
	for c in n.get_children():
		if c is Sprite2D:
			return c as Sprite2D
		var found := _first_sprite(c)
		if found != null:
			return found
	return null


# Persistent burning trail at the mount (the parent Marker2D rides the boss, so
# the trail follows the hull). Downward gravity sells "the wrecked mount streams
# smoke as the ship drifts." Auto-frees after a few seconds.
func _spawn_burn_trail() -> void:
	var mount: Node = get_parent()
	if mount == null or not (mount is Node2D):
		return
	var p := CPUParticles2D.new()
	p.amount = 18
	p.lifetime = 0.8
	p.one_shot = false
	p.explosiveness = 0.0
	p.spread = 25.0
	p.direction = Vector2(0, 1)
	p.gravity = Vector2(0, trail_fall)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 22.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = Color(1.0, 0.55, 0.2, 0.9)
	(mount as Node2D).add_child(p)
	# Fade the emission out and free so the wreck-smoke doesn't last forever.
	var tree := get_tree()
	if tree != null:
		tree.create_timer(4.0, false).timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.emitting = false
				var t2 := p.get_tree()
				if t2 != null:
					t2.create_timer(1.0, false).timeout.connect(func() -> void:
						if is_instance_valid(p):
							p.queue_free()))

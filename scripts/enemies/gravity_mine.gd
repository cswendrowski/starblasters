extends "res://scripts/enemies/enemy_core.gd"

# Gravity Mine (Roman 2026-06-09) — drifts down like any mine, ringed by 4/6/8 real Bomblets slowly
# orbiting it (CW or CCW). The bomblets are hittable + killable on their own; on the mine's death (or
# off-screen exit) the survivors are RELEASED, inheriting the mine's drift PLUS the tangential
# velocity of their orbit. Same hull as the Armored Mine (4 HP). Carries the #c73bff gravity glow +
# the shared red centre blink.
#
# The orbit + release is the shared OrbitComponent (LIVE mode) now — was bespoke (2026-06-19). The
# mine just owns its hull / glow / blink / mine-death VFX; "rings of bomblets" is config.

const StraightDown = preload("res://scripts/enemies/patterns/straight_down.gd")
const GravityGlow = preload("res://scripts/effects/gravity_glow.gd")
const MineBlinker = preload("res://scripts/effects/mine_blinker.gd")
const BombletScene = preload("res://scenes/enemies/enemy_bomblet.tscn")
const OrbitComponentC = preload("res://scripts/enemies/components/orbit_component.gd")

@export var drift_speed: float = 100.0
@export var damage_on_collide: int = 2
@export var hull_hp: int = 4                       # same as the Armored Mine
@export var orbit_radius: float = 18.0
@export var orbit_tangential_speed: float = 60.0   # 1 px/f


func _ready() -> void:
	max_health = hull_hp
	is_hazard = true
	bounty_value = 0
	# Ordnance Disposal Condition (grant.mine_bounty) + events (mine_bonus_bounty)
	# both raise per-mine bounty; additive so they STACK (design §4f). Mirror of the
	# asteroid_bonus_bounty path in asteroid.gd.
	if has_node("/root/Run"):
		var _run = get_node("/root/Run")
		bounty_value += int(_run.mine_bonus_bounty) + int(_run.cond_sum("grant.mine_bounty"))
	display_scale = 1.0
	auto_rotate = false
	has_ship_vfx = false
	recycle_passes = 0
	if has_node("Sprite2D"):
		$Sprite2D.frame = 0
	# Descent = chassis move_speed (StraightDown reads it). Seed from the authored drift_speed when
	# unset so the BODY descends at the written 100 instead of the pattern's 180 fallback — and so the
	# orbit host_drift below matches the body (they were mismatched). Handed move_speed wins.
	# (Roman 2026-07-02 speed-source pass, option B.)
	if move_speed <= 0.0:
		move_speed = drift_speed
	if movement == null:
		var m := StraightDown.new()
		movement = m
	# Orbiting bomblets via the shared OrbitComponent (LIVE) — set BEFORE super._ready so enemy_core
	# inits + ticks it. One ring of 4/6/8 bomblets, spinning CW or CCW; released on death/exit by the
	# component (on_death / on_leave) with the mine drift + their tangential orbit velocity.
	var oc = OrbitComponentC.new()
	oc.mode = OrbitComponentC.Mode.LIVE
	oc.host_drift = move_speed   # match the body's actual descent (seeded from drift_speed above)
	var dir: float = 1.0 if randf() < 0.5 else -1.0
	var n: int = [4, 6, 8][randi() % 3]
	var omega: float = orbit_tangential_speed / maxf(orbit_radius, 1.0) * dir
	oc.rings = [{"radius": orbit_radius, "count": n, "speed": omega, "scene": BombletScene}]
	components = [oc]
	super._ready()
	# #c73bff gravity glow (glowmask frame, always on) + the shared red centre blink.
	if has_node("Sprite2D"):
		var g := GravityGlow.new()
		add_child(g)
		g.setup($Sprite2D)
	add_child(MineBlinker.new())


func hit() -> void:
	if has_node("ParticleHit"):
		$ParticleHit.restart()


func explode() -> void:
	if _dying:
		return
	_components_death()   # release the orbiting bomblets (OrbitComponent.on_death)
	_dying = true
	set_deferred("monitorable", false)
	died.emit(bounty_value)
	_fade_death_overlays()   # drop glow-mask / gravity glow / outline / centre-blink instantly
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	ExplosionFx.burst(global_position, 2, 8.0, 0.05)
	var MineSfx = load("res://scripts/effects/mine_sfx.gd")
	MineSfx.play_at(global_position)
	if has_node("Sprite2D"):
		var BurnFx = load("res://scripts/effects/burn_fx.gd")
		BurnFx.apply_burn($Sprite2D, 0.4)
	await get_tree().create_timer(0.45).timeout
	queue_free()


# Catch-all: if the mine is freed for ANY reason (off-screen, level wipe), don't strand the
# orbiting bomblets frozen in space — the component releases them so they drift + despawn normally.
func _exit_tree() -> void:
	_components_leave()


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("take_damage") and "hull" in area:
		area.take_damage(damage_on_collide)
		explode()

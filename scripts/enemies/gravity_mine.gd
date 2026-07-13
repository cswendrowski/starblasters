extends "res://scripts/enemies/mine_base.gd"

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
	bounty_value = 0
	# Shared hazard flags + Ordnance-Disposal bounty bonus land in mine_base.super._ready() (below).
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
	# Release the orbiting bomblets via the pre-dying callback (must happen before _dying flag is set
	# so the OrbitComponent.on_death logic runs cleanly). The helper handles the common skeleton.
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	await _mine_explode_sequence(
		func(): ExplosionFx.burst(global_position, 2, 8.0, 0.05),
		func(): _components_death()   # pre-dying: release the orbiting bomblets (OrbitComponent.on_death)
	)


# Catch-all: if the mine is freed for ANY reason (off-screen, level wipe), don't strand the
# orbiting bomblets frozen in space — the component releases them so they drift + despawn normally.
func _exit_tree() -> void:
	_components_leave()


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("take_damage") and "hull" in area:
		area.take_damage(damage_on_collide)
		explode()

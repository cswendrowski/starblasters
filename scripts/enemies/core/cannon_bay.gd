extends "res://scripts/enemies/core/enemy_core_building_turret.gd"

# Cannon Bay (Roman 2026-07-28) — a ground turret that DEPLOYS before it can fight, instead of
# arriving armed like every other structure. Three phases, then it fires:
#
#   CLOSED -> COVER  : the 7-frame "Cover" door strip steps open (frame 0 -> 6).
#   COVER  -> RAISE  : the "Cannon" group fades in + grows to 1.0 scale, THEN slides its offset to 0
#                      as it moves forward into firing position.
#   RAISE  -> READY  : mounts un-hold and it starts shooting.
#
# Two gates ride the phase, and they are deliberately NOT the same gate:
#   * VULNERABILITY opens at RAISE_VULNERABLE_FRAC (halfway through the raise). Closed and
#     door-opening, it is not a valid target at all — take_hit returns false, the same contract
#     enemy_base already uses for recycling / off-screen enemies (no hit flash, no accuracy credit).
#   * FIRING opens only at READY, via the _on_playfield() override — MountComponent._held already
#     consults that method, so every mount holds fire for free with no mount-system change.
#
# Per-shot presentation (on_mount_fired, called from MountComponent._finish_shot):
#   barrel recoils RECOIL_PX back along its own axis and slides home, a large muzzle flash at Muzzle1
#   (the weapon's own flash, scaled up via muzzle_flash_scale), two small flashes of the same style at
#   FlareL/FlareR, and a large brass casing ejected BACKWARD from the Ejection marker.
#
# A bespoke script is justified here per the enemy convention: a multi-phase deploy state machine with
# distinct vulnerability and firing gates cannot be expressed as a movement/shoot pattern resource.

const MuzzleFxC = preload("res://scripts/effects/muzzle_fx.gd")

# --- Deploy timing (seconds) ---
const COVER_FRAME_TIME: float = 0.06    # per door frame; 7 frames = 0.42s total
const RAISE_GROW_TIME: float = 0.35     # fade in + scale up
const RAISE_SLIDE_TIME: float = 0.25    # then move forward into position
const DEPLOY_START_DELAY: float = 0.35  # beat after spawn before the doors start, so it reads

# Fraction through the WHOLE raise (grow + slide) at which the tower becomes shootable.
const RAISE_VULNERABLE_FRAC: float = 0.5

# --- Cannon start state ---
# The SCENE authors the start pose — `Cannon.scale` (0.9) and `Cannon.position` (0, 6) are Roman's
# values and are read, never overwritten; the deploy drives them to 1.0 / y=0. Only alpha is forced,
# since "starts hidden then fades in" can't be authored as visible-but-transparent without the
# editor showing an invisible node.
const START_ALPHA: float = 0.0

# --- Firing presentation ---
const RECOIL_PX: float = 5.0            # barrel slides back along -forward
const RECOIL_OUT_TIME: float = 0.05
const RECOIL_IN_TIME: float = 0.12
const FLASH_SCALE_MAIN: float = 2.0     # large forward flash
const FLASH_SCALE_SIDE: float = 0.6     # the two smaller L/R flares
const CASING_SPEED_MIN: float = 90.0
const CASING_SPEED_MAX: float = 140.0

enum Phase { CLOSED, COVER, RAISE, READY }

var _phase: int = Phase.CLOSED
var _vulnerable: bool = false
var _cannon: Node2D = null
var _barrel: Node2D = null
var _cover: Sprite2D = null
var _cannon_home := Vector2.ZERO   # authored resting offset of the Cannon group (target of the slide)
var _barrel_home := Vector2.ZERO
var _recoil_tw: Tween = null


func _ready() -> void:
	# Cache + force the closed start state BEFORE super._ready(), so the shadow rig and livery pass
	# bind to layers that are already in their deploy-start pose (and nothing pops on frame 1).
	_cover = get_node_or_null("Cover") as Sprite2D
	_cannon = get_node_or_null("Cannon") as Node2D
	if _cannon != null:
		_barrel = _cannon.get_node_or_null("Tower/Barrel") as Node2D
		# The scene authors the group at its OFFSET start (position.y = 6); the deploy target is y=0.
		# Authored scale is left exactly as-is — it IS the start pose.
		_cannon_home = Vector2(_cannon.position.x, 0.0)
		_cannon.modulate.a = START_ALPHA
		_cannon.visible = false
	if _barrel != null:
		_barrel_home = _barrel.position
	if _cover != null:
		_cover.frame = 0
	super._ready()
	_deploy()


# ---------------------------------------------------------------- deploy sequence

func _deploy() -> void:
	if _phase != Phase.CLOSED:
		return
	await get_tree().create_timer(DEPLOY_START_DELAY, false).timeout
	if not is_instance_valid(self) or _husk:
		return
	await _run_cover()
	if not is_instance_valid(self) or _husk:
		return
	await _run_raise()
	if not is_instance_valid(self) or _husk:
		return
	_phase = Phase.READY   # mounts un-hold via _on_playfield


# Step the 7-frame door strip. Frame count comes from the sprite so re-cutting the art needs no edit.
func _run_cover() -> void:
	_phase = Phase.COVER
	if _cover == null:
		return
	var frames: int = maxi(1, _cover.hframes)
	for i in range(1, frames):
		await get_tree().create_timer(COVER_FRAME_TIME, false).timeout
		if not is_instance_valid(self) or _husk:
			return
		_cover.frame = i


# Fade in + grow to full scale, THEN slide forward to offset 0. Vulnerability opens partway through
# the combined duration (RAISE_VULNERABLE_FRAC), not at either sub-step's boundary.
func _run_raise() -> void:
	_phase = Phase.RAISE
	if _cannon == null:
		_vulnerable = true
		return
	_cannon.visible = true
	var total: float = RAISE_GROW_TIME + RAISE_SLIDE_TIME
	_arm_vulnerability(total * RAISE_VULNERABLE_FRAC)
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_cannon, "modulate:a", 1.0, RAISE_GROW_TIME)
	tw.tween_property(_cannon, "scale", Vector2.ONE, RAISE_GROW_TIME)
	await tw.finished
	if not is_instance_valid(self) or _husk:
		return
	var tw2: Tween = create_tween()
	tw2.tween_property(_cannon, "position", _cannon_home, RAISE_SLIDE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw2.finished


func _arm_vulnerability(delay: float) -> void:
	await get_tree().create_timer(maxf(0.0, delay), false).timeout
	if is_instance_valid(self) and not _husk:
		_vulnerable = true


# ---------------------------------------------------------------- gates

# Not a valid target until the tower is halfway up. Mirrors enemy_base.take_hit's existing
# recycling / fully-offscreen contract: return false BEFORE the hit flash and the shots_hit credit,
# so a shot into a closed bay neither lights it up nor counts as an accuracy hit.
func take_hit(damage: int = 1) -> bool:
	if not _vulnerable:
		return false
	return super.take_hit(damage)


# Firing gate. MountComponent._held() calls this when the host defines it, so returning false holds
# EVERY mount with no mount-system change. AND-ed with the base check so the normal off-playfield
# suppression still applies once deployed.
func _on_playfield() -> bool:
	if _phase != Phase.READY:
		return false
	return super._on_playfield()


# Scale for the weapon's own muzzle flash at the mount marker (read by shoot_pattern._spawn_bullet).
# This IS the large forward flash — the host does not add a second one at Muzzle1.
func muzzle_flash_scale() -> float:
	return FLASH_SCALE_MAIN


# ---------------------------------------------------------------- per-shot presentation

# Called once per spawned shot by MountComponent._finish_shot (duck-typed, so nothing else is
# affected). `dir` is the shot's world direction; the large flash at the muzzle is already handled by
# the weapon, so this adds the side flares, the recoil, and the ejected casing.
func on_mount_fired(dir: Vector2, _muzzle_pos: Vector2) -> void:
	if _husk or _phase != Phase.READY:
		return
	_side_flares(dir)
	_eject_casing(dir)
	_recoil(dir)


func _side_flares(dir: Vector2) -> void:
	var root: Node = _fx_parent()
	for n in ["FlareL", "FlareR"]:
		var m := find_child(n, true, false)
		if m is Node2D:
			MuzzleFxC.play_enemy((m as Node2D).global_position, dir, root, FLASH_SCALE_SIDE)


# Large brass casing, thrown BACKWARD out of the Ejection port (opposite the shot).
func _eject_casing(dir: Vector2) -> void:
	var m := find_child("Ejection", true, false)
	if not (m is Node2D):
		return
	var back: Vector2 = (-dir).normalized() if dir.length() > 0.01 else Vector2.DOWN
	MuzzleFxC.eject_casing_dir(_fx_parent(), (m as Node2D).global_position,
		back * randf_range(CASING_SPEED_MIN, CASING_SPEED_MAX), true)


# Barrel kicks back along its own axis, then slides home. Local-space so it tracks the barrel's
# rotation; killing the prior tween keeps a fast cadence from stacking offsets.
func _recoil(_dir: Vector2) -> void:
	if _barrel == null:
		return
	if _recoil_tw != null and _recoil_tw.is_valid():
		_recoil_tw.kill()
		_barrel.position = _barrel_home
	# The barrel sprite points along local -Y, so recoil is +Y (back down the barrel).
	var back: Vector2 = _barrel_home + Vector2(0.0, RECOIL_PX)
	_recoil_tw = create_tween()
	_recoil_tw.tween_property(_barrel, "position", back, RECOIL_OUT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tw.tween_property(_barrel, "position", _barrel_home, RECOIL_IN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ---------------------------------------------------------------- death

# A bay killed mid-deploy must stop deploying: the awaits above all bail on _husk, and the recoil
# tween is killed so a dying barrel doesn't keep sliding.
func explode() -> void:
	if _recoil_tw != null and _recoil_tw.is_valid():
		_recoil_tw.kill()
	super.explode()

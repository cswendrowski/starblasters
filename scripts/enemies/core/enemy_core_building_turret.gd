extends "res://scripts/enemies/enemy_core.gd"

# Ground structures — buildings + turrets (Roman 2026-07-12). They drift down the lane like an asteroid
# (LateralDrift movement) and carry NO ship VFX: no damage-tell overlay/spiral, no engine trail, no
# parallax shadow, and no styled spin-out / wreck death. A weapon, if any, is a hardpoint from the
# roster (GUN muzzles on the diamond turret, a rotating TURRET on the turret / launcher); the plain
# buildings have none — "won't shoot".
#
# Death = EXPLODE WITH DEBRIS, then leave the base as an inert husk:
#   - a random explosion type + a debris scatter at the structure,
#   - the ROTATING turret layer (an EnemyTurret, if this structure has one) is destroyed + removed,
#   - the intact overlays (Building / GlowMuzzle) hide and the "Destroyed" frame shows,
#   - the base keeps drifting with collision OFF (bullets AND the player pass through), freed once it
#     clears the bottom of the screen.

const EnemyDeathFxC = preload("res://scripts/effects/enemy_death_fx.gd")

var _husk: bool = false   # true once destroyed — the base is now inert, drifting debris


func _ready() -> void:
	# Structures aren't ships: no damage-tell overlay/spiral, engine trail, or parallax shadow, and the
	# styled/wreck death is skipped (explode() below is fully overridden anyway). Set before super._ready
	# so the vfx gating reads it.
	has_ship_vfx = false
	# Never recycle (Roman 2026-07-13): a ground structure that drifts off-screen must despawn, not fly
	# back through the parallax. recycle_passes == 0 makes RecycleController._leave() instead of cycling.
	recycle_passes = 0
	super._ready()


func _process(delta: float) -> void:
	if _husk:
		# Inert base husk: keep drifting via the same pattern (no firing / components / auto-rotate), and
		# free it once it clears the bottom (RecycleController is bypassed — a husk never recycles).
		var sd: float = min(delta, 1.0 / 30.0)
		if _pattern != null and not _cycling:
			position += _pattern.compute_step(self, sd)
		if global_position.y > screensize.y + 48.0:
			queue_free()
		return
	super._process(delta)


func explode() -> void:
	if _husk or _dying:
		return
	_husk = true
	# Credit the bounty + fire component death hooks (faction drops), but DO NOT run the hull's styled
	# spin-out / classic hull death — the base survives.
	died.emit(bounty_value)
	_components_death()
	# The rotating turret layer (if any) is destroyed + removed first.
	var tur := _find_turret(self)
	if tur != null and is_instance_valid(tur):
		tur.queue_free()
	# EXPLODE (Roman 2026-07-14): route the death through the classic blast VFX — a size-scaled MULTI-blast
	# burst + settling dust + debris (honoring explosion_variant), NEVER a stretched sprite. This is the
	# ONLY death VFX: a structure is a stationary emplacement, so it gets no styled spin-out / drifting
	# wreck. Size the blast to the structure's own footprint so a big building erupts big even when spawned
	# directly (display_scale left at 1 by a non-director spawn path).
	display_scale = maxf(display_scale, _structure_heft())
	EnemyDeathFxC.classic(self, _fx_parent())
	# Base → Destroyed look (hide the intact overlays, show the "Destroyed" frame) + inert drifting husk.
	_hide_layer("Building")
	_hide_layer("GlowMuzzle")
	var d := find_child("Destroyed", true, false)
	if d != null and d is CanvasItem:
		(d as CanvasItem).visible = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	remove_from_group("enemies")


# Blast heft for the death explosion. A structure is a dense emplacement, not a fighter, so it always
# erupts with a MULTI-blast burst (floor 2.0 ≈ 3 blasts) regardless of its small pixel-art footprint, and
# scales up for genuinely large sprites. Combined with display_scale in explode() so a director-scaled
# (huge/giant) spawn erupts even bigger. Feeds classic()'s size-scaled blast count. 16px→3, 48px→4, 64px+→6.
func _structure_heft() -> float:
	var px: float = 16.0
	for n in find_children("*", "Sprite2D", true, false):
		var sp: Sprite2D = n
		if sp.texture == null or not sp.visible:
			continue
		var fw: float = float(sp.texture.get_width()) / float(maxi(1, sp.hframes))
		var fh: float = float(sp.texture.get_height()) / float(maxi(1, sp.vframes))
		px = maxf(px, maxf(fw, fh) * maxf(sp.scale.x, 0.01))
	return clampf(px / 16.0, 2.0, 4.0)


func _hide_layer(layer_name: String) -> void:
	var n := find_child(layer_name, true, false)
	if n != null and n is CanvasItem:
		(n as CanvasItem).visible = false


# First EnemyTurret in the subtree (the mount attaches it under the "Turret" marker).
func _find_turret(n: Node) -> Node:
	for c in n.get_children():
		if c is EnemyTurret:
			return c
		var r := _find_turret(c)
		if r != null:
			return r
	return null

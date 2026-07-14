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

const ExplosionFxC = preload("res://scripts/effects/explosion_fx.gd")
const EnemyDeathFxC = preload("res://scripts/effects/enemy_death_fx.gd")
const RosterC = preload("res://scripts/levels/enemy_roster.gd")
const FactionsC = preload("res://scripts/levels/factions.gd")

## Whether the PLAYER takes contact damage from / rams this structure. Structures default to FALSE — the
## ship flies THROUGH them (they stay shootable, they're just not rammers). Set true per-scene to opt in.
## Read player-side in player._on_area_entered.
@export var player_impact: bool = false

var _husk: bool = false   # true once destroyed — the base is now inert, drifting debris


func _ready() -> void:
	# Structures aren't ships: no damage-tell overlay/spiral, engine trail, or parallax shadow, and the
	# styled/wreck death is skipped (explode() below is fully overridden anyway). Set before super._ready
	# so the vfx gating reads it.
	has_ship_vfx = false
	# Never recycle (Roman 2026-07-13): a ground structure that drifts off-screen must despawn, not fly
	# back through the parallax. recycle_passes == 0 makes RecycleController._leave() instead of cycling.
	recycle_passes = 0
	# no_wave structures spawn OUTSIDE the director/WaveGen path, so its size→HP scaling never runs and
	# max_health would stay at the scene default (1 → one-hit death). Derive HP from our own roster entry
	# (size + tough), BEFORE super._ready() initializes the hull from max_health.
	_apply_roster_health()
	super._ready()
	_apply_livery()   # tint a "Livery" layer with the level faction, if this structure carries one


# Tint a "Livery" decal layer with the active level faction's colour. no_wave structures spawn OUTSIDE the
# director's livery pass, so we apply it here (covers turrets + composed buildings alike). No active faction
# or no "Livery" node → keeps the scene default (apply_livery is a no-op without a Livery layer).
func _apply_livery() -> void:
	var run = get_node_or_null("/root/Run")
	if run == null or not run.has_meta("active_faction"):
		return
	var faction: int = int(run.get_meta("active_faction", -1))
	if faction < 0:
		return
	FactionsC.apply_livery(faction, self)


# Set max_health from this structure's own roster entry (size template × tough), so it isn't a one-hit
# kill when spawned directly. No-op if the scene isn't in the roster (keeps the scene default).
func _apply_roster_health() -> void:
	var entry: Dictionary = RosterC.entry_for_scene(scene_file_path)
	if entry.is_empty():
		return
	max_health = maxi(1, int(RosterC.compose_stats(entry).get("max_health", max_health)))


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
	# Blast origin: the rotating turret if there is one, else the structure centre. Capture BEFORE freeing.
	var tur := _find_turret(self)
	var at: Vector2 = (tur.global_position if (tur != null and is_instance_valid(tur)) else global_position)
	if tur != null and is_instance_valid(tur):
		tur.queue_free()   # the rotating turret layer is destroyed + removed
	# EXPLODE (Roman 2026-07-14): a size-scaled MULTI-blast burst + debris rendered at NORMAL z, so the
	# fireball reads OVER the drifting husk. (The classic death-VFX path sinks the blast to z -3 — it was
	# hiding behind the big opaque structure, so buildings looked like they didn't explode.) Explosions
	# stay 1x — only the blast COUNT + debris scale with heft. This is the ONLY death VFX: a stationary
	# emplacement gets NO styled spin-out / drifting wreck.
	var fx: Node = _fx_parent()
	var heft: float = maxf(display_scale, _structure_heft())
	var scn: PackedScene = ExplosionFxC.scene_for(explosion_variant)
	var blasts: int = clampi(int(round(heft * 1.4)), 2, 6)
	ExplosionFxC.burst(at, blasts, 12.0 * maxf(1.0, heft * 0.6), 0.06, fx, scn)
	EnemyDeathFxC.spawn_debris(fx, at, heft)
	# Swap in the destroyed look, then become an inert drifting husk. Subclasses override _show_destroyed_look
	# for a different look (composed_building.gd overlays damage decals on a SURVIVING building instead).
	_show_destroyed_look()
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	remove_from_group("enemies")


# The death look: hide the intact "Building"/"GlowMuzzle" overlays and reveal the "Destroyed" frame. Lift
# "Destroyed" out of any layer we hide first — on the square turret it's a child of "Building", so hiding
# Building would keep it invisible (a parent hides its children). Overridable (see composed_building.gd).
func _show_destroyed_look() -> void:
	var d := find_child("Destroyed", true, false)
	if d != null and d is Node2D and d.get_parent() != self:
		(d as Node2D).reparent(self, true)   # keep world transform; now a root sibling, unaffected by _hide_layer
	_hide_layer("Building")
	_hide_layer("GlowMuzzle")
	if d != null and d is CanvasItem:
		(d as CanvasItem).visible = true
		(d as CanvasItem).z_index = maxi((d as CanvasItem).z_index, 1)   # ensure it reads above the Base husk


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

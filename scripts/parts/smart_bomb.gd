extends "res://scripts/parts/part.gd"

const Slots = preload("res://scripts/weapons/SlotTypes.gd")

# Smart Bomb — DoDonPachi / Raiden classic super weapon. On activation:
#   - Cancel every enemy bullet on screen.
#   - Deal heavy damage to every enemy on screen (lethal to most chaff,
#     bites bosses for a chunk).
#   - Big radial VFX so the player feels the panic-button payoff.
#
# Limited charges per equipped instance — Mk scaling adds charges
# (Mk.1=3, +1 per Mk → Mk.9=11). Refilled at outposts (TODO: outpost
# integration not wired yet; for now charges reset per combat scene).

@export var base_charges: int = 3
@export var charges_per_mark: int = 1
# Damage dealt to each enemy on activation. High enough to one-shot most
# chaff; bosses take a noticeable but not screen-clearing hit.
@export var base_damage: int = 25
@export var dmg_per_mark: int = 10


func _init() -> void:
	slot_type = Slots.SlotType.DEVICE_BAY_1
	display_name = "Smart Bomb"
	description = "Screen clear + heavy damage. Limited charges, refill at outposts."


func apply(ship) -> void:
	if not ("super_part" in ship):
		return
	ship.super_part = self
	ship.max_super_charges = _charges_at_mark(int(mark))
	ship.super_charges = ship.max_super_charges
	if ship.has_signal("super_charges_changed"):
		ship.super_charges_changed.emit(ship.super_charges, ship.max_super_charges)


func unapply(ship) -> void:
	if not ("super_part" in ship):
		return
	if ship.super_part == self:
		ship.super_part = null
		ship.super_charges = 0
		if ship.has_signal("super_charges_changed"):
			ship.super_charges_changed.emit(0, 0)


# Drive the screen clear + enemy-damage burst. Called by player.fire_super.
func activate(ship) -> void:
	var tree := ship.get_tree() if ship.has_method("get_tree") else null
	if tree == null:
		return
	var damage: int = _damage_at_mark(int(mark))
	# Damage every enemy. take_hit returns true if the enemy died — let
	# enemy_base / enemy_core handle scoring + debris + explosion VFX so
	# the bomb's screen-clear reads as a chain of normal kills, not a
	# single global event.
	for enemy in tree.get_nodes_in_group("enemies"):
		if enemy and is_instance_valid(enemy) and enemy.has_method("take_hit"):
			enemy.take_hit(damage)
	# Clear every enemy bullet aimed at the player. (Player bullets are in
	# the same group; we'd cancel them too — overkill but the player just
	# hit the bomb button, they accept the trade.)
	for b in tree.get_nodes_in_group("bullets"):
		if b and is_instance_valid(b):
			b.queue_free()
	# Big radial shockwave VFX — reuse ExplosionFx.burst centered on the
	# player so it reads as "the bomb came from you."
	var ExplosionFx = load("res://scripts/effects/explosion_fx.gd")
	if ExplosionFx:
		ExplosionFx.burst(ship.global_position, 8, 80.0, 0.05)
	# Camera shake if available — sells the impact.
	var main := tree.get_current_scene()
	if main and main.has_node("Camera2D"):
		var cam = main.get_node("Camera2D")
		if cam.has_method("add_trauma"):
			cam.add_trauma(0.7)


func _charges_at_mark(at_mark: int) -> int:
	return base_charges + (at_mark - 1) * charges_per_mark


func _damage_at_mark(at_mark: int) -> int:
	return base_damage + (at_mark - 1) * dmg_per_mark


# Editor uses this for DPS-style readouts. Smart Bomb isn't really DPS,
# but reporting the per-activation damage gives the editor a meaningful
# number on the Mk slider.
func effective_damage(at_mark: int) -> int:
	return _damage_at_mark(at_mark)

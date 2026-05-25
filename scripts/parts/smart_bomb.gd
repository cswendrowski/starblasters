extends "res://scripts/parts/super_part.gd"

# Smart Bomb — DoDonPachi / Raiden classic super weapon. On activation:
#   - Cancel every enemy bullet on screen.
#   - Deal heavy damage to every enemy on screen (lethal to most chaff,
#     bites bosses for a chunk).
#   - Big radial VFX so the player feels the panic-button payoff.

@export var base_damage: int = 25
@export var dmg_per_mark: int = 10


func _init() -> void:
	super._init()
	display_name = "Smart Bomb"
	description = "Screen clear + heavy damage. Limited charges, refill at outposts."
	base_charges = 3
	charges_per_mark = 1


func activate(ship) -> void:
	if not ship.has_method("get_tree"):
		return
	var tree: SceneTree = ship.get_tree()
	if tree == null:
		return
	# Brief invuln so the bomb resolves before the next hit lands. Also
	# lets the Touhou death-bomb hook in player.take_damage save the
	# player from a fatal hit.
	if "_invuln_t" in ship:
		ship._invuln_t = max(ship._invuln_t, 0.6)
	var damage: int = _damage_at_mark(int(mark))
	# Damage every enemy. take_hit lets enemy_base / enemy_core handle
	# scoring + debris + explosion VFX so the bomb reads as a chain of
	# normal kills, not a single global event.
	for enemy in tree.get_nodes_in_group("enemies"):
		if enemy and is_instance_valid(enemy) and enemy.has_method("take_hit"):
			enemy.take_hit(damage)
	# Clear every enemy bullet aimed at the player.
	for b in tree.get_nodes_in_group("bullets"):
		if b and is_instance_valid(b):
			b.queue_free()
	_flash_at(ship, 1.0)
	_burst_at(ship, 8, 80.0, 0.05)
	_camera_trauma(ship, 0.7)
	# Bomb detonation SFX — explosion.tscn itself doesn't play audio, and
	# pre-refactor smart_bomb never wired one. Reuse the mine explosion
	# clip (SFX_explosion1.wav) so the panic-button reads. One detached
	# one-shot — the staggered _burst_at would clip if each spawned audio.
	var ExplosionSfx = preload("res://Sound/SFX_explosion1.wav")
	Sfx.play_one_shot(ExplosionSfx, ship.global_position, -2.0)


func _damage_at_mark(at_mark: int) -> int:
	return base_damage + (at_mark - 1) * dmg_per_mark


func effective_damage(at_mark: int) -> int:
	return _damage_at_mark(at_mark)

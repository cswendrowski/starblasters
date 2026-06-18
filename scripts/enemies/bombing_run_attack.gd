extends RefCounted

# BombingRunAttack (Roman 2026-06-17) — launches a seq_bombing_run on a LIVE enemy in combat: the
# enemy transitions out (ascend), an overhead shadow carpet-bombs a lane pattern, then re-enters or
# exits. Shared by the bomber + wing so neither hand-rolls the sequence wiring.
#
# Contract for the caller (the enemy): set `external_control = true` BEFORE launch so enemy_core
# stops driving the transform, and clear it (or free the enemy) on the returned sequence's
# `finished`. The sequence parents to the enemy's world sibling (BulletWorld.resolve) so its
# telegraphs / shadow / explosions render in the gameplay viewport — and in the SubViewport bench.
# It self-frees on finish, so a caller that's destroyed mid-run never leaks the node.

const SeqBombingRun = preload("res://scripts/effects/sequences/seq_bombing_run.gd")
const BulletWorld = preload("res://scripts/systems/bullet_world.gd")

# Placeholder defaults — tune in the Sequence Lab ("Bombing Run"), then bake the values here.
const DEFAULTS := {
	"pattern": 0.0, "direction": 0.0, "bombs_per_lane": 4.0,
	"telegraph_time": 1.0, "shadow_speed": 120.0, "ascend_speed": 200.0,
	"aoe_radius": 12.0, "damage": 1.0, "return_mode": 0.0,
}


# Spawn + play the sequence on `enemy`. `body_sprite` is cloned for the overhead shadow. `knobs`
# overrides any DEFAULTS keys (pattern / direction / return_mode per run). Returns the sequence
# node (connect its `finished`) or null if the enemy has no world to parent into.
static func launch(enemy: Node2D, body_sprite: Sprite2D, knobs: Dictionary = {}) -> Node:
	if enemy == null or not is_instance_valid(enemy):
		return null
	var world: Node = BulletWorld.resolve(enemy, enemy.get_parent())
	if world == null or not is_instance_valid(world):
		return null
	var cfg: Dictionary = DEFAULTS.duplicate()
	for key in knobs:
		cfg[key] = knobs[key]
	var seq = SeqBombingRun.new()
	world.add_child(seq)
	seq.finished.connect(seq.queue_free)   # production lifecycle: free itself after the run
	seq.play(enemy, body_sprite, cfg)
	return seq

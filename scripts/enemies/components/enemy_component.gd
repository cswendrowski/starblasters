class_name EnemyComponent
extends Resource

# Base for enemy BEHAVIOR COMPONENTS (Shield, Emitter, DeathEffect, …) — the third
# composition axis alongside movement + weapon (m6 design §3 / §19). A component is a
# small Resource composed onto any enemy via `enemy_base.components[]`, duplicated
# per-instance at spawn. ALL hooks are optional (duck-typed — a component overrides
# only what it needs):
#
#   on_start(enemy)              — after spawn + positioning (deferred), and on recycle
#   on_process(enemy, delta)     — per-frame; ticked by enemy_core only (event-driven
#                                  components on bosses/bespoke hulls just skip this)
#   on_hit(enemy, damage) -> int — participate in the damage pipeline; return the
#                                  REMAINING damage (absorb/reduce/reflect). <=0 = fully
#                                  absorbed. Default: unchanged.
#   on_death(enemy)              — enemy is dying (ring-release, kill-partner, …)
#   on_leave(enemy)              — enemy recycled / escaped (teardown)
#
# Registry + event fan-out live on enemy_base (so bosses + bespoke hulls can host
# components too); the per-frame tick lives on enemy_core. INERT until something
# assigns components[] (conversions, faction overlays).


func on_start(_enemy) -> void:
	pass


func on_process(_enemy, _delta: float) -> void:
	pass


# Return the damage REMAINING after this component. Default: pass through unchanged.
func on_hit(_enemy, damage: int) -> int:
	return damage


func on_death(_enemy) -> void:
	pass


func on_leave(_enemy) -> void:
	pass

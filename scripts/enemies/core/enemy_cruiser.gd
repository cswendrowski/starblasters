extends "res://scripts/enemies/enemy_core.gd"
class_name EnemyCruiser

# Multi-part destroyable cruiser (rebuilt 2026-06-24). The hull is the CORE (this node — the tanky
# kill target); its destructible SECTIONS are DestructiblePart child nodes authored in the .tscn
# (two gun pods + an engine + a bridge), each an independent EnemyBase the player can shoot off for
# bounty. Killing the core cascade-explodes any surviving parts so the whole cruiser detonates
# together. Movement is the shared Drift hold (capital sits high in the band).
# NOTE: display_scale only affects VFX blast / debris count.

const Drift = preload("res://scripts/enemies/patterns/drift.gd")


func _ready() -> void:
	max_health    = 28          # tanky hull — the parts are the softer, pickable targets
	bounty_value  = 40
	auto_rotate   = false
	display_scale = 2.0
	if movement == null:
		var d := Drift.new()
		d.hover_y = 50.0        # capital hold high in the band
		movement = d
	super._ready()


# Cascade: detonate every surviving section (their died signals fire → bounties count), then the
# core's own explosion. Freeing the core frees the part children anyway; this gives them death VFX.
func explode() -> void:
	for c in get_children():
		if c is DestructiblePart and is_instance_valid(c) and not (("_dying" in c) and c._dying):
			c.explode()
	super.explode()

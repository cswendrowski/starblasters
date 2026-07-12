extends "res://scripts/parts/mode_part.gd"

# Reflect — Shift mode. For the duration, incoming shots have a CHANCE to bounce back at
# the enemy (negating that hit). Stacks with the Reflective Shield Tuning module (which
# reflects every Nth absorbed bullet) — both can fire. Effect lives in player.gd's
# catch-field handler _on_mode_field_hit (rolls reflect_chance → bullet.reflect_to_enemies();
# gated on _reflect_on()). Charges refill over time. Numbers first-pass.

@export var duration: float = 4.0
@export var charges: int = 2
@export var regen_secs: float = 5.0
@export var base_reflect_chance: float = 0.35   # 35% per-hit reflect at Mk1
@export var reflect_chance_per_mark: float = 0.05


func _init() -> void:
	super._init()
	mode_id = Mode.REFLECT
	display_name = "Reflect"
	description = "Tap Shift to harden — incoming shots have a chance to ricochet back at the enemy that fired them. Stacks with the reflect module. Charges refill over time."


func mode_duration(_at_mark: int) -> float:
	return duration

func mode_charges(_at_mark: int) -> int:
	return charges

func mode_regen_kind() -> int:
	return ModeRegen.TIME

func mode_regen_secs() -> float:
	return regen_secs


# Per-hit reflect probability while active. Mk1 = base; each further Mk adds a step.
func reflect_chance_at_mark(at_mark: int) -> float:
	return clampf(base_reflect_chance + float(clampi(at_mark, 1, 9) - 1) * reflect_chance_per_mark, 0.0, 1.0)


func bonus_description(mk: int) -> String:
	return "%.1fs · %d charges · %d%% reflect" % [mode_duration(mk), mode_charges(mk), roundi(reflect_chance_at_mark(mk) * 100.0)]

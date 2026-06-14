extends Resource

# Minimal phase descriptor for BossBase's HP-gated phase state machine.
# Sketch a phase as `BossPhase.make("Phase 2", 0.66, true, 4.0)` — boss base
# walks the list in order, switching phases when current HP% drops at or
# below `hp_threshold_pct` and the phase index advances. Phase 0 is the
# starting phase; its threshold is conventionally 1.0.

@export var name: String = ""
# Transition to this phase when hp_pct <= this value. Phase 0 = 1.0 (start).
@export var hp_threshold_pct: float = 1.0
# Whether to play the base's enrage flash on entry.
@export var enrage_flash: bool = true
# 0.0 = no shake on entry; otherwise passed to add_trauma().
@export var screen_shake_strength: float = 0.0


static func make(p_name: String, p_threshold: float, p_flash: bool = true, p_shake: float = 0.0) -> Resource:
	var p = (load("res://scripts/enemies/bosses/boss_phase.gd") as GDScript).new()
	p.name = p_name
	p.hp_threshold_pct = p_threshold
	p.enrage_flash = p_flash
	p.screen_shake_strength = p_shake
	return p

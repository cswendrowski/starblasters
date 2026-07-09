extends "res://scripts/enemies/bosses/boss_part.gd"

# A destructible SECTION of the Corporate Director (Roman 2026-07-08). The Director's fight IS destroying
# its sections — battleship-style: kill every section → death. Each section is a boss_part wrapping one of
# the authored Collision* polygons (the Director reparents the polygon into this part at spawn, so bullets
# hit the specific section rather than one whole-ship zone).
#
# Single-stage sections destroy once. The shared HOOD+MISSILE section is 2-stage: destroy → hood (re-arm) →
# destroy → missiles. On each stage-completion it emits section_stage(id, stage); the Director reveals the
# matching Destroyed* overlay, disables the weapon, and plays the instakill+blowout FX. Every hit also
# jolts the boss (asteroid-style knock-away) via boss_ref.section_was_hit().

signal section_stage(section: Node, stage: int)

var section_id: String = ""
var stages: int = 1
var _stage: int = 0
var _stage_hp: int = 30


func setup_section(host: Node2D, id: String, stage_hp: int, num_stages: int) -> void:
	boss_ref = host
	section_id = id
	stages = maxi(1, num_stages)
	_stage_hp = maxi(1, stage_hp)
	max_hp = _stage_hp
	hp = _stage_hp
	is_hazard = true
	leave_trail = false


# Player-fire entry point. Overrides boss_part.take_hit to add the knock-away + the 2-stage re-arm.
func take_hit(damage: int = 1) -> bool:
	if _destroyed:
		return false
	hp -= damage
	if boss_ref != null and is_instance_valid(boss_ref) and boss_ref.has_method("section_was_hit"):
		boss_ref.section_was_hit()   # asteroid-style knockback (graced by the boss)
	if hp <= 0:
		_complete_stage()
		return _destroyed
	return false


# Smart-bomb entry (capped, like boss_part) → routes through take_hit.
func take_smart_bomb(damage: int) -> bool:
	var d: int = damage if smart_bomb_cap < 0 else mini(damage, smart_bomb_cap)
	return take_hit(d)


func _complete_stage() -> void:
	section_stage.emit(self, _stage)   # boss: reveal overlay + disable weapon + FX for THIS stage
	_stage += 1
	if _stage < stages:
		hp = _stage_hp                       # re-arm for the next stage (hood → missiles)
	else:
		_destroyed = true
		part_destroyed.emit(self)            # fully gone → the boss's death check


func is_destroyed() -> bool:
	return _destroyed


# Health-bar contribution: current stage HP PLUS the untouched later stages, so the bar drops monotonically
# across the 2-stage hood/missile (destroying the hood doesn't re-fill the bar when the part re-arms).
func bar_hp() -> int:
	return maxi(0, hp + (stages - _stage - 1) * _stage_hp)


func bar_max() -> int:
	return stages * _stage_hp

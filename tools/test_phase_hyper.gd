extends Node

# Phase/Hyper mechanics test (Roman 2026-06-10): boots combat (autoloads loaded), grabs the player,
# and verifies the Phase rework mechanics — 3s duration, and bullet absorption restoring 1 shield per
# hit while phased — plus that the Hyper pulsing-outline node spawns when hyper is active. Visual feel
# (after-images, pulse rate) needs Roman's eyeball. Run:
# godot --headless --path . tools/test_phase_hyper.tscn --quit-after 120

const RESULT := "res://tools/_phase_hyper_result.txt"
var _t := 0
var _main: Node = null
var _p: Node = null
var _done := false

func _ready() -> void:
	var run = get_node_or_null("/root/Run")
	if run != null:
		run.new_run()
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)

func _process(_dt: float) -> void:
	if _done:
		return
	_t += 1
	if _p == null and _main != null:
		_p = _main.get_node_or_null("Player")
	if _t < 8 or _p == null:
		return
	_done = true
	var lines: Array = []
	var fails := 0
	# 1) Phase duration default = 3.0
	lines.append("mode_duration = %.1f (expect 3.0)" % float(_p.mode_duration))
	if abs(float(_p.mode_duration) - 3.0) > 0.01:
		lines.append("FAIL mode_duration not 3.0"); fails += 1
	# 2) Bullet absorption while phased restores 1 shield per hit (capped).
	_p.set("max_shield", 10)
	_p.set("shield", 2)
	_p.set("active_mode", 1); _p.set("mode_active_t", 3.0)        # phased
	_p.set("invincible", false)
	var before: int = int(_p.shield)
	_p.take_damage(5)              # would normally drain shield; phased -> +1
	var after1: int = int(_p.shield)
	_p.take_damage(3)
	var after2: int = int(_p.shield)
	lines.append("shield while phased: %d -> %d -> %d (expect +1 each)" % [before, after1, after2])
	if after1 != before + 1 or after2 != after1 + 1:
		lines.append("FAIL phase did not absorb -> +1 shield per hit"); fails += 1
	# cap at max_shield
	_p.set("shield", 10)
	_p.take_damage(5)
	if int(_p.shield) != 10:
		lines.append("FAIL phase shield exceeded max"); fails += 1
	else:
		lines.append("shield caps at max while phased: OK")
	# 3) Out of phase, damage applies normally (drains shield).
	_p.set("mode_active_t", 0.0)
	_p.set("_invuln_t", 0.0)
	_p.set("shield", 5)
	_p.take_damage(2)
	lines.append("shield after normal hit (phase off): %d (expect 3)" % int(_p.shield))
	if int(_p.shield) != 3:
		lines.append("FAIL normal damage broken after phase changes"); fails += 1
	# 4) Hyper pulsing outline node spawns while hyper active.
	_p.set("active_mode", 2)       # ShiftMode.HYPER = 2
	_p.set("mode_duration", 4.0)
	_p.set("mode_active_t", 4.0)
	_p.set("active_mode", 2)  # HYPER (already set; _hyper_on() now reads mode_active_t)
	_p._update_hyper_outline(0.05)
	var ho = _p.get("_hyper_outline")
	lines.append("hyper outline spawned: %s" % (ho != null and is_instance_valid(ho)))
	if ho == null or not is_instance_valid(ho):
		lines.append("FAIL hyper outline node not created"); fails += 1
	_p._clear_hyper_outline()
	if _p.get("_hyper_outline") != null:
		lines.append("FAIL hyper outline not cleared"); fails += 1
	lines.append("PHASE/HYPER: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(lines)))
		f.close()
	get_tree().quit()

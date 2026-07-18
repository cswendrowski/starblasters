extends Node

# Per-ship combat-launch smoke (born 2026-07-16 chasing the Hive CTD — kept: it caught a
# heap-corruption crash headless that parse/boot checks can't). Boots combat as a chosen
# hull with its REAL starting kit seeded. Run (exit 0 = clean):
#   godot --path . --headless res://tools/repro_hive_combat.tscn --quit-after 12
# Env knobs:
#   HIVE_VARIANT=N              ship_variant to launch (default 9 = Hive)
#   HIVE_STRIP=modules,secondary,mode   remove kit pieces (crash bisection)
#   HIVE_ONLY_MODULE=<module_id>        keep just one module in the bay
# Sweep all hulls: foreach v in 0..9 { HIVE_VARIANT=$v; run; check exit }

func _ready() -> void:
	var run = get_node("/root/Run")
	run.new_run()
	run.ship_variant = int(OS.get_environment("HIVE_VARIANT")) if OS.get_environment("HIVE_VARIANT") != "" else 9
	run.reseed_loadout_for_ship()
	run.current_node_type = 0   # COMBAT
	var strip := OS.get_environment("HIVE_STRIP")
	if strip.contains("modules"):
		run.modules = []
	# HIVE_ONLY_MODULE: keep just one module_id in the bay (bisect which one crashes).
	var only := OS.get_environment("HIVE_ONLY_MODULE")
	if only != "":
		var kept: Array = []
		for m in run.modules:
			if String(m.module_id) == only:
				kept.append(m)
		run.modules = kept
	if strip.contains("secondary"):
		run.loadout_snapshot.erase(5)   # SlotType.HARDPOINT_WING
	if strip.contains("mode"):
		run.loadout_snapshot.erase(10)  # SlotType.SHIFT_MODE
	print("[repro] Hive run seeded (strip='%s') — entering combat" % strip)
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")

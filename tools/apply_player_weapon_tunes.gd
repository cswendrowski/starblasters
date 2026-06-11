extends SceneTree

# Integrator for the Weapon Bench (Roman 2026-06-11). Reads the stat overrides Roman
# saved from the Weapon Lab's PLAYER tab (user://tuners/player_weapons.json) and writes
# them into the weapons' .tres — keeping the .tres single-source-of-truth. For each
# tuned weapon it rebuilds the Part from its current .tres, stamps the overrides, and
# re-saves (so untouched stats are preserved). Run:
#   godot --headless -s res://tools/apply_player_weapon_tunes.gd
# Then validate: tools/validate_weapon_data.gd

const PartCatalog = preload("res://scripts/parts/part_catalog.gd")
const CFG := "user://tuners/player_weapons.json"

# factory -> .tres (same map as tools/validate_weapon_data.gd).
const MAP := {
	"_make_basic_blaster": "res://resources/weapons/energy_blaster.tres",
	"_make_heavy_blaster": "res://resources/weapons/heavy_blaster.tres",
	"_make_twin_blaster": "res://resources/weapons/twin_blaster.tres",
	"_make_autocannon": "res://resources/weapons/autocannon.tres",
	"_make_minigun": "res://resources/weapons/minigun.tres",
	"_make_rotary_laser": "res://resources/weapons/rotary_laser.tres",
	"_make_quad_lasers": "res://resources/weapons/quad_lasers.tres",
	"_make_wave_gun": "res://resources/weapons/wave_gun.tres",
	"_make_laser_beam": "res://resources/weapons/laser_beam.tres",
	"_make_rocket_pod": "res://resources/weapons/rocket_pod.tres",
	"_make_seeking_missile": "res://resources/weapons/seeking_missile.tres",
	"_make_anti_ship_missile": "res://resources/weapons/anti_ship_missile.tres",
	"_make_em_torpedo": "res://resources/weapons/em_torpedo.tres",
	"_make_spread_cannon": "res://resources/weapons/spread_cannon.tres",
	"_make_shredder": "res://resources/weapons/shredder.tres",
	"_make_pulse_laser": "res://resources/weapons/pulse_laser.tres",
	"_make_smart_bomb": "res://resources/weapons/smart_bomb.tres",
	"_make_particle_beam": "res://resources/weapons/particle_beam.tres",
	"_make_drone_bits": "res://resources/weapons/drone_bits.tres",
	"_make_drone_swarm": "res://resources/weapons/drone_swarm.tres",
	"_make_swarm_launcher": "res://resources/weapons/swarm_launcher.tres",
}


func _init() -> void:
	await process_frame
	if not FileAccess.file_exists(CFG):
		print("No tunes file at ", CFG, " — nothing to apply.")
		quit()
		return
	var f := FileAccess.open(CFG, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		print("Malformed tunes file.")
		quit()
		return
	var applied := 0
	for factory in (parsed as Dictionary).keys():
		var overrides: Dictionary = parsed[factory]
		if not MAP.has(factory):
			print("SKIP unknown factory: ", factory)
			continue
		var path: String = MAP[factory]
		var part = PartCatalog._make_by_name(factory, 4)
		if part == null:
			print("SKIP build-fail: ", factory)
			continue
		var changes := PackedStringArray()
		for stat in overrides.keys():
			if stat in part:
				part.set(stat, overrides[stat])
				changes.append("%s=%s" % [stat, str(overrides[stat])])
		# Match the regen format: identity stays code-owned, .tres holds stats + slot.
		if "display_name" in part:
			part.display_name = ""
		if "description" in part:
			part.description = ""
		part.resource_path = ""
		var err := ResourceSaver.save(part, path)
		if err == OK:
			applied += 1
			print("APPLIED ", path.get_file(), ": ", ", ".join(changes))
		else:
			print("SAVE-FAIL(", err, "): ", path)
	print("DONE — ", applied, " weapon .tres updated. Run validate_weapon_data.gd next.")
	quit()

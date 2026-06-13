extends SceneTree

# Weapon DPS report generator (2026-06-13). Regenerates docs/weapon_stats.csv from
# live Part data and prints a single-target DPS table for the report doc. Reads each
# CANNON-slot primary via PartCatalog and evaluates its _mk_knobs() curves (the same
# specs the game applies), so multi-projectile + Callable-damage + cooldown-curve
# weapons are handled correctly without hand-correction.
#
# Single-target DPS = per-projectile damage x projectiles/shot / cooldown.
# Run: godot --headless --script res://tools/weapon_dps_report.gd

const PartCatalog := preload("res://scripts/parts/part_catalog.gd")
const Slots := preload("res://scripts/weapons/SlotTypes.gd")
const OUT_CSV := "res://docs/weapon_stats.csv"

# CANNON-slot primaries, in pool order. (Particle Beam is a HARDPOINT secondary beam,
# not a single-target primary — out of scope for this table.)
const PRIMARIES := [
	"_make_basic_blaster", "_make_heavy_blaster", "_make_twin_blaster",
	"_make_quad_lasers", "_make_rotary_laser", "_make_minigun", "_make_autocannon",
	"_make_wave_gun", "_make_spread_cannon", "_make_laser_beam",
	"_make_shredder", "_make_pulse_laser",
]


func _init() -> void:
	var rows: Array = []
	rows.append("Weapon,Mk1 Damage,Mk9 Damage,Mk1 Cooldown (s),Mk9 Cooldown (s),Mk1 Fire Rate (shots/s),Mk9 Fire Rate (shots/s),Mk1 Projectiles/shot,Mk9 Projectiles/shot,Ammo Mk1,Ammo Mk9")
	var report: Array = []
	report.append("%-16s | %-9s | Mk1 DPS | Mk9 DPS | proj | ammo" % ["Weapon", "dmg 1->9"])
	report.append("-".repeat(72))

	for factory in PRIMARIES:
		var part = PartCatalog._make_by_name(factory, Slots.SlotType.CANNON)
		if part == null:
			report.append("%s: BUILD FAILED" % factory)
			continue
		var name: String = str(part.display_name)
		var d1 := _dmg(part, 1); var d9 := _dmg(part, 9)
		var c1 := _cd(part, 1);  var c9 := _cd(part, 9)
		var p1 := _proj(part, 1); var p9 := _proj(part, 9)
		var a1 := _ammo(part, 1); var a9 := _ammo(part, 9)
		var fr1 := (1.0 / c1) if c1 > 0.0 else 0.0
		var fr9 := (1.0 / c9) if c9 > 0.0 else 0.0
		var dps1 := (float(d1 * p1) / c1) if c1 > 0.0 else 0.0
		var dps9 := (float(d9 * p9) / c9) if c9 > 0.0 else 0.0
		rows.append("%s,%d,%d,%.4f,%.4f,%.2f,%.2f,%d,%d,%s,%s"
			% [name, d1, d9, c1, c9, fr1, fr9, p1, p9, a1, a9])
		report.append("%-16s | %-9s | %7.0f | %7.0f | %d->%d | %s->%s"
			% [name, "%d->%d" % [d1, d9], dps1, dps9, p1, p9, a1, a9])

	var f := FileAccess.open(OUT_CSV, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(rows)) + "\n")
		f.close()
		print("wrote ", OUT_CSV)
	else:
		print("ERROR: could not open ", OUT_CSV)
	print("\n".join(PackedStringArray(report)))
	quit()


# Evaluate a knob spec (Callable(mark) | Array[mk1,mk9] linear | scalar) at `mark`.
func _eval(spec, mark: int) -> float:
	if spec is Callable:
		return float(spec.call(mark))
	if spec is Array and spec.size() == 2:
		var t: float = (clampf(float(mark), 1.0, 9.0) - 1.0) / 8.0
		return lerpf(float(spec[0]), float(spec[1]), t)
	if spec == null:
		return 0.0
	return float(spec)


func _dmg(part, mark: int) -> int:
	var knobs: Dictionary = part._mk_knobs()
	if knobs.has("bullet_damage"):
		return int(round(_eval(knobs["bullet_damage"], mark)))
	return int(part.effective_damage(mark))


func _cd(part, mark: int) -> float:
	var knobs: Dictionary = part._mk_knobs()
	if knobs.has("cooldown"):
		return _eval(knobs["cooldown"], mark)
	return float(part.base_cooldown)


func _proj(part, mark: int) -> int:
	var knobs: Dictionary = part._mk_knobs()
	if knobs.has("bullet_spread_count"):
		return int(round(_eval(knobs["bullet_spread_count"], mark)))
	# Quad Lasers fires 4 parallel bolts via primary_parallel_offsets (QUAD_OFFSETS),
	# not a spread knob — the only parallel-bolt primary, special-cased here.
	if "primary_parallel_offsets" in part._snapshot_keys():
		return 4
	return 1


func _ammo(part, mark: int) -> String:
	var n: int = int(part.ammo_at_mark(mark))
	return "infinite" if n <= 0 else str(n)

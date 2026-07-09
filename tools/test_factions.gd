extends SceneTree

# M6b: faction machinery (inert). Verifies the 4-faction data table and that apply()
# stamps each faction's modifier onto a fresh enemy via the M6a component/weapon axes:
#   supremacy -> faster projectiles only (bullet_speed_mult 1.25; fire-rate mult removed 2026-07-07)
#   privateer -> 2x HP                          corporate -> Shield component
#   zealot    -> DropFirecore ENTITY mount (DEATH)
# apply() is HOME-gated (Roman 2026-06-08): it only themes a unit whose home IS that faction, so
# each check uses a HOME unit of the faction under test (not a single shared dart).
# Run: godot --headless --script res://tools/test_factions.gd

const RESULT := "res://tools/_factions_result.txt"
const Factions := preload("res://scripts/levels/factions.gd")
const ShieldComponent := preload("res://scripts/enemies/components/shield_component.gd")
const MountSpecC := preload("res://scripts/enemies/mounts/mount_spec.gd")

var _lines: Array = []
var _fails := 0
var _done := false


func _fail(m: String) -> void:
	_lines.append("FAIL " + m); _fails += 1


func _dart():
	return load("res://scenes/enemies/core/enemy_core_s_dart.tscn").instantiate()


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true

	# data table: 4 factions, correct lore names + flags
	var lore := {
		Factions.Id.SUPREMACY: "Crimson Supremacy",
		Factions.Id.PRIVATEER: "Vertarine Armada",
		Factions.Id.CORPORATE: "UltraGalactic Concerns",
		Factions.Id.ZEALOT: "Evantian Theocracy",
	}
	for id in lore.keys():
		var d: Dictionary = Factions.data(id)
		if d.get("lore_name", "") != lore[id]:
			_fail("faction %d lore_name '%s' != '%s'" % [id, d.get("lore_name", ""), lore[id]])
	if not Factions.data(Factions.Id.PRIVATEER).get("overlay", false):
		_fail("privateer should be the overlay faction")

	# supremacy: faster PROJECTILES only (bullet_speed_mult 1.25). The faction fire-rate mult was
	# removed 2026-07-07 (mounts read cadence from spec.fire_interval_*, so a faction fire-rate mult
	# is a no-op) — fire_interval must stay UNCHANGED. — supremacy-home unit
	var s = load("res://scenes/enemies/factions/supremacy/enemy_s_s_hotrod.tscn").instantiate()
	var fmin: float = s.fire_interval_min
	var bsm0: float = s.bullet_speed_mult if "bullet_speed_mult" in s else 1.0
	Factions.apply(Factions.Id.SUPREMACY, s)
	if not is_equal_approx(s.fire_interval_min, fmin):
		_fail("supremacy fire_interval_min %.3f changed from %.3f (fire-rate mult removed)" % [s.fire_interval_min, fmin])
	if "bullet_speed_mult" in s and not is_equal_approx(s.bullet_speed_mult, bsm0 * 1.25):
		_fail("supremacy bullet_speed_mult %.3f != %.3f (×1.25)" % [s.bullet_speed_mult, bsm0 * 1.25])
	# Tint is intentionally NOT applied (art conveys faction) — modulate stays default.
	if s.modulate != Color.WHITE:
		_fail("supremacy modulate should be untouched (tint dropped), got %s" % str(s.modulate))
	s.free()

	# privateer: 2x HP — privateer-home unit (the dart moved to Supremacy-home 2026-07-06, so it no
	# longer receives the privateer overlay; use a privateer-home Falchion).
	var p = load("res://scenes/enemies/factions/privateer/enemy_core_s_falchion.tscn").instantiate()
	var hp0: int = p.max_health
	Factions.apply(Factions.Id.PRIVATEER, p)
	if p.max_health != int(round(hp0 * 2.0)):
		_fail("privateer max_health %d != %d (2x)" % [p.max_health, int(round(hp0 * 2.0))])
	p.free()

	# corporate: a Shield component attached — corporate-home unit
	var c = load("res://scenes/enemies/factions/corporate/enemy_c_s_curve.tscn").instantiate()
	Factions.apply(Factions.Id.CORPORATE, c)
	var has_shield := false
	for comp in c.components:
		if comp is ShieldComponent:
			has_shield = true
	if not has_shield:
		_fail("corporate did not attach a Shield component")
	c.free()

	# zealot: a DropFirecore drop attached — zealot-home unit. Now an ENTITY MountComponent (DEATH
	# trigger) since the firecore overlay migrated off EmitterComponent (Phase 2, 2026-07-07).
	var z = load("res://scenes/enemies/factions/zealot/enemy_z_s_manta.tscn").instantiate()
	Factions.apply(Factions.Id.ZEALOT, z)
	var has_emitter := false
	for comp in z.components:
		if "spec" in comp and comp.spec != null \
				and int(comp.spec.kind) == MountSpecC.Kind.ENTITY \
				and int(comp.spec.trigger) == MountSpecC.Trigger.DEATH \
				and String(comp.spec.emit_tag) == "firecore":
			has_emitter = true
	if not has_emitter:
		_fail("zealot did not attach a DEATH firecore ENTITY mount")
	z.free()

	_lines.append("FACTIONS: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	quit()
	return true

extends SceneTree

# M6b: faction machinery (inert). Verifies the 4-faction data table and that apply()
# stamps each faction's modifier onto a fresh enemy via the M6a component/weapon axes:
#   supremacy -> faster fire (interval * 0.7)   privateer -> 2x HP
#   corporate -> Shield component               zealot    -> DropFirecore Emitter (DEATH)
# plus the tint. Run: godot --headless --script res://tools/test_factions.gd

const RESULT := "res://tools/_factions_result.txt"
const Factions := preload("res://scripts/levels/factions.gd")
const ShieldComponent := preload("res://scripts/enemies/components/shield_component.gd")
const EmitterComponent := preload("res://scripts/enemies/components/emitter_component.gd")

var _lines: Array = []
var _fails := 0
var _done := false


func _fail(m: String) -> void:
	_lines.append("FAIL " + m); _fails += 1


func _dart():
	return load("res://scenes/enemies/factions/privateer/enemy_dart.tscn").instantiate()


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

	# supremacy: faster fire (interval * 0.7) + tint
	var s = _dart()
	var fmin: float = s.fire_interval_min
	Factions.apply(Factions.Id.SUPREMACY, s)
	if not is_equal_approx(s.fire_interval_min, fmin * 0.7):
		_fail("supremacy fire_interval_min %.3f != %.3f (×0.7)" % [s.fire_interval_min, fmin * 0.7])
	# Tint is intentionally NOT applied (art conveys faction) — modulate stays default.
	if s.modulate != Color.WHITE:
		_fail("supremacy modulate should be untouched (tint dropped), got %s" % str(s.modulate))
	s.free()

	# privateer: 2x HP
	var p = _dart()
	var hp0: int = p.max_health
	Factions.apply(Factions.Id.PRIVATEER, p)
	if p.max_health != int(round(hp0 * 2.0)):
		_fail("privateer max_health %d != %d (2x)" % [p.max_health, int(round(hp0 * 2.0))])
	p.free()

	# corporate: a Shield component attached
	var c = _dart()
	Factions.apply(Factions.Id.CORPORATE, c)
	var has_shield := false
	for comp in c.components:
		if comp is ShieldComponent:
			has_shield = true
	if not has_shield:
		_fail("corporate did not attach a Shield component")
	c.free()

	# zealot: a DropFirecore Emitter (DEATH trigger) attached
	var z = _dart()
	Factions.apply(Factions.Id.ZEALOT, z)
	var has_emitter := false
	for comp in z.components:
		if comp is EmitterComponent and comp.trigger == EmitterComponent.Trigger.DEATH:
			has_emitter = true
	if not has_emitter:
		_fail("zealot did not attach a DEATH Emitter component")
	z.free()

	_lines.append("FACTIONS: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(_lines)))
		f.close()
	quit()
	return true

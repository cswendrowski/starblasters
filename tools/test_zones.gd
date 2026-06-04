extends SceneTree

# Unit check for the firing Y-bands (Zones). Entry (top) and departure (bottom)
# hold/cease fire; the engagement band fires.
# Run: godot --headless --script res://tools/test_zones.gd

const RESULT := "res://tools/_zones_result.txt"


func _init() -> void:
	var log: Array = []
	if Zones.in_engagement(0.0):
		log.append("FAIL entry y=0 should be gated")
	if Zones.in_engagement(30.0):
		log.append("FAIL entry y=30 should be gated")
	if not Zones.in_engagement(100.0):
		log.append("FAIL engagement y=100 should fire")
	if not Zones.in_engagement(190.0):
		log.append("FAIL engagement y=190 should fire")
	if Zones.in_engagement(200.0):
		log.append("FAIL departure y=200 should cease")
	if Zones.in_engagement(260.0):
		log.append("FAIL departure y=260 should cease")
	if log.is_empty():
		log.append("ZONES TEST: PASS")
	else:
		log.append("ZONES TEST: FAIL")
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(PackedStringArray(log)))
		f.close()
	quit()

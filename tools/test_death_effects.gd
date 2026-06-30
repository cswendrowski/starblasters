extends SceneTree

# Headless smoke for scripts/effects/death_effects.gd. Plays every death STYLE on a synthetic host
# (a Node2D + body Sprite2D + two Engine markers) and verifies the sequence runs to completion and
# frees the host — no real enemy scene / autoloads needed, so it exercises death_effects.gd in
# isolation. Watch stderr for SCRIPT ERROR; the script prints a per-style verdict + PASS/FAIL.
#
#   godot --headless -s res://tools/test_death_effects.gd

const DeathEffects = preload("res://scripts/effects/death_effects.gd")
const BODY_TEX := "res://graphics/effects/debris.png"   # any small texture (size + UV path)

var _styles := ["burn_out", "firework", "spinout", "flashout", "instakill", "blow_out"]
var _i := -1
var _t := 0.0
const PER_STYLE := 7.0   # seconds per style — covers blow_out's max_dur (6s) + cleanup
var _host_ref: Node = null
var _fails := 0


func _process(dt: float) -> bool:
	if _i == -1:
		_start_next()
		return false
	_t += dt
	if _t < PER_STYLE:
		return false
	# Window elapsed — the host should be gone (every style frees it on finish).
	var freed: bool = _host_ref == null or not is_instance_valid(_host_ref)
	if not freed:
		_fails += 1
	print("[death_fx] %-10s host_freed=%s" % [_styles[_i], str(freed)])
	if _i + 1 >= _styles.size():
		_report()
		return true
	_start_next()
	return false


func _start_next() -> void:
	_i += 1
	_t = 0.0
	var host := _make_host()
	_host_ref = host
	var fx: Node = DeathEffects.new()
	get_root().add_child(fx)
	fx.play(host, _styles[_i], {}, Vector2.DOWN * 70.0, {
		"vfx_parent": get_root(), "wreck_parent": get_root(), "bounds": Rect2(0, 0, 480, 270),
	})


# A minimal stand-in for an enemy hull: a body Sprite2D named "Sprite2D" + two Engine markers.
func _make_host() -> Node2D:
	var host := Node2D.new()
	host.position = Vector2(240, 95)
	var body := Sprite2D.new()
	body.name = "Sprite2D"
	if ResourceLoader.exists(BODY_TEX):
		body.texture = load(BODY_TEX)
	host.add_child(body)
	var el := Marker2D.new()
	el.name = "EngineL"
	el.position = Vector2(-4, 6)
	host.add_child(el)
	var er := Marker2D.new()
	er.name = "EngineR"
	er.position = Vector2(4, 6)
	host.add_child(er)
	get_root().add_child(host)
	return host


func _report() -> void:
	if _fails == 0:
		print("VERDICT: PASS (%d/%d styles ran + freed the host)" % [_styles.size(), _styles.size()])
	else:
		print("VERDICT: FAIL (%d/%d styles left the host alive)" % [_fails, _styles.size()])

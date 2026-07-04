extends SceneTree

# Headless smoke for scripts/effects/death_effects.gd. Plays every death STYLE (and every spinout
# RESOLUTION) on a synthetic host (a Node2D + body Sprite2D + two Engine markers) and verifies the
# sequence runs to completion and frees the host — no real enemy scene / autoloads needed, so it
# exercises death_effects.gd in isolation. Watch stderr for SCRIPT ERROR; prints a per-case verdict.
#
#   godot --headless -s res://tools/test_death_effects.gd

const DeathEffects = preload("res://scripts/effects/death_effects.gd")
const BODY_TEX := "res://graphics/effects/debris.png"   # any small texture (size + UV path)

# (label, style, cfg). Force each spinout resolution + a small-ship size so the smoulder-trail path
# also runs (size_override drives _measure_scale's fallback via display_scale isn't set here, so we
# force it by texture — the debris tex reads large, so spinout below exercises the fire-trail path;
# blow_out/flashout/instakill also large. Small path is covered by compile + lab boot.)
var _cases := [
	{"label": "spin→instakill", "style": "spinout", "cfg": {"resolution": "instakill"}},
	{"label": "spin→flashout", "style": "spinout", "cfg": {"resolution": "flashout"}},
	{"label": "spin→wreck", "style": "spinout", "cfg": {"resolution": "wreck"}},
	{"label": "spin→blowout", "style": "spinout", "cfg": {"resolution": "blow_out"}},
	{"label": "spin→random", "style": "spinout", "cfg": {}},
	{"label": "flashout", "style": "flashout", "cfg": {}},
	{"label": "instakill", "style": "instakill", "cfg": {}},
	{"label": "blow_out", "style": "blow_out", "cfg": {}},
	{"label": "wreck", "style": "wreck", "cfg": {}},
	{"label": "wreck2", "style": "wreck", "cfg": {}},   # 2nd run — the shrink variant is random per play
	{"label": "random(lg)", "style": "random", "cfg": {}},
	{"label": "random(sm)", "style": "random", "cfg": {}, "small": true},
	{"label": "sm flashout", "style": "flashout", "cfg": {}, "small": true},
	# Small hosts exercise the SMOULDER trail (Line2D smoke + spark + torch shader) + the spark taper.
	{"label": "sm wreck", "style": "wreck", "cfg": {}, "small": true},
	{"label": "sm wreck2", "style": "wreck", "cfg": {}, "small": true},
]
var _i := -1
var _t := 0.0
const PER_STYLE := 9.0   # seconds per case — covers spinout's wreck drift-safety (8s) + cleanup
var _host_ref: Node = null
var _fails := 0


func _process(dt: float) -> bool:
	if _i == -1:
		_start_next()
		return false
	_t += dt
	if _t < PER_STYLE:
		return false
	var freed: bool = _host_ref == null or not is_instance_valid(_host_ref)
	if not freed:
		_fails += 1
	print("[death_fx] %-14s host_freed=%s" % [String(_cases[_i]["label"]), str(freed)])
	if _i + 1 >= _cases.size():
		_report()
		return true
	_start_next()
	return false


func _start_next() -> void:
	_i += 1
	_t = 0.0
	var host := _make_host(bool(_cases[_i].get("small", false)))
	_host_ref = host
	var fx: Node = DeathEffects.new()
	get_root().add_child(fx)
	fx.play(host, String(_cases[_i]["style"]), _cases[_i]["cfg"], Vector2.DOWN * 40.0, {
		"vfx_parent": get_root(), "wreck_parent": get_root(), "bounds": Rect2(0, 0, 480, 270),
	})


# A minimal stand-in for an enemy hull: a body Sprite2D named "Sprite2D" + two Engine markers.
func _make_host(small: bool = false) -> Node2D:
	var host := Node2D.new()
	host.position = Vector2(240, 95)
	var body := Sprite2D.new()
	body.name = "Sprite2D"
	if ResourceLoader.exists(BODY_TEX):
		body.texture = load(BODY_TEX)
		if small:
			body.hframes = 6   # 96px/6 = 16px frame → size_scale ~1.0 → smoulder trail path
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
		print("VERDICT: PASS (%d/%d cases ran + freed the host)" % [_cases.size(), _cases.size()])
	else:
		print("VERDICT: FAIL (%d/%d cases left the host alive)" % [_fails, _cases.size()])

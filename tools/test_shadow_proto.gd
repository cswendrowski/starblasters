extends SceneTree

# Headless driver for the light-derived shadow prototype (light_shadow_fx). The existing arrival/boot
# drivers only run LEGACY mode; this one flips KEY / FILL / dynamic on BOTH dock screens and ticks a few
# frames between switches so the per-frame projection (LightShadowFx._process) actually runs. Tested
# sequentially (OA freed before patrol) so the two HD scopes never overlap.
# 0=LEGACY 1=KEY 2=FILL (ShadowMode).

var _oa = null
var _ps = null
var _phase := 0
var _oa_fill := 0
var _oa_key := 0
var _oa_legacy_vis := false
var _ps_fill := 0


func _init() -> void:
	_oa = load("res://scenes/outpost_arrival.tscn").instantiate()
	_oa.manage_hd_scope = true
	_oa.arrival_time = 0.3
	get_root().add_child(_oa)
	var t := Timer.new()
	t.wait_time = 0.25
	t.autostart = true
	t.timeout.connect(_step)
	get_root().add_child(t)
	var guard := Timer.new()
	guard.wait_time = 12.0
	guard.one_shot = true
	guard.autostart = true
	guard.timeout.connect(func() -> void:
		print("VERDICT: FAIL (timeout, phase=%d)" % _phase)
		quit(1))
	get_root().add_child(guard)


func _step() -> void:
	_phase += 1
	match _phase:
		1:
			_oa.set_shadow_mode(2)        # FILL
			_oa.set_shadow_dynamic(true)
		2:
			_oa_fill = _count(_oa)
			_oa.set_shadow_mode(1)        # KEY
		3:
			_oa_key = _count(_oa)
			_oa.set_shadow_mode(0)        # LEGACY
		4:
			_oa_legacy_vis = _oa._shadow != null and _oa._shadow.visible
			_oa.queue_free()
			_oa = null
		5:
			_ps = load("res://scenes/dev/patrol_start.tscn").instantiate()
			get_root().add_child(_ps)
		6:
			_ps.set_shadow_mode(2)        # FILL
			_ps.set_shadow_dynamic(true)
		7:
			_ps_fill = _count(_ps)
			_finish()


func _count(scr) -> int:
	if scr == null or scr._shadow_mgr == null:
		return 0
	var n := 0
	for c in scr._shadow_mgr._casters:
		for s in c["pool"]:
			if is_instance_valid(s) and (s as Sprite2D).visible:
				n += 1
	return n


func _finish() -> void:
	print("shadow_proto: oa_fill=%d oa_key=%d oa_legacy_shadow_visible=%s ps_fill=%d" %
		[_oa_fill, _oa_key, str(_oa_legacy_vis), _ps_fill])
	var ok := _oa_fill > 0 and _oa_key > 0 and _oa_legacy_vis and _ps_fill > 0
	print("VERDICT: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

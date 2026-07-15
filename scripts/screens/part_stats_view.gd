class_name PartStatsView
extends Object

# Shared "part info" builder: the Mk-aware stats box + the clickable Mark ladder.
# Used by BOTH the outpost dock info popup (scripts/screens/outpost_arrival.gd) and the
# Codex item detail (scripts/screens/enemy_codex.gd) so the two never drift.

const SlotTypes = preload("res://scripts/weapons/SlotTypes.gd")

const HINT_OWNED := "MARK LEVELS — tap to compare (current ringed)"
const HINT_REFERENCE := "MARK LEVELS — tap to preview each"


# The full block: a hint line + Mark ladder + a stats box that repopulates when a Mark is tapped.
# owned=false (Codex) drops the "(current)" annotation — there's no owned mark in a reference view.
static func build(part, cur_mk: int, max_mk: int = 9, owned: bool = true, hint: String = "") -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	if hint == "":
		hint = HINT_OWNED if owned else HINT_REFERENCE
	v.add_child(_label(hint, UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 4)
	var show_mk := func(mk: int) -> void:
		fill_stats_box(stats_box, part, mk, cur_mk, owned)
	v.add_child(mark_ladder(cur_mk, max_mk, show_mk))
	v.add_child(stats_box)
	show_mk.call(cur_mk)
	return v


# The numeric stat lines for a part at a given Mk (slot-aware). Static — no instance state.
static func stat_lines(part, mk: int) -> Array:
	var lines: Array = []
	if part == null:
		return lines
	var st: int = int(part.slot_type) if "slot_type" in part else -1
	if st == SlotTypes.SlotType.MODULE:
		var bd: String = String(part.bonus_description(mk)) if part.has_method("bonus_description") else ""
		if bd != "":
			lines.append(bd)
		return lines
	if st == SlotTypes.SlotType.SHIFT_MODE:
		if part.has_method("mode_duration"):
			lines.append("Duration: %.1fs" % float(part.mode_duration(mk)))
		if part.has_method("mode_charges"):
			lines.append("Charges: %d" % int(part.mode_charges(mk)))
		if part.has_method("mode_regen_kind"):
			if int(part.mode_regen_kind()) == 1:   # ModeRegen.KILLS
				var kpc: int = int(part.mode_kills_per_charge()) if part.has_method("mode_kills_per_charge") else 0
				lines.append("Refill: %d kills / charge" % kpc)
			else:
				var rs: float = float(part.mode_regen_secs()) if part.has_method("mode_regen_secs") else 0.0
				lines.append("Refill: %.1fs / charge" % rs)
		return lines
	# Weapons (CANNON / HARDPOINT_WING / DEVICE_BAY_1).
	if part.has_method("effective_damage"):
		var dmg: int = int(part.effective_damage(mk))
		if dmg >= 0:
			lines.append("Damage: %d" % dmg)
	if part.has_method("ammo_at_mark"):
		var ammo: int = int(part.ammo_at_mark(mk))
		lines.append("Ammo: %s" % ("∞" if ammo < 0 else str(ammo)))
	elif part.has_method("_base_ammo"):
		var ammo2: int = int(part._base_ammo())
		lines.append("Ammo: %s" % ("∞" if ammo2 < 0 else str(ammo2)))
	if st == SlotTypes.SlotType.DEVICE_BAY_1 and part.has_method("_charges_at_mark"):
		lines.append("Charges: %d" % int(part._charges_at_mark(mk)))
	return lines


# Render the stat box for a chosen Mk: a header (flagged when it's the owned Mk) + each stat line.
static func fill_stats_box(box: VBoxContainer, part, mk: int, cur_mk: int, owned: bool = true) -> void:
	if box == null or not is_instance_valid(box):
		return
	_clear(box)
	var hdr: String = "Mk.%d stats" % mk
	if owned and mk == cur_mk:
		hdr += "   (current)"
	box.add_child(_label(hdr, UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_BOUNTY if (owned and mk == cur_mk) else UiTheme.COLOR_ACCENT))
	var lines: Array = stat_lines(part, mk)
	if lines.is_empty():
		box.add_child(_label("(no numeric stats)", UiTheme.FONT_SIZE_CAPTION, UiTheme.COLOR_FAINT))
	for ln in lines:
		box.add_child(_label(String(ln), UiTheme.FONT_SIZE_BODY, UiTheme.COLOR_GREEN))


# A row of tappable Mk chips 1..mx. The selected chip is ringed (bounty); lower marks dim, higher dark.
static func mark_ladder(cur: int, mx: int, on_pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for i in range(1, mx + 1):
		var chip := Button.new()
		chip.text = str(i)
		chip.custom_minimum_size = Vector2(40, 40)
		chip.add_theme_font_override("font", UiTheme.menu_font())
		chip.add_theme_font_size_override("font_size", UiTheme.FONT_SIZE_CAPTION)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(3)
		var fg: Color = UiTheme.COLOR_DISABLED
		if i == cur:
			sb.bg_color = UiTheme.COLOR_BOUNTY
			fg = Color(0.05, 0.05, 0.08)
		elif i < cur:
			sb.bg_color = Color(UiTheme.COLOR_ACCENT_DIM.r, UiTheme.COLOR_ACCENT_DIM.g, UiTheme.COLOR_ACCENT_DIM.b, 0.55)
			fg = UiTheme.COLOR_TEXT
		else:
			sb.bg_color = Color(0, 0, 0, 0.35)
			fg = UiTheme.COLOR_DISABLED
		for state in ["normal", "hover", "pressed", "focus"]:
			chip.add_theme_stylebox_override(state, sb)
		chip.add_theme_color_override("font_color", fg)
		chip.add_theme_color_override("font_hover_color", fg)
		chip.add_theme_color_override("font_pressed_color", fg)
		chip.add_theme_color_override("font_focus_color", fg)
		var mk: int = i
		chip.pressed.connect(func() -> void: on_pick.call(mk))
		row.add_child(chip)
	return row


static func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.menu_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

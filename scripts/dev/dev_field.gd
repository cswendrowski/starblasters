extends Object

# DevField — shared default-vs-override affordance for the P-BAKE dev tuners
# (docs/dev_tool_unification_design_2026-07-07.md §3.2, Phase 3). Solves Roman's symptom (c): in a
# tuner a shown value could be the shipping BAKED default or an un-pasted edit, indistinguishable.
#
# Given a value-carrying Control (SpinBox / CheckBox / CheckButton / OptionButton / LineEdit), a BAKED
# production default (the committed const/.tres value — NOT the user:// save), and the control's current
# value, it decorates the row: when current != baked it appends a muted "was: <default>" label + a small
# per-field "↺" revert button next to the control; when equal, no visual noise. Revert restores the baked
# value by SETTING the control (which fires the control's normal change signal, so the tool's existing
# plumbing reacts) and then re-hides the affordance.
#
# Design constraints (per the ticket):
#   - Opt-in per field. A tool calls decorate() once (at build) then refresh() after each load/change.
#   - Non-invasive: the affordance nodes are SIBLINGS appended after the control; no reparenting, no
#     data-model change, no Copy-output change.
#   - Cheap: no per-frame work. All work happens in decorate()/refresh(), called on load/change only.
#   - Safe under _loading guards: revert fires the control's change signal like a normal user edit — the
#     tool's own `if not _loading` guards apply. decorate/refresh NEVER emit signals themselves (they use
#     set_pressed_no_signal / direct value writes), so refreshing during a load can't fight suppression.
#
# Preload-referenced, NOT a global class_name (headless-safe), mirroring scripts/dev/dev_data.gd. Every
# method is static; the per-field state lives in metadata on the control itself (no registry to leak).

const _META := "_devfield"          # meta key: {baked, was_lbl, revert_btn}
const _MUTED := Color(0.62, 0.70, 0.44, 0.85)   # olive "was:" tint — reads as an aside, not an error
const _REVERT_TXT := "↺"        # ↺


# Decorate `ctl` with a default-vs-override affordance. `baked` is the committed production default (any
# scalar: float/int/bool/String). The affordance nodes are appended as siblings right after `ctl` in its
# parent, so the parent must already contain `ctl`. `font_size` matches the tool's caption size so the
# aside doesn't tower over the row. Call refresh() afterwards (and after each load) to sync visibility.
#
# Returns true on success. Idempotent-ish: a second decorate() on the same control rebuilds its state.
static func decorate(ctl: Control, baked, font_size: int = 15) -> bool:
	if ctl == null:
		return false
	var parent := ctl.get_parent()
	if parent == null:
		return false
	# Clear any prior decoration (re-decorate on a rebuilt row).
	if ctl.has_meta(_META):
		var prev: Dictionary = ctl.get_meta(_META)
		for k in ["was_lbl", "revert_btn"]:
			var n = prev.get(k, null)
			if n != null and is_instance_valid(n):
				n.queue_free()
	# The "was: X" muted aside.
	var was_lbl := Label.new()
	was_lbl.add_theme_font_size_override("font_size", font_size)
	was_lbl.add_theme_color_override("font_color", _MUTED)
	was_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	was_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	was_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Small per-field revert button.
	var revert := Button.new()
	revert.text = _REVERT_TXT
	revert.tooltip_text = "Revert to baked default"
	revert.add_theme_font_size_override("font_size", font_size)
	revert.custom_minimum_size = Vector2(0, 0)
	revert.size_flags_horizontal = Control.SIZE_SHRINK_END
	revert.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Insert both right after the control so they sit inline with the row.
	var idx := ctl.get_index()
	parent.add_child(was_lbl)
	parent.move_child(was_lbl, idx + 1)
	parent.add_child(revert)
	parent.move_child(revert, idx + 2)
	ctl.set_meta(_META, {"baked": baked, "was_lbl": was_lbl, "revert_btn": revert})
	revert.pressed.connect(func(): _revert(ctl))
	refresh(ctl)
	return true


# Update the baked default a decorated control compares against (e.g. when the tool re-seeds a row for a
# newly selected item without rebuilding the widget). Then refresh() to re-sync visibility.
static func set_baked(ctl: Control, baked) -> void:
	if ctl == null or not ctl.has_meta(_META):
		return
	var st: Dictionary = ctl.get_meta(_META)
	st["baked"] = baked
	ctl.set_meta(_META, st)
	refresh(ctl)


# Re-evaluate current-vs-baked and show/hide the affordance. Cheap; call after any load or value change.
# NEVER emits a change signal (reads the control's value, writes only sibling label text/visibility).
static func refresh(ctl: Control) -> void:
	if ctl == null or not ctl.has_meta(_META):
		return
	var st: Dictionary = ctl.get_meta(_META)
	var was_lbl: Label = st.get("was_lbl", null)
	var revert: Button = st.get("revert_btn", null)
	if was_lbl == null or not is_instance_valid(was_lbl):
		return
	var baked = st.get("baked", null)
	var cur = _read(ctl)
	var differs: bool = not _eq(cur, baked)
	was_lbl.visible = differs
	if revert != null and is_instance_valid(revert):
		revert.visible = differs
	if differs:
		was_lbl.text = "was: " + _fmt(baked)


# --- internals -------------------------------------------------------------------------------------

static func _revert(ctl: Control) -> void:
	if ctl == null or not ctl.has_meta(_META):
		return
	var baked = (ctl.get_meta(_META) as Dictionary).get("baked", null)
	# Write the baked value THROUGH the control's normal setter so its change signal fires — the tool's
	# existing value_changed/toggled/item_selected/text_changed plumbing then reacts exactly as if the
	# user had typed it (respecting the tool's own _loading guard, since this is a real user action).
	if ctl is SpinBox:
		(ctl as SpinBox).value = float(baked)
	elif ctl is CheckButton or ctl is CheckBox:
		# button_pressed = X only fires `toggled` when it actually changes; force via set_pressed then emit.
		var b := ctl as BaseButton
		if b.button_pressed != bool(baked):
			b.button_pressed = bool(baked)   # fires toggled
		else:
			b.emit_signal("toggled", b.button_pressed)
	elif ctl is OptionButton:
		var od := ctl as OptionButton
		var want := int(baked)
		if od.selected != want:
			od.select(want)
		od.emit_signal("item_selected", od.selected)
	elif ctl is LineEdit:
		var le := ctl as LineEdit
		le.text = String(baked)
		le.emit_signal("text_changed", le.text)
	refresh(ctl)


# Read the control's current value in the same type-space as the baked default.
static func _read(ctl: Control):
	if ctl is SpinBox:
		return (ctl as SpinBox).value
	elif ctl is CheckButton or ctl is CheckBox:
		return (ctl as BaseButton).button_pressed
	elif ctl is OptionButton:
		return (ctl as OptionButton).selected
	elif ctl is LineEdit:
		return (ctl as LineEdit).text
	return null


# Value equality tolerant of float/int mixing (SpinBox always reports float).
static func _eq(a, b) -> bool:
	if a == null or b == null:
		return a == b
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	return a == b


static func _fmt(v) -> String:
	if v is bool:
		return "on" if v else "off"
	if v is float:
		# Trim to a compact form: whole numbers show no decimals, else up to 2 places.
		if is_equal_approx(v, roundf(v)):
			return "%d" % int(roundf(v))
		return String.num(v, 2)
	return str(v)

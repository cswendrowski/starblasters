extends MarginContainer

const HologramHUDCls = preload("res://scripts/hologram_hud.gd")
const HullPipsCls = preload("res://scripts/hull_pips.gd")
const ShieldPipsCls = preload("res://scripts/shield_pips_hud.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

@onready var shield_bar = $BoxContainer/ShieldBar
@onready var hull_bar = $BoxContainer/HullBar if has_node("BoxContainer/HullBar") else null
@onready var score_counter = $BoxContainer/ScoreCounter
@onready var wave_label: Label = $BoxContainer/WaveLabel if has_node("BoxContainer/WaveLabel") else null

var hologram_hud = null
var hull_pips = null  # HullPips (HBoxContainer)
var shield_pips = null  # ShieldPipsHud (HBoxContainer)
var hull_warning: Label = null
# Machinegun ammo readout. Anchored to the bottom-right of the screen;
# hidden when the equipped CANNON is not a machinegun.
var ammo_label: Label = null
var bounty_label: Label = null
var _warning_tween: Tween = null
# Super-weapon charge pips — small icons in the right gutter under
# the bounty readout. Built lazily on bind_player.
var _super_pips_row: HBoxContainer = null
var _super_key_label: Label = null
var _super_charge_count: int = 0
var _super_charge_max: int = 0
# Weapon-readout block in the right gutter — PRI / SEC names + key hints
# pulled from InputMap so a rebinding update is automatic.
var _weapon_hints_box: VBoxContainer = null
var _pri_label: Label = null
var _sec_label: Label = null

func _ready() -> void:
	# main.tscn pins this MarginContainer to a 152×24 rect at top-left. We
	# need the HUD to span the viewport so widgets can land in both the
	# centre playfield band AND the right gutter. Override anchors here
	# and keep modest 14/14/6 margins (no band-wide squeeze — that crushed
	# the content area to zero and made the whole HUD invisible).
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 60.0
	add_theme_constant_override("margin_left", 14)
	add_theme_constant_override("margin_right", 14)
	add_theme_constant_override("margin_top", 6)

	# Keep the wave label off — banner pops carry that info.
	if wave_label:
		wave_label.visible = false
	# The legacy 8x8-pixel ScoreCounter is hard to read at native size under
	# the hologram shader. Hide it and use a proper Label with outline +
	# warm-gold tint so the bounty actually reads on screen.
	if score_counter:
		score_counter.visible = false
	# Bounty: anchored to top-right of the HUD margin, half the previous
	# size (Roman, 2026-05-17). Lives directly on the UI MarginContainer,
	# not in the vertical BoxContainer, so it doesn't fight for layout.
	bounty_label = Label.new()
	bounty_label.name = "BountyLabel"
	bounty_label.text = "BOUNTY 0"
	bounty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.style_label(bounty_label, UiTheme.LabelKind.BOUNTY)
	# Bounty kind is FONT_SIZE_BODY + 4 = 16 by default; Roman wants ~half.
	# Original BOUNTY size is 16 (FONT_SIZE_BODY+4). Half = 8; bumped to 10
	# for legibility while staying near "about half".
	bounty_label.add_theme_font_size_override("font_size", 10)
	bounty_label.add_theme_constant_override("outline_size", 1)
	# Push the bounty closer to the right edge (Roman, 2026-05-18: "check
	# the readability of the bounty counter, push it more right"). Width
	# stays generous for the BOUNTY X label but the alignment now sits
	# tight against the viewport edge.
	bounty_label.z_index = 100
	bounty_label.add_theme_color_override("font_color", UiTheme.COLOR_BOUNTY)
	# Attach directly to the parent CanvasLayer so MarginContainer's layout
	# rules don't shrink/clip the label. Pinned at the viewport's top-right
	# via absolute pixel position so anchor math can't drift.
	var canvas := get_parent() as CanvasLayer
	if canvas == null:
		canvas = get_node_or_null("/root/Main/CanvasLayer") as CanvasLayer
	# Park the bounty at the right end of the HullShieldRow so it lives
	# next to the hull bar + pips. The row is in BoxContainer; with
	# size_flags_horizontal = EXPAND_FILL on a Spacer, the bounty gets
	# pushed to the right edge of whatever width the row claims.
	# (Earlier attempts to put it directly on the CanvasLayer rendered
	# invisible — best guess is the layer is clip_contents under combat;
	# inside the row it composes through the same path as the pips.)
	# Spacer + bounty get appended after the row is built below.

	# Hull + Shield row — hull bar (sprite-based, red-tinted) on the left,
	# shield pips on the right. Layout puts a fixed left spacer + hull +
	# pips + expanding middle spacer + bounty so:
	#   - hull/pips land centred over the 216-wide playfield band
	#   - bounty pins to the right edge (in the right gutter)
	var top_row := HBoxContainer.new()
	top_row.name = "HullShieldRow"
	top_row.add_theme_constant_override("separation", 6)
	$BoxContainer.add_child(top_row)
	$BoxContainer.move_child(top_row, 0)

	# Left spacer pushes hull+pips off the left edge. 117 px (UI Designer
	# export, Roman 2026-05-19) lands hull at screen x≈131 — right at the
	# playfield band's left edge so the bar reads against the band, not
	# inside it.
	var spacer_left := Control.new()
	spacer_left.name = "SpacerLeft"
	spacer_left.custom_minimum_size = Vector2(117, 0)
	top_row.add_child(spacer_left)

	# Hide the legacy bars so they don't steal layout space.
	if hull_bar:
		hull_bar.visible = false
	if shield_bar:
		shield_bar.visible = false

	# Sprite-based hull bar — uses Roman's supplied bar_*.png + red tint.
	var hull_tex_bg: Texture2D = load("res://graphics/ui/bar_background.png")
	var hull_tex_fg: Texture2D = load("res://graphics/ui/bar_foreground_white.png")
	var hull_tpb := TextureProgressBar.new()
	hull_tpb.name = "HullBarSprite"
	hull_tpb.custom_minimum_size = Vector2(80, 12)
	hull_tpb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hull_tpb.texture_under = hull_tex_bg
	hull_tpb.texture_progress = hull_tex_fg
	hull_tpb.nine_patch_stretch = true
	hull_tpb.stretch_margin_left = 3
	hull_tpb.stretch_margin_top = 3
	hull_tpb.stretch_margin_right = 3
	hull_tpb.stretch_margin_bottom = 3
	hull_tpb.tint_progress = Color(1.0, 0.30, 0.28, 1.0)
	hull_tpb.max_value = 50
	hull_tpb.value = 50
	top_row.add_child(hull_tpb)
	hull_bar = hull_tpb

	# Shield pip strip (unchanged behavior — just moved into the row to
	# sit right of the hull bar).
	shield_pips = ShieldPipsCls.new()
	shield_pips.name = "ShieldPips"
	top_row.add_child(shield_pips)

	# Middle spacer pushes bounty to the row's right end. Once that lands
	# at x≈386 with the BoxContainer custom_minimum_size set below, bounty
	# sits inside the right gutter (x=348..480).
	var spacer_mid := Control.new()
	spacer_mid.name = "SpacerMid"
	spacer_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer_mid)

	bounty_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	bounty_label.custom_minimum_size = Vector2(80, 0)
	bounty_label.add_theme_color_override("font_color", UiTheme.COLOR_BOUNTY)
	bounty_label.z_index = 0
	bounty_label.modulate = Color(1, 1, 1, 1)
	bounty_label.visible = true
	top_row.add_child(bounty_label)

	$BoxContainer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Force BoxContainer to a 452-wide rect so the row spans the viewport.
	# UI's MarginContainer is 152×24 per main.tscn, but we already widened
	# it via anchor overrides; this minimum keeps the row from shrinking
	# back to MarginContainer's natural rect.
	$BoxContainer.custom_minimum_size = Vector2(452, 0)

	# Diegetic warning that fires when integrity drops to ≤50%.
	# Hull warning — Roman, 2026-05-18: "Move the hull damage warning to
	# under the hull bar". Anchored to the BoxContainer (left-aligned)
	# right beneath the hull/shield row, so it sits directly under the
	# red hull bar rather than centered or below the playfield.
	hull_warning = Label.new()
	hull_warning.name = "HullWarning"
	hull_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UiTheme.style_label(hull_warning, UiTheme.LabelKind.DANGER)
	hull_warning.text = "HULL COMPROMISED"
	hull_warning.add_theme_font_size_override("font_size", 11)
	hull_warning.add_theme_constant_override("outline_size", 2)
	hull_warning.visible = false
	# Insert immediately after the HullShieldRow so it sits beneath the
	# hull bar, not next to the bounty label.
	$BoxContainer.add_child(hull_warning)
	$BoxContainer.move_child(hull_warning, 1)

	# Ammo row sits directly under the bounty in the right gutter — same
	# layout trick as the hull row (left spacer + expand fill spacer
	# pushes the label to the right end of the BoxContainer).
	_install_ammo_row()

	# Now apply the hologram material to the assembled tree.
	hologram_hud = HologramHUDCls.new()
	hologram_hud.name = "HologramHUD"
	hologram_hud._hud_root = self
	add_child(hologram_hud)


func _install_ammo_row() -> void:
	var ammo_row := HBoxContainer.new()
	ammo_row.name = "AmmoRow"
	ammo_row.add_theme_constant_override("separation", 0)
	$BoxContainer.add_child(ammo_row)
	var ammo_spacer := Control.new()
	ammo_spacer.name = "AmmoSpacer"
	ammo_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ammo_row.add_child(ammo_spacer)

	if ammo_label == null or not is_instance_valid(ammo_label):
		ammo_label = Label.new()
		ammo_label.name = "AmmoLabel"
		ammo_label.text = "AMMO 0"
		UiTheme.style_label(ammo_label, UiTheme.LabelKind.BOUNTY)
		ammo_label.add_theme_font_size_override("font_size", 10)
		ammo_label.add_theme_constant_override("outline_size", 1)
		ammo_label.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	ammo_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	ammo_label.custom_minimum_size = Vector2(80, 0)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label.visible = false
	if ammo_label.get_parent() != null and ammo_label.get_parent() != ammo_row:
		ammo_label.get_parent().remove_child(ammo_label)
	if ammo_label.get_parent() == null:
		ammo_row.add_child(ammo_label)


func bind_player(player) -> void:
	if hologram_hud:
		hologram_hud.bind_player(player)
	if shield_pips and shield_pips.has_method("bind_player"):
		shield_pips.bind_player(player)
	# Ammo HUD — wire up via the player's ammo_changed signal. Hidden when
	# weapon_style != machinegun.
	_install_ammo_label()
	if player and player.has_signal("ammo_changed"):
		if not player.ammo_changed.is_connected(_on_ammo_changed):
			player.ammo_changed.connect(_on_ammo_changed)
		_on_ammo_changed(player.ammo if "ammo" in player else -1)
		# Also poll weapon_style to decide visibility — energy = hidden,
		# machinegun = shown.
		if "weapon_style" in player:
			_set_ammo_visible(String(player.weapon_style) == "machinegun")
	# Standalone showcase bind: main.tscn wires hull_changed via the scene
	# connection table, but the showcase instantiates ui.tscn manually and that
	# connection doesn't exist. So we wire it here defensively.
	if player and player.has_signal("hull_changed"):
		if not player.hull_changed.is_connected(update_hull):
			player.hull_changed.connect(update_hull)
	if player and player.has_signal("shield_changed"):
		if not player.shield_changed.is_connected(update_shield):
			player.shield_changed.connect(update_shield)
	# Super-charge indicator: small pip strip in the right gutter under
	# the bounty label. Updated by super_charges_changed signal.
	_install_super_pips()
	if player and player.has_signal("super_charges_changed"):
		if not player.super_charges_changed.is_connected(_on_super_charges_changed):
			player.super_charges_changed.connect(_on_super_charges_changed)
		# Seed with the current state in case the part already applied.
		if "super_charges" in player and "max_super_charges" in player:
			_on_super_charges_changed(int(player.super_charges), int(player.max_super_charges))
	# Weapon-name + key-hint readout in the right gutter (Roman playtest
	# 2026-05-23). Reads Run.loadout_snapshot + InputMap; refreshes on
	# every bind_player so a weapon swap at the outpost shows up on the
	# next combat scene.
	_install_weapon_hints()
	# Seed once from current values.
	if player and "max_hull" in player and "hull" in player:
		update_hull(player.max_hull, player.hull)
	if player and "max_shield" in player and "shield" in player:
		update_shield(player.max_shield, player.shield)


func flicker_in(duration: float = 0.6) -> void:
	if hologram_hud and hologram_hud.has_method("flicker_in"):
		hologram_hud.flicker_in(duration)


func flicker_out(duration: float = 0.5) -> void:
	if hologram_hud and hologram_hud.has_method("flicker_out"):
		hologram_hud.flicker_out(duration)

func update_score(value):
	if bounty_label:
		bounty_label.text = "BOUNTY %d" % int(value)
	if score_counter and score_counter.has_method("display_digits"):
		score_counter.display_digits(value)

# Hull-bar fill colors. Blue when at least one shield charge is up (Roman,
# 2026-05-17: "visual indicator that hull is protected"); red otherwise.
const HULL_COLOR_UNPROTECTED := Color(1.0, 0.30, 0.28, 1.0)
const HULL_COLOR_SHIELDED    := Color(0.30, 0.65, 1.00, 1.0)


func update_shield(max_value, value):
	# Shield rendering moved to the pip strip — listens to the player's
	# shield_changed signal directly via bind_player(). Keep this method
	# for backward-compat with main.tscn's connection table.
	if shield_bar:
		shield_bar.max_value = max_value
		shield_bar.value = value
	# Hull bar tint reflects shield state: blue while at least one charge
	# is up, red once the last charge breaks.
	if hull_bar and hull_bar is TextureProgressBar:
		var protected: bool = int(value) >= 1
		(hull_bar as TextureProgressBar).tint_progress = HULL_COLOR_SHIELDED if protected else HULL_COLOR_UNPROTECTED

func update_hull(max_value, value):
	if hull_bar:
		hull_bar.max_value = max(1, int(max_value))
		hull_bar.value = clamp(int(value), 0, int(max_value))
	# Warning element: visible when integrity at or below 50%.
	if hull_warning:
		var pct: float = (float(value) / max(float(max_value), 0.001))
		var should_warn: bool = pct <= 0.5 and value > 0
		if should_warn and not hull_warning.visible:
			hull_warning.visible = true
			_start_warning_pulse()
		elif not should_warn and hull_warning.visible:
			hull_warning.visible = false
			if _warning_tween and _warning_tween.is_valid():
				_warning_tween.kill()

func update_wave(idx: int, total: int) -> void:
	if wave_label:
		wave_label.text = "WAVE %d / %d" % [idx + 1, total]
		# Crisp outline so the hologram shader's edge fade doesn't eat the
		# top of the text. Kick added every time in case theme overrides
		# were reset.
		wave_label.add_theme_color_override("font_outline_color", Color(0.1, 0.4, 0.45, 1))
		wave_label.add_theme_constant_override("outline_size", 5)
		# Brief pop animation — settles to fully opaque.
		wave_label.modulate = Color(1, 1, 0.4, 1)
		var tw = wave_label.create_tween()
		tw.tween_property(wave_label, "modulate", Color(1, 1, 1, 1.0), 0.6)

func _install_ammo_label() -> void:
	# Ammo label is now provisioned by _install_right_gutter() so it sits in
	# the reserved right gutter alongside bounty. Kept as a no-op so the
	# showcase path that called this before bind_player still works.
	pass


func _on_ammo_changed(value: int) -> void:
	if ammo_label == null:
		return
	if value < 0:
		_set_ammo_visible(false)
		return
	ammo_label.text = "AMMO %d" % value
	_set_ammo_visible(true)


func _set_ammo_visible(v: bool) -> void:
	if ammo_label:
		ammo_label.visible = v


# Build the super-charge pip strip — a row of small diamond/pill markers
# below the bounty readout. Lit pips = charges remaining; dim pips =
# spent. Anchored to the BoxContainer so it rides the same layout flow
# as the other HUD widgets.
func _install_super_pips() -> void:
	if _super_pips_row != null and is_instance_valid(_super_pips_row):
		return
	# Wrapper row: [expand-spacer] [pips] [gap] [key hint] — pinned to the
	# right gutter via SHRINK_END on the inner row, same layout trick as
	# the bounty/ammo rows.
	var wrap := HBoxContainer.new()
	wrap.name = "SuperRow"
	wrap.add_theme_constant_override("separation", 3)
	var wrap_spacer := Control.new()
	wrap_spacer.name = "SuperSpacer"
	wrap_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(wrap_spacer)
	var row := HBoxContainer.new()
	row.name = "SuperPips"
	row.add_theme_constant_override("separation", 2)
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	wrap.add_child(row)
	# Super-fire key hint, faded so it doesn't shout next to the pips.
	# Roman playtest 2026-05-23: "give a hint about the button to hit
	# next to the Super ammo count".
	var key_lbl := Label.new()
	key_lbl.name = "SuperKey"
	UiTheme.style_label(key_lbl, UiTheme.LabelKind.BOUNTY)
	key_lbl.add_theme_font_size_override("font_size", 8)
	key_lbl.add_theme_constant_override("outline_size", 1)
	key_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	key_lbl.text = "[%s]" % _action_key_label("shoot_nose")
	key_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
	wrap.add_child(key_lbl)
	_super_key_label = key_lbl
	if has_node("BoxContainer"):
		$BoxContainer.add_child(wrap)
	else:
		add_child(wrap)
	_super_pips_row = row


# Pull the first keyboard binding for an action and return a short human
# label ("Space", "X", "C", "Shift"). Empty string if the action has no
# keyboard event. Reads InputMap so HUD updates on rebind.
func _action_key_label(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var kc: int = (ev as InputEventKey).physical_keycode
			if kc == 0:
				kc = (ev as InputEventKey).keycode
			if kc == 0:
				continue
			var s: String = OS.get_keycode_string(kc)
			# OS returns "Space" / "X" / "Shift" — pass through; uppercase
			# single letters look correct at HUD size already.
			return s
	return ""


# Right-gutter weapon readout: "PRI <name> [Key]" + "SEC <name> [Key]".
# Names pull from Run.loadout_snapshot so swaps at outposts reflect on
# next combat entry (the HUD is rebuilt with each Main scene). Keys pull
# from InputMap.
func _install_weapon_hints() -> void:
	if _weapon_hints_box != null and is_instance_valid(_weapon_hints_box):
		_refresh_weapon_hints()
		return
	# Wrapper row aligns the VBox to the right edge — same SHRINK_END
	# trick as bounty / super.
	var wrap := HBoxContainer.new()
	wrap.name = "WeaponHintsRow"
	wrap.add_theme_constant_override("separation", 0)
	var sp := Control.new()
	sp.name = "WeaponHintsSpacer"
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(sp)
	var box := VBoxContainer.new()
	box.name = "WeaponHints"
	box.add_theme_constant_override("separation", 0)
	box.size_flags_horizontal = Control.SIZE_SHRINK_END
	wrap.add_child(box)
	_pri_label = _make_weapon_hint_label("PriLabel")
	_sec_label = _make_weapon_hint_label("SecLabel")
	box.add_child(_pri_label)
	box.add_child(_sec_label)
	if has_node("BoxContainer"):
		$BoxContainer.add_child(wrap)
	else:
		add_child(wrap)
	_weapon_hints_box = box
	_refresh_weapon_hints()


func _make_weapon_hint_label(node_name: String) -> Label:
	var l := Label.new()
	l.name = node_name
	UiTheme.style_label(l, UiTheme.LabelKind.BOUNTY)
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_constant_override("outline_size", 1)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _refresh_weapon_hints() -> void:
	if _pri_label == null or _sec_label == null:
		return
	const Slots = preload("res://scripts/weapons/SlotTypes.gd")
	var pri_name: String = "—"
	var sec_name: String = "—"
	if has_node("/root/Run"):
		var run = get_node("/root/Run")
		if "loadout_snapshot" in run and run.loadout_snapshot is Dictionary:
			var p_cannon = run.loadout_snapshot.get(Slots.SlotType.CANNON, null)
			if p_cannon != null and "display_name" in p_cannon:
				pri_name = String(p_cannon.display_name)
			var p_sec = run.loadout_snapshot.get(Slots.SlotType.HARDPOINT_WING, null)
			if p_sec != null and "display_name" in p_sec:
				sec_name = String(p_sec.display_name)
	var pri_key: String = _action_key_label("shoot")
	var sec_key: String = _action_key_label("shoot2")
	_pri_label.text = "PRI %s [%s]" % [pri_name, pri_key]
	_sec_label.text = "SEC %s [%s]" % [sec_name, sec_key]


func _on_super_charges_changed(value: int, maximum: int) -> void:
	_super_charge_count = value
	_super_charge_max = maximum
	if _super_pips_row == null or not is_instance_valid(_super_pips_row):
		return
	# Rebuild pips when max changes (Mk upgrade or new super equipped).
	if _super_pips_row.get_child_count() != maximum:
		for c in _super_pips_row.get_children():
			c.queue_free()
		for i in maximum:
			var pip := ColorRect.new()
			pip.size = Vector2(5, 7)
			pip.custom_minimum_size = Vector2(5, 7)
			_super_pips_row.add_child(pip)
	# Repaint: filled (gold) for charges remaining, dim (grey) for spent.
	var pips := _super_pips_row.get_children()
	for i in pips.size():
		var pip: ColorRect = pips[i] as ColorRect
		if pip == null:
			continue
		pip.color = Color(1.0, 0.85, 0.3, 1.0) if i < value else Color(0.3, 0.3, 0.3, 0.7)


# Style a ProgressBar as a flat %-bar with a colored fill + dark BG.
# Same recipe for hull + shield so both bars read consistently.
func _style_pct_bar(bar, fill: Color, bg: Color) -> void:
	# Bars in the scene may be ProgressBar OR the legacy TextureProgressBar
	# variant. Theme overrides only work on ProgressBar; modulate is what
	# we can drive on both.
	if bar == null:
		return
	if bar is ProgressBar:
		var sb_fill := StyleBoxFlat.new()
		sb_fill.bg_color = fill
		sb_fill.corner_radius_top_left = 2
		sb_fill.corner_radius_top_right = 2
		sb_fill.corner_radius_bottom_left = 2
		sb_fill.corner_radius_bottom_right = 2
		bar.add_theme_stylebox_override("fill", sb_fill)
		var sb_bg := StyleBoxFlat.new()
		sb_bg.bg_color = bg
		sb_bg.border_color = Color(0, 0, 0, 0.6)
		sb_bg.border_width_left = 1
		sb_bg.border_width_top = 1
		sb_bg.border_width_right = 1
		sb_bg.border_width_bottom = 1
		bar.add_theme_stylebox_override("background", sb_bg)
		(bar as ProgressBar).show_percentage = true
	else:
		# TextureProgressBar — drive the tint via modulate as a best-effort.
		bar.modulate = fill


func _start_warning_pulse() -> void:
	if hull_warning == null:
		return
	if _warning_tween and _warning_tween.is_valid():
		_warning_tween.kill()
	hull_warning.modulate.a = 1.0
	_warning_tween = create_tween().set_loops()
	_warning_tween.tween_property(hull_warning, "modulate:a", 0.35, 0.45).set_trans(Tween.TRANS_SINE)
	_warning_tween.tween_property(hull_warning, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE)

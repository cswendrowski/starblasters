extends Control

# Progression Choice mockup — three-card UI + persistent sector progress
# bar. Cycles through sector positions 1..6 so the designer can see how
# the weighting shifts and how the bar fills.
#
# Spec: docs/progression_3pick_proposal_2026-05-21.md

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SceneTransition = preload("res://scripts/scene_transition.gd")
const BackdropScript = preload("res://scripts/galaxy_backdrop.gd")

const SECTOR_TOTAL := 6

# Node types + the per-position weight table from the spec.
const NODE_TYPES := {
	"COMBAT_NORMAL":   {"label": "COMBAT",        "desc": "Standard wave",                "reward": "+150 bounty"},
	"COMBAT_ELITE":    {"label": "ELITE COMBAT",  "desc": "Tough wave w/ mini-boss",      "reward": "+300 bounty"},
	"HAZARD_MINEFIELD":{"label": "MINEFIELD",     "desc": "Dense mine hazard",            "reward": "+200 bounty"},
	"HAZARD_ASTEROIDS":{"label": "ASTEROIDS",     "desc": "Asteroid field hazard",        "reward": "+200 bounty"},
	"OUTPOST":         {"label": "OUTPOST",       "desc": "Shop, super refill",           "reward": "Spend bounty"},
	"SIGNAL_EVENT":    {"label": "SIGNAL EVENT",  "desc": "Narrative choice",             "reward": "Varies"},
	"TREASURE":        {"label": "TREASURE",      "desc": "Bounty cache or Part roll",    "reward": "+1 Part"},
	"BOSS":            {"label": "BOSS",          "desc": "Sector boss",                  "reward": "+huge bounty"},
}

# Per-position weight table — see proposal §"Pick generation".
const POSITION_WEIGHTS := [
	# Position 1 (start): combat-heavy
	{"COMBAT_NORMAL": 0.70, "HAZARD_MINEFIELD": 0.10, "HAZARD_ASTEROIDS": 0.10, "SIGNAL_EVENT": 0.10},
	# Position 2
	{"COMBAT_NORMAL": 0.35, "COMBAT_ELITE": 0.20, "HAZARD_MINEFIELD": 0.15, "HAZARD_ASTEROIDS": 0.10, "OUTPOST": 0.10, "SIGNAL_EVENT": 0.10},
	# Position 3
	{"COMBAT_NORMAL": 0.30, "COMBAT_ELITE": 0.25, "HAZARD_MINEFIELD": 0.10, "HAZARD_ASTEROIDS": 0.10, "OUTPOST": 0.15, "SIGNAL_EVENT": 0.05, "TREASURE": 0.05},
	# Position 4
	{"COMBAT_NORMAL": 0.25, "COMBAT_ELITE": 0.30, "HAZARD_MINEFIELD": 0.15, "OUTPOST": 0.15, "SIGNAL_EVENT": 0.05, "TREASURE": 0.10},
	# Position 5 (penultimate) — handled specially in _generate_choices to force OUTPOST
	{"COMBAT_NORMAL": 0.30, "COMBAT_ELITE": 0.35, "HAZARD_MINEFIELD": 0.20, "OUTPOST": 0.15},
	# Position 6 — boss only (no choices presented)
]

var _position: int = 1  # 1..SECTOR_TOTAL
var _cards: Array = []  # array of {root, type_key, button}
var _progress_fill: ColorRect = null
var _progress_label: Label = null
var _seed: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seed = randi()
	_build_backdrop()
	_build_ui()
	_refresh_choices()


func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var bd := Node2D.new()
	bd.name = "Backdrop"
	bd.set_script(BackdropScript)
	bd.modulate = Color(1, 1, 1, 0.4)  # dim so cards read clearly
	add_child(bd)


func _build_ui() -> void:
	var header := Label.new()
	header.text = "PROGRESSION MOCKUP — pick a node to advance"
	header.position = Vector2(8, 6)
	UiTheme.style_label(header, UiTheme.LabelKind.HEADER)
	header.add_theme_font_size_override("font_size", 10)
	add_child(header)

	# Three cards centered in the viewport.
	var card_width: float = 130.0
	var card_height: float = 150.0
	var gap: float = 12.0
	var total_width: float = card_width * 3.0 + gap * 2.0
	var start_x: float = (480.0 - total_width) * 0.5
	var card_y: float = 50.0
	for i in 3:
		var card := _make_card(Vector2(start_x + i * (card_width + gap), card_y), Vector2(card_width, card_height))
		add_child(card["root"])
		_cards.append(card)

	# Sector Progress bar.
	var bar_y: float = 220.0
	var bar_label := Label.new()
	bar_label.text = "Sector 1"
	bar_label.position = Vector2(40, bar_y - 14)
	UiTheme.style_label(bar_label, UiTheme.LabelKind.CAPTION)
	bar_label.add_theme_font_size_override("font_size", 7)
	add_child(bar_label)
	_progress_label = Label.new()
	_progress_label.text = "Node 1 / %d" % SECTOR_TOTAL
	_progress_label.position = Vector2(360, bar_y - 14)
	_progress_label.size = Vector2(80, 8)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.style_label(_progress_label, UiTheme.LabelKind.CAPTION)
	_progress_label.add_theme_font_size_override("font_size", 7)
	add_child(_progress_label)
	var bar_bg := Panel.new()
	bar_bg.position = Vector2(40, bar_y)
	bar_bg.size = Vector2(400, 10)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.85)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	bar_bg.add_theme_stylebox_override("panel", sb)
	add_child(bar_bg)
	_progress_fill = ColorRect.new()
	_progress_fill.color = Color(0.62, 0.82, 1.00, 0.85)
	_progress_fill.position = Vector2(41, bar_y + 1)
	_progress_fill.size = Vector2(0, 8)
	add_child(_progress_fill)
	# Boss icon at right end of bar.
	var boss_icon := Label.new()
	boss_icon.text = "BOSS"
	boss_icon.position = Vector2(442, bar_y - 1)
	boss_icon.add_theme_font_size_override("font_size", 6)
	boss_icon.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
	add_child(boss_icon)

	# Dev controls — cycle position + reseed + back.
	var ctrl_y: float = 244.0
	_add_button(Vector2(8, ctrl_y), Vector2(78, 14), "← Prev pos", _on_prev)
	_add_button(Vector2(90, ctrl_y), Vector2(78, 14), "Next pos →", _on_next)
	_add_button(Vector2(172, ctrl_y), Vector2(78, 14), "Re-roll", _on_reroll)
	_add_button(Vector2(395, ctrl_y), Vector2(78, 14), "Back to Dev Menu", _on_back)


func _make_card(pos: Vector2, sz: Vector2) -> Dictionary:
	var root := Panel.new()
	root.position = pos
	root.size = sz
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.11, 0.92)
	sb.border_color = UiTheme.COLOR_ACCENT_DIM
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	root.add_theme_stylebox_override("panel", sb)
	# Type label
	var type_lbl := Label.new()
	type_lbl.name = "TypeLabel"
	type_lbl.position = Vector2(6, 8)
	type_lbl.size = Vector2(sz.x - 12, 14)
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_lbl.add_theme_font_size_override("font_size", 9)
	type_lbl.add_theme_color_override("font_color", UiTheme.COLOR_ACCENT)
	root.add_child(type_lbl)
	# Icon placeholder (block of color reflecting node type).
	var icon := ColorRect.new()
	icon.name = "Icon"
	icon.position = Vector2(sz.x * 0.25, 26)
	icon.size = Vector2(sz.x * 0.5, sz.x * 0.5)
	icon.color = Color(0.3, 0.4, 0.5)
	root.add_child(icon)
	# Desc
	var desc := Label.new()
	desc.name = "DescLabel"
	desc.position = Vector2(6, 26 + sz.x * 0.5 + 4)
	desc.size = Vector2(sz.x - 12, 24)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 7)
	desc.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(desc)
	# Reward
	var reward := Label.new()
	reward.name = "RewardLabel"
	reward.position = Vector2(6, sz.y - 24)
	reward.size = Vector2(sz.x - 12, 10)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward.add_theme_font_size_override("font_size", 7)
	reward.add_theme_color_override("font_color", UiTheme.COLOR_BOUNTY)
	root.add_child(reward)
	# Pick button
	var btn := Button.new()
	btn.name = "PickButton"
	btn.text = "Pick"
	btn.position = Vector2(sz.x * 0.5 - 28, sz.y - 14)
	btn.size = Vector2(56, 12)
	btn.add_theme_font_size_override("font_size", 7)
	UiTheme.style_button(btn, true)
	root.add_child(btn)
	return {"root": root, "type_key": "", "button": btn, "type_label": type_lbl, "icon": icon, "desc": desc, "reward": reward}


func _refresh_choices() -> void:
	var picks := _generate_choices(_position)
	for i in _cards.size():
		var card = _cards[i]
		# Disconnect any prior signal so card 3-2-1 click chains don't stack.
		var btn: Button = card["button"]
		if btn.pressed.is_connected(_on_card_picked):
			btn.pressed.disconnect(_on_card_picked)
		if i >= picks.size():
			card["root"].visible = false
			continue
		card["root"].visible = true
		var type_key: String = picks[i]
		var meta: Dictionary = NODE_TYPES[type_key]
		card["type_key"] = type_key
		(card["type_label"] as Label).text = meta["label"]
		(card["desc"] as Label).text = meta["desc"]
		(card["reward"] as Label).text = meta["reward"]
		(card["icon"] as ColorRect).color = _icon_color_for(type_key)
		btn.pressed.connect(_on_card_picked.bind(i))
	# Boss-only position: hide cards, show a single "ENTER BOSS" card.
	if _position >= SECTOR_TOTAL:
		for i in _cards.size():
			_cards[i]["root"].visible = (i == 1)
		if _cards.size() > 1:
			var center = _cards[1]
			(center["type_label"] as Label).text = "BOSS"
			(center["desc"] as Label).text = "Sector boss — fight begins on pick"
			(center["reward"] as Label).text = "+huge bounty"
			(center["icon"] as ColorRect).color = Color(1.0, 0.4, 0.35)
	_refresh_progress_bar()


func _generate_choices(pos: int) -> Array:
	# Position 6 → boss only.
	if pos >= SECTOR_TOTAL:
		return ["BOSS"]
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + pos * 1009
	# Position 5 — force outpost in slot 0, fill 1+2 from the weighted pool.
	if pos == SECTOR_TOTAL - 1:
		var picks: Array = ["OUTPOST"]
		var weights: Dictionary = POSITION_WEIGHTS[pos - 1]
		while picks.size() < 3:
			var pick = _weighted_pick(weights, rng)
			if not picks.has(pick):
				picks.append(pick)
		return picks
	# Standard: pick 3 distinct types from the position's weight table.
	var weights2: Dictionary = POSITION_WEIGHTS[pos - 1]
	var out: Array = []
	var safety: int = 0
	while out.size() < 3 and safety < 50:
		safety += 1
		var pick = _weighted_pick(weights2, rng)
		if not out.has(pick):
			out.append(pick)
	return out


func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total: float = 0.0
	for w in weights.values():
		total += float(w)
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for key in weights.keys():
		acc += float(weights[key])
		if roll <= acc:
			return key
	return weights.keys()[0]


func _icon_color_for(type_key: String) -> Color:
	match type_key:
		"COMBAT_NORMAL":   return Color(0.62, 0.82, 1.00)
		"COMBAT_ELITE":    return Color(1.00, 0.60, 0.40)
		"HAZARD_MINEFIELD":return Color(0.85, 0.55, 0.20)
		"HAZARD_ASTEROIDS":return Color(0.70, 0.65, 0.55)
		"OUTPOST":         return Color(0.40, 0.85, 0.65)
		"SIGNAL_EVENT":    return Color(0.85, 0.70, 1.00)
		"TREASURE":        return Color(1.00, 0.85, 0.42)
		"BOSS":            return Color(1.00, 0.40, 0.32)
	return Color(0.5, 0.5, 0.5)


func _refresh_progress_bar() -> void:
	var frac: float = float(_position - 1) / float(SECTOR_TOTAL)  # progress AT the choice screen for this position
	if _progress_fill:
		var max_w: float = 398.0
		_progress_fill.size.x = lerp(0.0, max_w, clampf(frac, 0.0, 1.0))
	if _progress_label:
		_progress_label.text = "Node %d / %d" % [_position, SECTOR_TOTAL]


# Dev controls ---------------------------------------------------------------

func _add_button(pos: Vector2, sz: Vector2, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = sz
	b.add_theme_font_size_override("font_size", 7)
	UiTheme.style_button(b, true)
	b.pressed.connect(cb)
	add_child(b)


func _on_card_picked(_idx: int) -> void:
	# Advance the position; in real flow this would transition to the picked
	# node's scene. The mockup just bumps the position counter.
	_position = clampi(_position + 1, 1, SECTOR_TOTAL)
	_refresh_choices()


func _on_prev() -> void:
	_position = clampi(_position - 1, 1, SECTOR_TOTAL)
	_refresh_choices()


func _on_next() -> void:
	_position = clampi(_position + 1, 1, SECTOR_TOTAL)
	_refresh_choices()


func _on_reroll() -> void:
	_seed = randi()
	_refresh_choices()


func _on_back() -> void:
	SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_back()

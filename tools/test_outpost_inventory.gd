extends SceneTree

# Headless driver for the OutpostArrival dock inventory + shop MOCK: exercises every action
# path (info popup, pull, lock-guarded scrap, slot/swap, buy, sell → buyback → buy-back,
# node-complete price reset, scrap installed) so a regression in the click handlers is caught
# without a real click. Card/popup construction is what we verify — the ops are dict/array work.

var _oa

func _init() -> void:
	_oa = load("res://scenes/outpost_arrival.tscn").instantiate()
	_oa.manage_hd_scope = true
	_oa.damage_level = 0.7
	get_root().add_child(_oa)
	var t := Timer.new()
	t.wait_time = 0.3
	t.one_shot = true
	t.autostart = true   # _ready builds the panels a frame after add_child; let it settle
	t.timeout.connect(_run)
	get_root().add_child(t)

func _run() -> void:
	_oa._money = 9999   # Run.bounty is 0 headless; fund the purchases

	# Info popup (mark ladder) open + close.
	_oa._show_info(_oa._slots["PRIMARY"])
	_oa._close_info()

	# Pull installed → hold; lock-guarded scrap (locked blocks); unlock.
	_oa._pull("PRIMARY")
	_oa._toggle_lock(0)
	var before: int = _oa._hold.size()
	_oa._scrap_hold(0)                  # locked → no-op
	assert(_oa._hold.size() == before)
	_oa._toggle_lock(0)

	# Slot a hold item back (or swap if its slot kind is full).
	var kind: String = _oa._hold[0]["kind"]
	var empty: String = _oa._empty_target(kind)
	if empty != "":
		_oa._slot_from_hold(0, empty)
	else:
		_oa._swap_from_hold(0)

	# Buy a market entry → hold (entry consumed).
	var mkt_n: int = _oa._market.size()
	_oa._buy_market(_oa._market[0])
	assert(_oa._market.size() == mkt_n - 1)

	# Sell a hold item → 20% money + a buyback listing in the market.
	var money_before: int = _oa._money
	_oa._sell_hold(0)
	assert(_oa._money > money_before)
	var bb = null
	for e in _oa._market:
		if e.get("buyback", false):
			bb = e
			break
	assert(bb != null)

	# Buy it back, then sell another and complete the node → buyback clears (full price).
	_oa._buy_market(bb)
	if _oa._hold.size() > 0:
		_oa._sell_hold(0)
	_oa._complete_node_shop()
	for e in _oa._market:
		assert(not e.get("buyback", false))

	# Scrap an installed module (the scrap-mode slot action) → materials.
	_oa._set_shop_mode(OutpostArrival.ShopMode.SCRAP)
	var mats_before: int = _oa._materials
	_oa._scrap_slot("MODULE_2")
	assert(_oa._materials > mats_before)
	_oa._set_shop_mode(OutpostArrival.ShopMode.NONE)

	# Repair walks damage back DOWN live → shader + tells removed.
	_oa.set_damage(0.8)
	_oa.repair(0.0, 0.0)
	assert(_oa.damage_level == 0.0)

	print("INV ok; hold=%d money=%d materials=%d market=%d" % [_oa._hold.size(), _oa._money, _oa._materials, _oa._market.size()])
	print("VERDICT: PASS")
	quit()

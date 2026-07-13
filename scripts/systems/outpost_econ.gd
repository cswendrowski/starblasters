class_name OutpostEcon
extends RefCounted

# OutpostEcon — the single static cost engine for every outpost transaction.
#
# WHY THIS EXISTS: the condition-aware cost math used to live only in the LEGACY
# outpost scene (scripts/screens/outpost.gd), while the LIVE dock
# (scripts/screens/outpost_arrival.gd) hardcoded flat prices — so ALL economy
# Sector-Conditions were dead in production. This module is the SSOT both scenes
# now call, so display and spend can never drift and the math lives in ONE place
# (CLAUDE.md: reusable systems over bespoke islands).
#
# Every function takes `run` (the Run autoload) and is NULL-SAFE: a null run
# yields the baseline cost (no conditions applied). The math here is a
# bit-identical lift of the original outpost.gd helpers — rounding, floors, and
# guard order preserved.
#
# All condition reads go through Run.cond_scalar / cond_sum / cond_flag, which
# delegate to Conditions.* aggregators (scalar = product, sum = additive,
# flag = OR). The condition ids that feed each key are documented per function.

# Baseline material cost of a hull repair. Repairs ALWAYS cost a material at
# baseline (Roman 2026-07-11, design §8); the repair Conditions adjust the count.
# This is the model's SSOT (moved here from outpost.gd).
const REPAIR_BASE_MATERIALS := 1


# Hull-repair cost split into {bounty, mats}. The caller passes `base_bounty`
# already Mk9-discounted (if its scene has that perk) — this only folds the
# Condition econ hooks on top.
#   Bounty side — Costly Repairs (econ.repair_cost_mult ×1.5) /
#                 Cheap Repairs (econ.repair_no_bounty → 0).
#   Mats side   — REPAIR_BASE_MATERIALS + Complex/Cheap Repairs
#                 (econ.repair_mat_delta +1) / Easy Repairs (econ.repair_no_mats → 0).
static func repair_costs(run, base_bounty: int) -> Dictionary:
	var bounty: int = base_bounty
	var mats: int = REPAIR_BASE_MATERIALS
	if run != null:
		if run.cond_flag("econ.repair_no_bounty"):
			bounty = 0
		else:
			bounty = roundi(base_bounty * run.cond_scalar("econ.repair_cost_mult"))
		if run.cond_flag("econ.repair_no_mats"):
			mats = 0
		else:
			mats = REPAIR_BASE_MATERIALS + int(run.cond_sum("econ.repair_mat_delta"))
	return {"bounty": bounty, "mats": mats}


# Flat restock cost (super refill, whole-magazine ammo refill). Scaled by
# Costly Restock (econ.restock_cost_mult ×1.5) / Cheap Restock (×0.7).
# Floors at 1 so a cheap restock never becomes free.
static func restock_cost(run, base: int) -> int:
	if run == null:
		return base
	return maxi(1, roundi(base * run.cond_scalar("econ.restock_cost_mult")))


# Per-round ammo cost with the restock mult folded in — for scenes that do
# partial (per-round) refills. Keeps the ceil/floor partial math structurally
# intact by scaling the RATE, not the total (a flat restock_cost's maxi(1)
# floor would corrupt the zero-missing / affordable-rounds edge cases).
# Same condition source as restock_cost (econ.restock_cost_mult).
static func restock_per_round(run, base: float) -> float:
	if run == null:
		return base
	return base * run.cond_scalar("econ.restock_cost_mult")


# Upgrade cost split into {mats, bounty}. `base_bounty` is the scene's raw
# upgrade labor fee (before Conditions).
#   Mats   — ceil(new_mk × econ.upgrade_mat_mult); Cheap Upgrades
#            (econ.upgrade_no_mats) zeroes it. Complex Upgrades sets mat_mult 1.5.
#   Bounty — round(base_bounty × econ.upgrade_bounty_mult); Easy Upgrades
#            (econ.upgrade_no_bounty) zeroes it. Costly Upgrades sets bounty_mult 1.5.
static func upgrade_costs(run, new_mk: int, base_bounty: int) -> Dictionary:
	if run == null:
		return {"mats": new_mk, "bounty": base_bounty}
	var mats: int = 0 if run.cond_flag("econ.upgrade_no_mats") else ceili(new_mk * run.cond_scalar("econ.upgrade_mat_mult"))
	var bounty: int = 0 if run.cond_flag("econ.upgrade_no_bounty") else roundi(base_bounty * run.cond_scalar("econ.upgrade_bounty_mult"))
	return {"mats": mats, "bounty": bounty}


# Shop offer buy price. Scaled by Galactic Tariffs (econ.shop_price_mult ×1.2) /
# Buyer's Market (×0.8). Floors at 1.
static func offer_price(run, base: int) -> int:
	if run == null:
		return base
	return maxi(1, roundi(base * run.cond_scalar("econ.shop_price_mult")))


# Number of offers the shop stocks. Shifted by Market Scarcity
# (econ.stock_delta −1) / Market Surplus (+1). Floors at 1.
static func stock_count(run, base: int) -> int:
	if run == null:
		return base
	return maxi(1, base + int(run.cond_sum("econ.stock_delta")))


# Bias a rolled Mk by Shoddy Imports (econ.mk_bias −1) / Quality Goods (+1),
# clamped to [1, cap]. `cap` is the shop's per-visit Mk ceiling.
static func bias_mark(run, mk: int, cap: int) -> int:
	if run == null:
		return clampi(mk, 1, cap)
	return clampi(mk + int(run.cond_sum("econ.mk_bias")), 1, cap)

class_name OutpostHelpStrings
extends Object

# All user-visible text for the outpost dock's ? help overlay + the top-bar resource tooltips.
# Kept human-editable in one place. Referenced by scripts/screens/outpost_arrival.gd.
# Resources are spelled out by NAME (Bounty / Materials / Hull / Super) rather than glyphs.

# ---- Resource tooltips (top-bar stat fields) ----
const TIP_HULL := "HULL — your ship's structural integrity (current / max).\nRepair it here; if it's depleted in combat your patrol ends."
const TIP_SUPER := "SUPER — Super Pulse Bomb charges (your panic weapon, fired with X).\nRefill charges here."
const TIP_BOUNTY := "BOUNTY — earned by destroying enemies and clearing sectors.\nSpent on parts, repairs, refills, and upgrades. Resets each patrol."
const TIP_MATERIALS := "MATERIALS — salvage from scrapping parts and from Signal events.\nSpent alongside Bounty to upgrade equipped parts."

# ---- Help overlay ----
const HELP_TITLE := "OUTPOST — HOW IT WORKS"
const HELP_INTRO := "Dock between sectors to REPAIR, REARM, and RE-EQUIP. The LEFT panel is the Trade Post (Market + Services); the RIGHT panel is your Ship Status (Armaments / Systems / Hold)."

const HELP_HEAD_RESOURCES := "Top bar — resources  (hover any for a tooltip)"
const HELP_HULL := "HULL — your ship's integrity. Repair it here; if it's depleted in combat your patrol ends."
const HELP_SUPER := "SUPER — Super Pulse Bomb charges (your panic weapon, fired with X). Refill here."
const HELP_BOUNTY := "BOUNTY — earned from kills and sector clears. Spent on parts, repairs, refills, and upgrades. Resets each patrol."
const HELP_MATERIALS := "MATERIALS — salvage from scrapping parts and Signal events. Spent alongside Bounty to upgrade parts."

const HELP_HEAD_MARKET := "Trade Post — MARKET"
const HELP_MARKET := "Parts for sale, priced in Bounty. Buying sends the part to your HOLD (it isn't auto-equipped). A part you sell lists here for BUYBACK until you depart."
const HELP_MARKET_INFO := "The Info button opens full stats and a Mark track — tap any Mark to preview what an upgrade buys before you pay."

const HELP_HEAD_SERVICES := "Trade Post — SERVICES"
const HELP_SERVICES := "Repair Hull and Refill Primary / Secondary / Super. The 1 button does one pip or charge; All tops it up. Both gray out when it's already full or you can't afford it."
const HELP_MODES_INTRO := "Below the refills are three MODES — tap a mode, then tap an owned part on the right:"
const HELP_MODE_SCRAP := "SCRAP — break a part down into Materials."
const HELP_MODE_SELL := "SELL — sell a part for Bounty (a fraction of its value; buyable back until you depart)."
const HELP_MODE_UPGRADE := "UPGRADE — raise a part's Mark. Costs Materials plus Bounty; grays out when maxed or unaffordable."

const HELP_HEAD_CONDITIONS := "Trade Post — STATUS"
const HELP_CONDITIONS := "Active patrol MODIFIERS (Conditions) that affect difficulty, economy, or combat rules. Some are chosen at patrol start; others roll randomly when you enter a sector. Tap the Info button (i) to see what each one does."

const HELP_HEAD_ACTIONS := "Part buttons"
const HELP_ACTION_INFO := "INFO (i) — opens the part's full stats and its Mark track (tap a Mark to preview that level)."
const HELP_ACTION_SLOT := "SLOT — install a Hold part into a matching empty slot."
const HELP_ACTION_SWAP := "SWAP — install a Hold part in place of the equipped one; the old part drops back to your Hold."
const HELP_ACTION_PULL := "PULL — unequip an installed part back to your Hold."
const HELP_ACTION_LOCK := "LOCK — protect a Hold part so Scrap and Sell modes skip it. Tap again to unlock."

const HELP_HEAD_ARMAMENTS := "Ship Status — ARMAMENTS"
const HELP_ARMAMENTS := "BLASTER — your permanent, infinite-ammo cannon. You can SWAP it for another blaster (the old one drops to your Hold), but you can never leave without one.\nPRIMARY — an optional metered cannon; toggle to it with G in combat.\nSECONDARY — a wing hardpoint weapon (fires with C).\nSUPER — the Super Pulse Bomb (X)."

const HELP_HEAD_SYSTEMS := "Ship Status — SYSTEMS"
const HELP_SYSTEMS := "Your passive MODULES (up to six) and your SHIFT MODE (activated with Shift). Both are swappable parts — buy, sell, scrap, or upgrade them like anything else."

const HELP_HEAD_HOLD := "Ship Status — HOLD"
const HELP_HOLD := "Parts you're carrying but haven't installed. Use SLOT / SWAP to equip one; LOCK a part to protect it from Scrap and Sell modes."

const HELP_HEAD_BOTTOM := "Bottom bar"
const HELP_BOTTOM := "DEPART — leave for your next destination (this ends buyback). OPTIONS — settings. CODEX — the reference library (ships, enemies, your kit). ? — this guide."

const HELP_CLOSE := "Close"

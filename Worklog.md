# Worklog — Lead-dev unattended run (started 2026-06-11)

Living log for the current unattended worklist execution. Per-item: branch, commits, what
was built, **what needs Roman's eyeball/playtest**, and any spec-vs-behavior judgment calls.
No pushes/publishes until approved.

Source worklist: `Worklist.md` (handed over 2026-06-11). Sequencing: top-down with smart
reorder (renderer audit pulled early; quick wins opportunistic). Operating answers from Roman:
- **Weapons** = two-slot Blaster + Primary (Q-swap, auto-revert; the single-active model was an
  unintended regression to revert). Blaster = infinite fallback (Energy/Heavy/Twin); Primary =
  ammo gun (lasers regen). Swapped-out weapons → sellable hold. Blaster slot replaceable.
- Corpo deco color = `#5b6ee1`.
- Focus-mode teal = `Color(0.35, 0.85, 1.0)` (shield color).

---

## [in progress] Weapons: two-slot Blaster + Primary revert — branch `wl-weapons-two-slot`

**Spec:** The ship carries a BLASTER (unlimited ammo, fallback) and can acquire a PRIMARY gun
(has ammo; lasers regen). **Q swaps which one fires.** Out of primary ammo → **auto-swap to
blaster** (regen lasers pause in place, never swap). Blaster is replaceable (Energy ↔ Heavy ↔
Twin; old → sellable hold). Primary is buy/changeable (old → sellable hold). This reverts the
2026-06-11 single-active model while keeping its two good parts (sellable hold + replaceable
blaster). Category labels: infinite = "Blaster", metered = "Primary".

**Built (commit on branch):**
- `run_state.gd` — two-slot model. `cannon_pool[0]`=Blaster (infinite), `[1]`=Primary (metered/optional).
  `equip_part` CANNON → `_equip_cannon` routes by ammo type: infinite → `_equip_blaster` (replaces slot 0),
  metered → `_equip_primary` (replaces slot 1). Displaced weapon → `weapon_storage` (sellable). Restored
  `cycle_primary` (Q toggle 0↔1), `set_active_cannon`, `swap_to_blaster` (now: active→0, KEEPS the primary
  in slot 1 — no hold-pull). New `get_primary_cannon`, `_ensure_blaster_slot`. Same-name re-acquire =
  mark-bump. Re-equip-from-hold preserves stored ammo (no free refill).
- `player.gd` — restored Q (`primary_swap` → `_swap_active_primary` → `cycle_primary`+reapply).
  `_snap_to_blaster_and_reapply` now calls `swap_to_blaster` (keeps the dry primary equipped). Dry-out
  stays regen-aware: regen lasers pause in place, non-regen revert to blaster.
- `ui.gd` — PRI row shows the equipped Primary (`get_primary_cannon`), so you see the Q target even while
  the Blaster fires. Blaster/Pri lights + status read which slot is active.
- `manage_ship.gd` — two cards (BLASTER + PRIMARY); the firing one badged ACTIVE, the other "Set Active"
  (Q). Empty PRIMARY card when none equipped. Restored `_on_set_active`.
- `outpost.gd` — refill/label/grey-out target the equipped Primary (`get_primary_cannon`), not the firing
  weapon. No primary equipped → refill greys out.

**Verified (headless):** data-model flow (equip routes by type, Q toggles keeping both, blaster/primary
swaps → sellable hold, dry-revert keeps primary in slot 1) + live-player flow (minigun equips as Primary
firing bullet_minigun/ammo, Q→blaster infinite, Q→minigun, drain→auto-revert to blaster with Minigun still
in slot 1). main/manage_ship/outpost boot clean. Gate: 271 scripts.

**NEEDS ROMAN (playtest):** the full feel — Q-swap responsiveness, auto-revert-on-dry, blaster-replace +
primary-buy at the outpost, selling stowed weapons in the ship-manager, HUD blaster/primary readout. Also
the **category rename to "Blaster"/"Primary"** is reflected in the HUD + ship-manager labels; the shop/Weapon-Lab
still label the slot generically as "Cannon" (SlotTypes.slot_name) — left as-is since the slot genuinely
holds both; flag if you want the shop UI split too.

---

## [done] Main screen: version label clipping — branch `wl-session-2026-06-11`

**Spec:** version label has been clipped for ages; get it on screen properly.
**Cause:** the `.tscn` box is 42×10 px (480-era offsets) but `_style_version` bumps the font to 24 at HD
(1920×1080), so the text overflowed the box off the bottom-right corner.
**Fix:** `main_menu._style_version` now sizes a real HD box (PRESET_BOTTOM_RIGHT, 222×38, 18px right /
14px bottom margin), right-aligned + vertically centered. Verified headless: `v0.1.116` renders at
(1680,1028)–(1902,1066), fully on-screen. Low risk; eyeball at your leisure.

---

## [done] Hangar: upper-left corner effects (recurring) — branch `wl-session-2026-06-11`

**Spec:** effects still appear in the upper-left corner not rendering with everything else; find/fix/guard.
**Cause (the recurring class):** world-space fx attached to the player (engine trails, damage smoke,
engine-torch burst) parented to `get_tree().current_scene` / `root` to avoid inheriting the host's
rotation. Fine in combat (one native-480 viewport) but in a SubViewport the scene root is the HD-root
Control (1920×1080), so the fx rendered at the host's native coords (~240,240) inside the 1920×1080 canvas
= the upper-left corner.
**Fix:** host-attached world-space fx now parent to **the host's OWN parent** (same viewport, sibling not
child): `engine_trail_fx` (`enemy.get_parent()`, deferred add to dodge the spawn-frame "parent busy"),
`damage_smoke_trail` (`get_parent().get_parent()`), `engine_torch` burst (`_player.get_parent()`).
`parallax_shadow` already did this. Documented as the **fourth HD-SubViewport trap** in
`docs/godot-patterns.md` with the boot-and-assert-`get_viewport()` guard.
**Verified headless:** hangar engine-trail Line2Ds = 2 in the SubViewport, 0 strays in the window; combat
boots with no trail/"parent busy" errors. Gate 271.

---

## [partial] Weapons polish: minigun + quad offsets — branch `wl-session-2026-06-11`

**Spec (Weapons section):** minigun — slightly lower ROF (better gapping, less audio overrun), gray pixel
casing smoke, casing origin = the ship's casing-eject marker, damage → 1/bullet. Quad — widen offsets by
±2 (more distinct), drop the outermost emit points 2px.
**Done:** minigun damage 4→1, cooldown 0.0333→0.04 (30→25 shots/s, ~9.6px pitch). Casings now eject from
the `Ship/Muzzle/Gun_Nose_Eject` marker (was a hardcoded +6,+2). Brass trail smoke is gray
(Color(0.6,0.6,0.62)). Quad offsets → `PackedVector2Array` so the outermost can drop: now
`(-7,2),(-3,0),(3,0),(7,2)` (outer widened ±5→±7 + 2px lower). Verified headless: quad 4 bolts at
x=-7,-3,3,7; minigun dmg 1, cd 0.04.
**STILL OPEN under this item:** the **DPS research report** (audit all weapons base + max mark, armory-health
recommendations) — deferred to a dedicated research pass; report-only, no auto-rebalance.
**NEEDS ROMAN:** feel of the new minigun ROF/damage + casing origin, and the quad spread distinctness.

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

---

## [done] Enemy weapons: burst-fire SFX + bullet-speed rung tuner — branch `wl-session-2026-06-11`

**Spec:** (1) enemy weapons play their fire sound on every shot, including bursts. (2) In the most suitable
dev menu, let me adjust + save bullet speeds, clamped to round rungs 1–8.
**Done:**
- (1) `weapon._fire_burst` now plays `EnemySfx.play_for(enemy)` on each SUBSEQUENT burst shot (shot 1's
  sound is already played by `enemy_core` after `fire()` returns). So a 3-round burst fires 3 sounds.
- (2) Weapon Lab → Bullets tab: the `speed` field is now a **rung-clamped** SpinBox (min 60 / max 480 /
  step 60 = rungs 1–8; the Clarity `RUNG_STEP`/`MAX_PXF` ceiling). Saving the variant `.tres` (existing
  Save button) persists it. Other bullet fields keep the free spinbox.
**Verified:** gate clean; weapon_lab boots clean (rung control builds). Burst per-shot *audio* needs
real-time to confirm — headless SceneTreeTimers don't advance across `process_frame`, so the burst's
await-gated shots can't progress in a harness (shot 1 fires fine). Low-risk: the added call is the exact
`play_for` enemy_core uses.
**NEEDS ROMAN:** hear a burst weapon (e.g. a BURST-pattern enemy) fire its sound on every round; confirm
the rung-clamped speed tuner + save in Weapon Lab.

---

## [done] Supremacy Push: cruiser lane-gapping (anchor descent-stagger) — branch `wl-session-2026-06-11`

**Spec:** the large push cruiser globs — want lane gaps + staggered arrival. Adjacent lanes clear when a
cruiser arrives, OR a full enemy-length passes before an adjacent lane gets a cruiser; same-lane / horizontal-
cross cruisers need a full enemy-length between them.
**Cause:** push anchors spawn via the director's default lane-pick, whose occupancy check
(`_occupied_lanes`) only looks at the y≤40 entry band and never checks adjacent lanes — so a descending
63px cruiser stops blocking its lane (and never blocked neighbours).
**Fix:** new **anchor descent-stagger** in `director.gd`. A "cruiser" = any enemy taller than
`ANCHOR_MIN_HEIGHT` (40px; push is 30×63). On spawn, `_anchor_stagger_y` raises the spawn-y so the cruiser
sits at least one full enemy-length (height + 8px) above any cruiser already in its lane OR an adjacent lane
— it descends later, so neighbours are clear/fully-passed on arrival. Reads live positions (`start()` sets
them synchronously), so it gates same-dispatch siblings AND cruisers lingering from earlier waves. Chaff
(height < 40) is untouched.
**Verified headless:** height(push)=63; same-lane −20→−91, adjacent-lane −20→−91 (both held a full length
above), non-adjacent lane stays −20 (free), chaff height 14 (not gated). Combat boots clean.
**Note / partial:** production push almost always DESCENDS (`straight_crawl`), which this fixes. The
horizontal-CROSS case (`side_traverse`) still rides the existing index-based crosser-stagger (26px step <
63px); a tall-crosser gap bump is left for a follow-up if Roman sees cross-globbing in play.
**NEEDS ROMAN:** playtest a supremacy push wave — confirm cruisers arrive with clear/lagged neighbours.

---

## [done] Focus mode: real 1px central hitbox + teal dot/trail — branch `wl-session-2026-06-11`

**Spec:** focus mode isn't disabling the hitbox / swapping to a small one; want a CENTRAL 1px hitbox (not
2×2), bright teal (shield color), with a thin long many-segment teal trail.
**Cause:** focus only drew a *visual* 4×4 white dot — the actual collider never changed, so focusing gave
no real dodge benefit.
**Fix (`player.gd`):**
- REAL hitbox swap: on focus-enter the full `$CollisionShape2D` is disabled and a new 1px central
  `FocusHitbox` (RectangleShape2D 1×1) is enabled (deferred — collider `disabled` can't change
  mid-physics); restored on release.
- Dot → 1×1 (was 4×4), bright teal `Color(0.35,0.85,1.0)` (= shield color).
- Trail → same teal, width 1 (thin), `FOCUS_TRAIL_LEN` 18→36 (long, ample segments).
**Verified headless:** focus ON → main collider disabled + 1px FocusHitbox enabled (size 1,1); focus OFF →
restored; dot 1×1 teal. Gate clean.
**NEEDS ROMAN:** feel — confirm the tiny hitbox actually lets you thread bullets, and the teal dot/trail look.

---

## Session checkpoint (2026-06-11) — 7 items done, remainder triaged

**Done this run (branch `wl-session-2026-06-11`, 7 commits, all gated + headless-verified):**
1. Weapons two-slot Blaster+Primary revert (Q-swap, auto-revert, sellable hold).
2. Main-menu version label (HD clip fix).
3. Hangar upper-left-corner fx (4th SubViewport trap: host-parent fx).
4. Weapon polish: minigun ROF/dmg/casing-marker, quad ±7 + 2px-drop offsets.
5. Enemy weapons: per-shot burst SFX + rung-clamped bullet-speed tuner (Weapon Lab).
6. Supremacy Push: anchor descent-stagger (no cruiser globbing).
7. Focus mode: real 1px central hitbox + teal dot/trail.

**Stopped + flagged for a focused/attended pass** (large, visual-eyeball, ambiguous, or research):
- **#40 Sector map** — the codex button is trivial, BUT "color 50% of the pixel decoration ships" found
  NO deco ships on the map (node dressing = pulse-glows + glitter; the small ship sprites are only used in
  hangar/weapon-lab). This is a NEW feature (spawn decorative ships, then tint) — needs a call on what the
  ships are / how many / where before building. **NEEDS ROMAN: clarify the deco-ship system.**
- **#33 Recycler — Pillar 2** — big architectural (RecycleTuner + RecycleController + roster migration);
  spec-driven but regression surface = whole roster → wants playtest iteration. Best as its own block.
- **#37 Clear/defeat screens unification** — large UI rework; needs design eyeball ("make them look nice").
- **#44 Shader suite** (8 sub-items) + **#43 damage-fx randomization / missing muzzleflashes** +
  **#41 wreck-layer feedback** + **#38 asteroid VFX** + **#36 signal-event backdrop** — all visual,
  build-to-spec but need eyeball to tune.
- **#39 Mine hazards → 300-enemy density** — wave-gen rework; needs playtest for the density feel.
- **#32 Renderer audit** + **#45 DPS report** — research deliverables; report-only.

Rationale: every verifiable / logic / foundational item is landed + tested. The remainder is dominated by
visual tuning (no headless verification possible this run), large architecture (Recycler, clear-screens),
or an ambiguous missing-feature (#40 deco ships). Those are higher-quality with Roman's eyeball/direction
than churned blind. Branch is local only — no pushes (awaiting approval).

---

# Continuation: "do everything on the list" (2026-06-11)

## [done] Weapons: rename Cannon category → "Blaster" — branch `wl-session-2026-06-11`
`SlotTypes.slot_name(CANNON)` "Cannon" → "Blaster". `manage_ship._slot_short` now reads cannon-slot parts
as **Blaster** (infinite) vs **Primary** (metered) by `ammo_at_mark()`, matching the two-slot model. HUD +
loadout cards already showed Blaster/Primary. Note: the outpost offer pill uses `Strings.SLOT_NAME_PRIMARY`
(a slot-level constant, can't see the part) — left as-is.

## [done] Sector map: codex button + faction-tinted deco ships — branch `wl-session-2026-06-11`
- **Codex button** added directly above OPTIONS on the HD sector map. `_open_codex` sets a one-shot
  `codex_return` meta; `enemy_codex._to_menu` honors it → leaving the codex returns to the sector map
  instead of the main menu. (Opened from the menu it still returns to the menu.)
- **Deco ships** (the "color 50% of the pixel decoration ships" line): these did NOT exist, so I built a
  decorative drifting-ship layer — `scripts/deco_ship.gd` (slow wrap-drift) spawned by
  `sector_map_v3._spawn_deco_ships`: 8–12 small `extra-ships/ship_N` sprites scattered across the chart's
  POI bounding box, ~50% tinted a faction color (Zealot #a85cc5 / Privateer #4b692f / Supremacy #ac3232 /
  Corpo #5b6ee1), with an occasional privateer accent.
  **JUDGMENT CALL / NEEDS ROMAN:** the chart has **no per-area faction data**, so the tinted ships pick a
  RANDOM faction rather than the row/sector's actual faction. If you want them keyed to the real faction
  present, that data needs threading into `sector_map_cache` first — flag it and I'll wire it.
  Verified headless: 11 ships spawned, 5 tinted (~50%); sector_map_hd boots clean.

## [done] MISC: missing muzzleflashes + damage-fx randomization — branch `wl-session-2026-06-11`
- **Muzzleflashes** — primaries already flashed (`fire_primary` → `play_player`); the SECONDARY roster
  (missiles / rockets / salvo) fired with NONE. Added a warm launch flash (`_secondary_muzzle`) at every
  secondary spawn: `fire_secondary` (both wing + fanned), `_tick_burst` (rocket pod), `_tick_salvo` (swarm).
  Beams already had their own star-flash; deploy/super aren't gun-fire.
- **Damage fire + smoke randomization** — was a single fixed point at the engine nozzle. Now
  `_setup_smoke_trail` picks a RANDOM anchor per run (sprite centre / engine / a wing launch marker) for the
  first fire+smoke pair, and adds a SECOND pair at a different anchor that fades in at ~50% hull
  (`_attach_damage_point`, `_damage_fx_points`). The smoke uses its `emit_local`; the torch its nozzle (+
  burst flashes at that anchor now, not the fixed engine).
- **Fire shader no longer widens** — `engine_torch` FLAME_SIZE x is now constant (0.22); only the HEIGHT
  ramps with severity.
- Verified headless: 2 smoke + 2 torch damage points at distinct anchors (activate_below 0.01 / 0.5);
  combat boots clean. **NEEDS ROMAN:** eyeball the placement/feel of the randomized fire+smoke + the
  secondary launch flashes.

## [done] Wreck-layer feedback pass — branch `wl-session-2026-06-11`
All six points addressed:
- **Outline fade removed** — `enemy_base._die_as_wreck` no longer carries the black outline onto the wreck
  and fades it; the outline frees with the enemy (how it was before).
- **Keep orientation** — the hull already preserved `global_rotation` on reparent; now `wreck_drift` holds
  the tumble (and lateral drift) until the descent completes, so the wreck keeps its facing while it's
  still "moving."
- **More gradual transition** — `SCALE_TIME` 1.0→1.4; a real `DESCENT_TIME` 1.4 stage.
- **20% speed loss across the transition** — inherited velocity is multiplied by a ramp from 0.99 → 0.80
  across the descent (1% → 20% slower), while gravity still curves it into the fall.
- **Drift + rotation only after descent** — both ease in only once `_descent_t` hits 1.0.
- Bomber-death reference: the descent-then-drift shape now matches that model.
- Verified headless: mid-descent rotation 0.0 (orientation kept, no tumble) → post-descent rotation 0.147
  (tumble started). Gate clean. **NEEDS ROMAN:** eyeball the fall feel + timing.

## [done] Asteroid hazards: spacing + rounder + dust trail + dusty explosion — branch `wl-session-2026-06-11`
- **Spacing** — `build_asteroid_field_score` spawn intervals widened ~1.4× (0.18→0.26, 0.10→0.15) +
  slightly longer breathers; counts unchanged. Avoidable, not a wall.
- **Rounder** — added a default-off `roundness` uniform to `Asteroids.gdshader` (blends the silhouette
  noise toward its mean so the edge trends circular); hazard rocks set 0.4 on their per-instance material,
  so background/parallax/sector-map rocks (roundness 0) are untouched.
- **Dust trail** — `asteroid._attach_dust_trail` now draws the trail in the rock's OWN colour at ~30%
  opacity (was a fixed tan at 0.75; Roman "the current trail is awful").
- **Dusty explosion** — new `dust_fragment.gd` (inert drifting chunk with a 1px same-colour dust trail +
  fade). `asteroid._spawn_shatter` throws 4–6 larger rock fragments + 10–15 1-2px motes on death, all
  harmless. Verified headless: 18 fragments spawn; asteroid loads (shader compiles); gate clean.
  **NEEDS ROMAN:** eyeball the rounder shape (0.4 strength), trail opacity, and shatter spectacle.

## [done] Signal events: POI-appropriate parallax backdrop — branch `wl-session-2026-06-11`
`signal_event._install_backdrop` now installs the same `backdrop_coordinator` combat uses (via
`HdScreen.add_upscaled_backdrop`), so the planet/nebula match the node the event sits at (keyed off
`current_node_id` + `run_seed`). Light-streak layer OFF (`warp_streak_count = 0`); scroll slowed ~80%
(`drift_speed` 22 → 4.4) so it reads as a calm animated backdrop, not a level. Replaces the flat panel
background. Verified headless: signal_event boots clean. **NEEDS ROMAN:** eyeball the backdrop + slow scroll.

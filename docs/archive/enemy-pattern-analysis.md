**⚠️ ARCHIVED 2026-06-15 — historical snapshot, not current design.** Superseded by: docs/m6_modular_enemies_design_2026-06-05.md + CLAUDE.md "Modular enemy system".
Kept for design history; do not cite as the live spec.

# Enemy Pattern System Analysis

**Date:** 2026-05-28  
**Scope:** Movement/shoot pattern architecture, consistency gaps, and tooling recommendations.

---

## Section 1: Current Architecture

**The slot system.** `scripts/enemy_core.gd` is the standard pattern-driven enemy. It holds two resource slots: `movement: Resource` (a `MovementPattern` subclass) and `shoot_pattern: Resource` (a `ShootPattern` subclass). Each frame, `_process()` calls `movement.compute_step(self, delta)` and applies the result. The director wires patterns at spawn time via `wave.movement_override` and `wave.shoot_pattern_override`. `boss_base.gd` exposes the same two slots, so bosses are also pattern-capable.

Seventeen movement patterns live under `scripts/enemies/patterns/`. Four shoot patterns live under `scripts/enemies/shoot_patterns/`. `EnemyRoster.make_movement()` and `make_shoot()` (`scripts/levels/enemy_roster.gd:391–524`) construct and parameterize all patterns used in actual play. This is the primary source of truth for tuning values — pure GDScript, not `.tres` files. Only three movement `.tres` and four shoot `.tres` exist under `resources/patterns/`; these are the minority the Wave Editor can see.

**Who uses the slot system vs. who bypasses it.** Enemies that extend `enemy_core.gd` and use slots: `interceptor.gd`, `minelayer.gd`, `hunter_drone.gd`, and all generic enemies the Roster describes (dart, weaver, hover, frigate, skirmisher, crystal, cutter, etc.).

Enemies that extend `EnemyBase` directly with inline movement:

| Script | Bypassed behavior |
|---|---|
| `enemy_burner.gd` | Straight-down descent at constant speed |
| `enemy_sapper.gd` | Manually preloads and ticks `omni_thrust.gd` inline + Y-clamp |
| `enemy_cruiser.gd` | Settle-to-Y + sine drift (matches `slow_advance`/`bulwark_drift`) |
| `enemy_drone_carrier.gd` | Identical settle-to-Y + sine drift |
| `enemy_gunship.gd` | ENTERING → ACTIVE → EXITING state machine |
| `enemy_beam_shooter.gd` | Lateral drift + beam IDLE/WINDUP/FIRING/COOLDOWN |
| `enemy_firecore_cruiser.gd` | Traverse + custom death descent |
| `enemy_bomber.gd` | Settle + sway + dual-turret arcs + death slump |
| `bulwark.gd` | Inertial push-to-center + shield-charge `take_hit` override |

**Consistency problems from bespoke enemies.**

1. **Shield-charge logic duplicated.** `bulwark.gd:99–119` and `enemy_bomber.gd:124–142` each carry ~80 lines of near-identical `take_hit` override, `_build_shield_ring`, `_update_shield_visual`, and `hull`/`max_hull` shims. `EnemyBase` already has `max_shield` / `shield` and `_setup_shield_ring()` for single-charge shields; the copies drift from the base without differing in intent.

2. **Player-lookup triplicated.** `EnemyBase.find_player()` is canonical. Each of several movement patterns defines its own `_find_player(enemy)` (`beeline_player.gd`, `inertial_thrust.gd`, `jet.gd`, etc.) instead of calling `enemy.find_player()`. `ShootPattern._aim_at_player()` is a third copy. All three scan the `"player"` group.

3. **Settle-to-Y + sine drift** is coded independently in `slow_advance.gd`, `bulwark_drift.gd`, `enemy_cruiser.gd`, and `enemy_drone_carrier.gd`. Functionally identical; the bespoke variants simply didn't reuse the existing pattern.

---

## Section 2: Centralization Assessment

**What "centralized" means here.** Every enemy declares locomotion via the movement resource slot, even if it also has bespoke behavior on top. The slot handles movement; the script handles abilities (beam, drone release, turret arcs). `interceptor.gd` and `minelayer.gd` prove this works: both extend `enemy_core.gd`, use slot-driven movement, and add custom emission in their own `_process`.

**Benefits.** Slot-driven enemies get sector speed scaling (`enemy_core._apply_sector_speed_scale`), the parallax fly-back cycle, the shoot guard (`_on_playfield` / `_cycling` gate), and the `fire_on_phase` mechanism automatically. Bespoke movers must reinvent or skip these. The Wave Editor and the Roster's conflict-tag system also only operate on slot-driven enemies.

**What to fold in vs. leave bespoke.**

*Accidentally bespoke — slot-driven movement would work:*
- `enemy_burner.gd` — Replace inline descent with the `StraightDown` pattern slot. No other changes.
- `enemy_sapper.gd:36` — The manual `preload(...omni_thrust).new()` + `compute_step` call is already the pattern slot, just not wired through `enemy_core`. Extend `enemy_core`, assign `movement` in `_ready`, keep the Y-clamp as a `_process` override — exactly the `minelayer.gd` precedent.
- `enemy_drone_carrier.gd` — Settle-to-Y is `slow_advance` with tuned parameters. Drone release stays in the script.
- `enemy_cruiser.gd` — Similar to drone carrier; turret-spawn interaction adds a little risk, best done separately.

*Genuinely bespoke — leave alone:*
- `enemy_beam_shooter.gd` — The beam IDLE/WINDUP/FIRING/COOLDOWN state machine is its identity.
- `enemy_firecore_cruiser.gd` — Traverse + death descent is not expressible as a simple `compute_step`.
- `enemy_bomber.gd` — Dual turret arcs and death slump are signature behaviors. The settle+sway locomotion is extractable but the surgery isn't worth the gain given overall complexity.
- `enemy_gunship.gd` — The ENTERING/ACTIVE/EXITING state machine and `on_spawned_in_wave` role-context logic is bespoke by necessity.
- `bulwark.gd` — Inertial push-to-center is unique; the shield-charge `take_hit` is the real duplication problem (see R5).

**Verdict.** Partial centralization is worthwhile for burner, sapper, and drone carrier. The slot system is sound — the gap is that several enemies opted out of a pattern that already fit them. A full mandate ("everything must use the slot") is over-reach and wouldn't improve the genuinely complex enemies.

---

## Section 3: Tooling and Signposting Gaps

**What the existing tools cover.** The Movement Lab previews the five AI-steering patterns (`omni_thrust`, `inertial_thrust`, `jet`, `jet_charger`, `jet_vector`) against a movable player cursor. The Movement Pattern Editor previews individual `.tres` patterns. The Shoot Pattern Editor previews shoot patterns. The Wave Editor lets designers author and playtest `WaveDef` `.tres` files.

**Gap 1: Two sources of truth for patterns that don't agree.**  
`EnemyRoster.make_movement` hard-codes 13 movement keys with inline parameter tuning. The Wave Editor's movement picker reads `resources/patterns/movement/` — currently only 3 files. A designer using the Wave Editor cannot pick `advance_retreat` at all because no `.tres` exists for it, even though it is a working production pattern. Fix: either generate `.tres` stubs from `make_movement` for all roster entries, or make the Wave Editor enumerate roster keys instead of scanning a directory.

**Gap 2: No named Y-band constants.**  
Movement patterns reference Y positions as magic literals: `loiter.gd:33` clamps `hover_y` to 135, `advance_retreat.gd:10` defaults `advance_y` to 192, `slow_advance.gd:7` defaults `hold_y` to 88, `beeline_player.gd:12` sets `commit_y` to 48. `scripts/playfield.gd` defines `X_MIN`, `X_MAX`, and `CENTER` but has no named Y-bands. A pattern author placing a new loiter zone has no canonical reference. Adding constants like `Playfield.Y_TOP_HOLD`, `Y_MID_HOLD`, `Y_ADVANCE_LINE`, `Y_FIRE_LINE` would document intent and give a shared vocabulary across patterns, the Wave Editor, and dev tools.

**Gap 3: No playfield band overlay in Movement Lab.**  
The Movement Lab uses `grid_overlay.gd` but does not draw the Y-bands. A developer setting `advance_y` can't see "mid-hold" at a glance. Once Y-band constants exist (Gap 2), adding horizontal labeled lines costs ~10 lines in `grid_overlay.gd`. Dev-tool-only, no runtime chrome.

**Gap 4: Movement Lab covers only 5 of 17 patterns.**  
The remaining 12 (straight_down, s_curve, loiter, advance_retreat, side_cut, side_traverse, side_pingpong, top_dive, beeline_player, bulwark_drift, slow_advance, jet_vector) are only testable via the single-pattern Movement Pattern Editor with no player-interaction context. Expanding the Movement Lab to include these as named tabs — or a "multi-pattern browse" mode — would let Roman quickly compare behaviors in context.

---

## Section 4: Recommendations (Prioritized)

**R1 — Fold burner, sapper, and drone carrier into `enemy_core` (quick win, low risk)**  
Convert `enemy_burner.gd`, `enemy_sapper.gd`, and `enemy_drone_carrier.gd` to extend `enemy_core.gd`. Assign their movement via the slot in `_ready`; keep bespoke `_process` behavior (fire-mine drops, drain beam, drone release) as overrides on top. Uses the `interceptor.gd` / `minelayer.gd` precedent exactly. These enemies gain sector speed scaling and the shoot guard for free. `enemy_cruiser.gd` is a similar candidate but turret-spawn interaction is riskier — file separately.

**R2 — Add named Y-band constants to `scripts/playfield.gd` (quick win, no breaking change)**  
Add `Y_TOP_HOLD`, `Y_MID_HOLD`, `Y_ADVANCE_LINE`, `Y_FIRE_LINE` (names open to bikeshedding). Update pattern defaults to reference them. Documents designer intent and gives a shared vocabulary across patterns, editors, and Movement Lab.

**R3 — Add horizontal band guides to Movement Lab (quick win, dev-only)**  
After R2, draw Y-band lines in Movement Lab's field drawing code, labeled with constant names. Reuse `grid_overlay.gd`'s draw infrastructure (~10 lines). The lab already shows playfield bounds; bands add zero runtime cost.

**R4 — Reconcile the two pattern sources of truth (medium effort)**  
Either (a) generate `.tres` stubs from `EnemyRoster.make_movement`'s 13 keys so the Wave Editor can pick all production patterns, or (b) change the Wave Editor's movement picker to enumerate roster keys rather than scan `resources/patterns/movement/`. Option (b) is fewer files but tighter coupling to the roster. Either way, the Wave Editor becomes a complete authoring tool rather than covering only ~20% of patterns.

**R5 — Extract shared shield-charge into EnemyBase or a component node (larger, lower urgency)**  
`bulwark.gd` and `enemy_bomber.gd` each carry ~80 lines of near-identical shield-charge logic that duplicates `EnemyBase`'s existing `max_shield` / `shield` infrastructure. A charge-pool extension to `EnemyBase`, or a reusable `ShieldChargeComponent` child node on the `EnemyTurret` model, would collapse both copies. The bomber's `hull`/`max_hull` shims suggest it predates `EnemyBase`'s damage-overlay support — worth re-checking whether they're still needed post-merge.

---

## What Is Working Well

- The `movement_pattern.gd` / `compute_step` contract is clean. The `on_start` / `compute_step` split (reset vs. step) is the right shape.
- `EnemyRoster.make_movement` and `make_shoot` as factory functions: tuning values in one file, not scattered across dozens of `.tres` files.
- The `phase_entered` signal on `loiter.gd` + `fire_on_phase` in `enemy_core` is an elegant mechanism for shot-on-cue behavior without per-enemy timers.
- `EnemyTurret` as a reusable aiming/firing child node (used by cruiser, gun turret, gunship, bulwark, firecore cruiser) is sound composition. The shield-component gap is the next logical step in the same direction.

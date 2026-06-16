# Code follow-ups — from the 2026-06-15 doc staleness audit

**Status: OPEN** — code-level items surfaced while remediating the docs (`docs/doc_staleness_audit_2026-06-15.md`).
These need a code decision/change, not a doc edit. None is urgent; the game runs fine as-is.
Line references verified 2026-06-15 against the working tree.

---

## 1. `row` → `route` rename: apply it or formally drop it

The archived lane-wave bridge (`docs/archive/combat_lane_wave_bridge_2026-06-03.md` §0) declared a
`row → route` rename "canonical / THIS WINS" (route = map-space, lane/row = combat-space). **It was
never applied** — the code still uses `row` vocabulary:

- `func is_row_pois_complete(row_idx)` — `scripts/autoload/run_state.gd:907`
- call sites — `scripts/screens/sector_map_v3.gd:1167, 2058, 2163`
- (plus other `row_*` POI symbols — `grep` `row` in `run_state.gd` / `sector_map_v3.gd` for the full surface)

**Decision needed:** either
- (a) apply the rename — mechanical: `is_row_pois_complete` → `is_route_pois_complete` and related
  `row_*` POI symbols + all call sites; verify with `tools/parse_check.ps1` + a sector-map headless boot; **or**
- (b) drop it — strike the idea (the source doc is archived anyway). The code's `row` naming is
  internally consistent.

**Recommendation: (b) drop it.** Low value; `row` reads fine in context. Only worth (a) if you
want the map-space/combat-space vocabulary split to be explicit in code.

---

## 2. Boss file/scene names don't match display names (grep trap)

Two bosses ship under filenames that don't match their player-facing names, so a `grep` for the
display name finds nothing:

| Display name | Scene | Script | Registered |
|---|---|---|---|
| **Lash** | `scenes/enemies/bosses/boss_reaver.tscn` | `boss_reaver.gd` | `scripts/levels/wave_generator.gd:85-86` |
| **Aegis** | `scenes/enemies/bosses/boss_sentinel.tscn` | `boss_aegis.gd` | `scripts/levels/wave_generator.gd:90-91` |

(There is no `boss_lash.*` and no `boss_aegis.tscn`.)

**Decision needed:** (a) rename files/scenes to match the display names, or (b) leave as-is and rely
on the alias being documented (it's noted in the archived `boss_proposals_2026-05-24.md` banner and
`docs/README.md`).

⚠️ **If renaming (a):** `.gd`/`.tscn` moves are reference-fragile (uid + literal-path refs):
- Follow the move-safety checklist in `docs/file-structure.md` and run a Godot `--import` afterward
  to rebuild the uid cache (see the `moving-uid-referenced-scripts` learning).
- `wave_generator.gd` hardcodes the scene paths above — update them.
- **Do NOT move `boss_base.gd`** — it's recognized by literal path
  (`resource_path == "res://scripts/enemies/bosses/boss_base.gd"`) in `main.gd` + `base_missile.gd`.

**Recommendation: low priority.** (b) leave + keep documented, unless the naming actively bites.

---

## 3. Manage-Ship modal — ALREADY DONE (note only, no action)

The archived `sector_map_hd_PORT_HANDOFF.md` asks to "remove the old in-map Manage Ship modal from
`sector_map_v3` (~lines 2207–2536)." **That is already done** — there is no `_show_manage_ship_modal`
or modal builder, and `sector_map_v3.gd:2139` confirms "Zero-bounty entry is no longer gated by a modal."

The only residual is `_ms_build_status_bits_text` (`sector_map_v3.gd:2186`), which is **intentionally
kept and shared with the live `manage_ship.gd`** (see comments at 1407-1408 and 2183-2185). It is live
code, not dead. The `_ms_` ("manage-ship-modal") prefix is now a vestigial name — an **optional**
cosmetic rename for clarity, nothing more. No functional action required.

---

## 4. Stale comment in `outpost.gd` (trivial)

`scripts/screens/outpost.gd:62` says the weapon-roll table is `= 9 weights`, but `WEAPON_SLOT_WEIGHTS`
(lines 65-78) actually has **11** entries: CANNON ×4, HARDPOINT_WING ×2, DEVICE_BAY_1 ×1, SHIFT_MODE ×2,
**MODULE ×2** (the two MODULE entries were added after the comment was written). This stale comment is
what led a doc to under-count the MODULE roll weight.

**Action:** one-line comment fix — `9` → `11` and update the breakdown to include MODULE ×2.

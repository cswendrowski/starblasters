# Vestigial Parts Cleanup — plan (2026-06-03)

Removing the early per-slot Part design (wings, tail, per-slot shields) that the
**Mark upgrade system** (`thrusters_mk`, `hull_mk`, `armor_mk`, `self_repair_mk`
bought at the outpost) replaced. Audit confirmed these 7 scripts are orphaned:
not in `part_catalog.gd`'s pool, not in `part_factory.gd`, no `class_name`, not in
any `.tscn`/`.tres`, and no file references them by path.

**Scope (approved):** Bucket 1 (delete orphaned parts) + fix docs.
**Out of scope (deferred):** slot-enum scaffolding (`WING_LEFT/WING_RIGHT/TAIL`)
— removal renumbers the `SlotType` enum, and `loadout_snapshot` is keyed by slot
int and persisted by `run_save.gd`, so it would corrupt saves. Leave for a
deliberate migration. **Vectoring Engine is LIVE** (in the roll pool) — do NOT touch.

## Step 1 — delete orphaned Part scripts (+ their `.uid` sidecars)

```
scripts/parts/reactive_wings.gd        (+ .uid)   "Reactive Wing"   WING
scripts/parts/armored_wings.gd         (+ .uid)   "Armored Wing"    WING
scripts/parts/basic_wings.gd           (+ .uid)   "Standard Wing"   TAIL/WING
scripts/parts/basic_tail.gd            (+ .uid)   "Basic Tail"      TAIL
scripts/parts/basic_shield.gd          (+ .uid)   "Standard Shield" SHIELD
scripts/parts/reinforced_shield.gd     (+ .uid)   —                 SHIELD
scripts/parts/quick_reset_shield.gd    (+ .uid)   —                 SHIELD
```

14 files total (7 `.gd` + 7 `.gd.uid`).

## Step 2 — docs

- `docs/contributing/04-player-parts-economy.md` (slot table ~L86-95): drop the
  `WING_LEFT, WING_RIGHT` and `TAIL` rows (or relabel as
  "reserved / unused — early design"); fix the SHIELD row note since the
  Standard Shield part is being deleted.
- `.claude/agents/game-design.md:14`: drop `WING_LEFT, WING_RIGHT, TAIL` from the
  "10 player slots" line (or note them as reserved). Verify the slot count phrasing.

## Step 3 — verify

- `tools/parse_check.ps1` (catches any dangling preload/reference).
- Headless smoke: `godot --path . --headless --quit-after 2`.

## Notes / do-NOT-touch
- `Vectoring Engine` (`scripts/parts/vectoring_engine.gd`) — live in catalog pool.
- `thrusters_mk` / "Thrusters" — the current Mark system. Keep.
- `exit_thruster_*.ogg` SFX (`main.gd`), "thruster frame loop" comments
  (`base_missile.gd`, `enemy_rocket.gd`) — unrelated, ignore.
- Enum `SlotType` (`scripts/weapons/SlotTypes.gd`), `strings.gd` SLOT_NAME_*,
  `outpost.gd` slot-name mapping — left intact this pass (save-compat hazard).

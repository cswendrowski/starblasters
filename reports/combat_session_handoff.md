# Combat session handoff → TODO Task Lead (2026-06-08)

**Branch:** `m6c-polish-r2` (NEVER pushed yet — first push will carry both sessions' work).
**Ask:** commit any remaining loose ends + **push** the branch. All combat work below is
committed + headless-verified. Standing rule: nothing was pushed (push is the Lead's/Roman's call).

## My commits (combat / weapons / shields / projectiles / patterns)

Polish (earlier): `8fb449d` shader polish · `e57f843` opaque damage flame · `cb3a807` push enemy
face+no-recycle · `96733b8` push auto_rotate + turret aims relative to parent.

Weapons spec alignment (docs/weapons_system_2026-06-05.md):
- `b5e4e32` P0 (spec-name baselines, burst primitives, tracker hitbox)
- `803b432` P1 (twin-muzzle pair_shot, aimed_wild/aimed_lead, turret lead_factor)
- `5507d22` + `4a29e36` P2 (per-bullet scene catalog routing; retire old Mini Pixel art)
- `82a4631` P3a (rockets unified onto BaseMissile) · `297fe25` P3 wrap (3b deferred, option C)

- `1ba0692` Shield unification (one ShieldComponent, CHARGE/POOL; bulwark/mine/sapper migrated)
- `d973c31` Smart bomb (ignore all shields, clear missiles/rockets, full-wave iframes) + faction
  bonuses scoped to home-faction units only
- `423565d` Projectiles (scene-authoritative hitboxes, cannon speed 240, gunship 3-shot MG)
- `4e930a5` Patterns (top_dive horizontal-then-dive, new dive_return, advance_retreat collapse,
  s_curve/drifter culls)
- `4fe582a` Cannon random_frame (glow matches the shown frame)

## Loose items the push must include

**LOAD-BEARING — commit these (combat, mine):** the projectile-scene hitbox edits Roman made —
`scenes/projectiles/enemy_bullet.tscn`, `enemy_bullet_diamond.tscn`, `enemy_bullet_laser.tscn`,
`enemy_bullet_tracer.tscn`, `enemy_bullet_wave.tscn`. Since `423565d` made `_apply_variant` stop
overriding the collision shape, **these scene shapes ARE the live hitboxes** — if they're not in
the push, shipped hitboxes are wrong. (Committed in this handoff commit.)
Plus my `.uid` sidecars: `pair_shot.gd.uid`, `bullet_catalog.gd.uid`, `test_cannon_bullet.gd.uid`,
`test_faction_gate.gd.uid`.

**NOT mine — coordinate with the other session before sweeping:** `SpaceBG/Colorscheme.tres`,
`tools/capture_smart_bomb.{gd,gd.uid,ps1}`, `scripts/{codex_strings,credits,run_history}.gd.uid`.

## Verification

parse_check clean; `compile_check` clean; reorg 38/38; combat boots clean. Targeted tests all
PASS: `test_shield_component`, `test_bomb_shields`, `test_faction_gate`, `test_cannon_bullet`,
`test_movement_keys`.

## Open / flagged (not blockers for the push)

- **`dive_return`** pattern is built + verified but NOT assigned to any enemy yet — pending the
  pattern-eligibility system below.
- **Weapons 3b** (make weapon.gd the sole production firing class + single-source rate) is
  deliberately deferred (option C; see the spec status block).
- **Pattern-eligibility / lane-visualizer tab** — designed-not-built. Next combat-session task:
  a central enemy×pattern eligibility matrix edited in a tool, exported to committed data (NOT
  runtime user://), conductor picks movement from it. Two design questions open with Roman
  (manual grid vs tag-derived; default-movement as a separate identity field).

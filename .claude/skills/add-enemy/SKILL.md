---
name: add-enemy
description: Scaffold a new Starblaster enemy end to end — stats, movement/shoot pattern Resources (or a justified bespoke script), the .tscn, the roster entry with spawn gating, sprite import, and verification. Use when adding a new enemy type to the game. Follows the docs/contributing/03 walkthrough and chains the enemy-design / data-author / asset-importer agents.
---

# /add-enemy — guided enemy scaffold

Full reference: `docs/contributing/03-combat-waves-enemies.md`. This skill is the
ordered procedure; lean on the listed agents for the actual work.

## Procedure

### 1. Gather intent
Confirm with the requester (or infer from the request): role (chaff / elite /
mini-boss), HP, bounty, speed, **movement** behavior, **shoot** behavior, size,
and whether real art exists or it's a placeholder. For role/stat/pacing
judgment, consult the **enemy-design** agent (read-only — it knows the roster
and threat curve).

### 2. Prefer enemy_core + Resource slots over bespoke code
This is the project convention. Before writing any movement code, check
`scripts/enemies/patterns/` (movement) and `scripts/enemies/shoot_patterns/`
(shooting) for an existing Resource that fits. Compose the enemy by extending
`scripts/enemy_core.gd` (top-level `scripts/`, NOT `scripts/enemies/`) and
filling its `movement` + `shoot_pattern` slots. **Only** write a bespoke script
that extends `scripts/enemies/enemy_base.gd` for behavior a pattern genuinely
can't express (multi-phase state machines, continuous-effect weapons).

### 3. Sprite
- If real art was dropped (e.g. Roman shared new art): use the **asset-importer**
  agent to place it under `graphics/enemies/`, generate the `.import` sidecar +
  `.uid`, and confirm the `hframes` (width/height ratio).
- If it's **placeholder** art: FLAG IT. Do not wire placeholder-art enemies into
  production waves and ship — that hits every tester. Hold, or keep it out of
  live rotation (weight 0 / dev-only), and ask the maintainer. (See memory
  `feedback_placeholder_in_prod_waves`.)

### 4. Build the .tscn (use data-author or code-editor for the wiring)
- Root: `Area2D` in group `["enemies"]`, script attached.
- A child **named exactly `Sprite2D`** — `enemy_base.gd` hard-references
  `$Sprite2D` for auto-rotate / damage-overlay / hit-flash / burn. Don't rename it.
- `CollisionShape2D` sized to the **full sprite** (hitbox rule: enemies = full
  sprite size; tune difficulty via HP/damage/spawn-rate, never hitbox size).
- Optional `Muzzle*` `Marker2D` children as bullet origins / flash anchors (two
  muzzles = alternating fire).
- Set `max_health` + `bounty_value`.
- For a **bespoke** script: set stats BEFORE `super._ready()` (the base reads
  them in `_ready()`; the `<=0 ? default` pattern caused a 1-HP bug).

### 5. Register in the roster
Add an ENTRY in `scripts/levels/enemy_roster.gd`: `scene`, `tier`, `size`,
`weight`, `unlock_sector`/`unlock_depth` (spawn gating), `chaff` flag,
`conflict_tags`. Decide the gating/weight with the **enemy-design** agent so it
fits the pacing.

### 6. Verify + ship
Run the **/ship** skill: parse_check + headless boot (confirm the scene
instantiates and the script compiles) + commit the `.uid` sidecars + push +
report to the user. If the art is placeholder or it's now in live waves, HOLD the
publish and surface that to the maintainer.

## Notes
- Cross-refs: `docs/contributing/03`, memories `feedback_placeholder_in_prod_waves`,
  `feedback_hitbox_rule`, `feedback_auto_rotate_default`.

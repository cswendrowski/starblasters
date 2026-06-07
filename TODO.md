# Starblaster TODO

Captured from Cody's 2026-05-19 punch list. Ordered roughly by leverage.

## Controls + Player

- [x] **Rebind to genre conventions** — `5d36dcc`. Z+Space = primary, C = secondary, X = super, Shift = focus, Q/E weapon swap.
- [x] **Focus Mode** — `5d36dcc`. Hold Shift → speed × 0.55 + hitbox dot at player center.
- [x] **Settings remap UI** — `1cf36be`. Options overlay Controls section, click-to-rebind per action. Keyboard only (gamepad rebind in-app still deferred).
- [x] **Cross-session keybind persistence** — `2cdc4cd`. Settings.keyboard_overrides dict JSON-serialised to settings.cfg + replayed on Settings._ready.
- [x] **Autofire toggle** — `fba545a`. Settings.autofire (checkbox in Options).
- [x] **Gamepad support** — `94be6ab`. D-pad / left stick for movement; A/B/X/Y + LB for action buttons.

## Weapons + Parts

- [x] **Secondary fire pipeline + shuffle missile/rocket to HARDPOINT_WING** — `278066e`.
- [x] **Spread Cannon** — `83cd9f5`. Fans bullets, Mk adds bullets.
- [x] **Smart Bomb** — `b9e3458`, `ee904d9`. Screen-clear + heavy damage + 0.6s invuln.
- [x] **Hyper Mode** — `073a709`. 3 s supercharged primary + invuln.
- [x] **Phase Shift** — `073a709`. 2 s invuln + bullet cancel.
- [x] **Particle Beam (secondary)** — `0c0042e`, `cffbc25`, `446f5c2`, `dad6669`. Continuous beam, pierces chaff, stops on tough/boss. Width scales per Mk; 3-layer halo/main/core visual.
- [x] **Side Pods (secondary)** — `cff4d38`. Multi-pod forward fire, Mk adds pods (2 → 8).
- [x] **Drone Bits (secondary)** — `7981440`. Gradius Options — companion drones piggyback primary fire.
- [x] **Drone Swarm (super)** — `b1b57b4`. 5 s burst of 4-6 drones; reuses PlayerDrone scene.
- [x] **Outpost refill for super charges** — `3cbfef0` (free on visit), `39c6f1b` (paid in-station button).
- [x] **HUD super_charges pip strip** — `e41cf49`.
- [x] **Filter Weapon Editor list by slot_type** — `ff47632`.
- [x] **Touhou death-bomb hook** — `e41cf49`, `ee904d9`.
- [x] **PartFactory consults `resources/weapons/*.tres`** — `c54befc`.

## Onboarding

- [x] **Updated for new keybinds + Mk system** — `57faad3`.

## Dev Menu Cleanup

- [x] **Remove obsolete buttons** — `35a66a2`.
- [x] **Shipyard + Ship Sizer merge** — `1f1fd8a`. Scale slider + flip toggle folded into Shipyard. Ship Sizer dropped from dev menu. Stat editor / sprite picker remains a follow-up.
- [x] **Unified Test Combat launcher** — `eb45a8f`.

## Asteroid Lab

- [x] **Fix slider wiring + visuals** — `7835360`, `b3abdbb`, `d9feb54`. Inner ColorRect sized from Size slider; pivot centered; tints applied to inner directly; numeric readouts; smaller rail; asteroid centered in right half.

## Visual / FX

- [x] **Outline shader + preset material** — `93f4763`. `shaders/outline_1px.gdshader` + `resources/materials/outline_1px_black.tres` (round, 1px black).
- [x] **Outline asteroids in the asteroid hazard playspace** — `0a16c51`.

## Follow-ups (not in scope this pass)

- [ ] **Shipyard stat editor / sprite picker** — full unit authoring tool (edit HP, bounty, speed, hitbox, sprite per enemy in-game). Deferred — bigger UI refactor than this pass. Godot inspector on enemy `.tscn` is the authoritative path until then.
- [ ] **Gamepad rebind in-app** — keyboard rebind UI persists across sessions, but gamepad button reassignment still requires editing `project.godot`.
- [ ] **WaveGeneratorV2 + scene removal** — V2 wave path is now unreachable from the dev menu but the script + scene + dev/wave_tester.tscn remain on disk. Safe to delete once nothing in the runtime path references it (main.gd's `wave_v2_knobs` meta branch is dead code).
- [ ] **Old Ship Sizer scene + script** — left on disk after the Shipyard merge; unreachable from the dev menu. Same cleanup posture as V2 wave.
- [ ] **Drone autonomy** — current Drone Bits + Drone Swarm drones only fire when the player fires primary (piggyback model). Truly independent target acquisition + cadence is a follow-up if the feel warrants. [PARTIAL: 2026-05-21 — Drone Swarm now autonomous, picks bosses then nearest enemy, fires basic blaster (commit `e6c42a6`). Drone Bits was redesigned into Shield Drones (ablative, non-firing) in the same commit.]

## Cobalt 2026-05-21 backlog

- [ ] **Dynamic animated nebula** — adjust nebula to be dynamic, animated, noise-based, and seamless. Current V3 nebula uses `nebula2.gdshader` (domain-warped + filaments, scroll_offset driven from layer accumulated scroll). May need new shaders for a fully animated swirl. Build prototype + capture for review.
- [ ] **V3 parallax color correction + adjustment sliders not working** — Brightness / Contrast / Colorization in the tuner aren't tinting V3 layers reliably. After the CanvasGroup removal we're on per-child modulate via the tuner's fallback path; need to confirm whether modulate IS being written and whether Parallax2D propagates it through tiled draws in Godot 4.3. **Also add a blend-mode dropdown** for the per-layer color system (Mix / Add / Multiply / Screen).
- [ ] **Phase Shift + Focus supers not working** — investigate why both super actions are no-op when triggered. Verify the super_part hook + activate() path.
- [ ] **Drone Swarm super emit point** — drones should emit from the player center on activation (currently spawn at the wing-halfspan offset).
- [ ] **Direction-based player sprite rotation** — the player ship sprite used to rotate based on horizontal input direction; this seems to have been lost in the horizontal-rework branch. Restore the frame-swap / rotation behaviour.

## Enemy rework backlog 2026-05-24

- [ ] **480-speed Dart reaction-test variant** ("Sprint Dart") — distinct enemy for late-game; reuses Dart sprite + faster movement (~480 px/s), no shoot. Spun off from the 2026-05-24 speed pass where Dart was dropped from 480 → 360 for fair-play; the 480 tier still wants to exist as a deliberate reaction test.
- [ ] **Per-enemy-class loiter timing** — Beam Shooter / Gunship / Crystal / Cruiser / Drone Carrier currently share the identical `enter 110 / hold 3 / exit accel 300 max 350` cadence on the `Loiter` pattern. Fold into a per-enemy-class rework like chaff got (medium tier ~130 / 3 / 400-450; large tier ~90 / 4 / 280 per the §3 doc). Out of scope of the 2026-05-24 speed pass.
- [ ] **Bullet library refactor (B2)** — replace the single `enemy_bullet.tscn` + 200 px/s baseline with a roster of bullet variants (dumb 220 / aimed 300 / heavy 180 / fast 240) selectable per shoot_pattern. Doc audit §3 + §1 reference bands. Cheapest path is a `bullet_speed` @export on `shoot_pattern.gd` honored in `_spawn_bullet`, but designer prefers a real bullet-resource roster rather than a single override knob.
- [ ] **Bulwark drift retune** — bulwark_drift currently 25/36/0.35; doc §3 proposes 50/50/0.45. Folded into a separate Bulwark-turret pass alongside the shielding rework.

## Hazard rework backlog 2026-05-24

- [ ] **Overhaul Asteroid Hazard** — current asteroid_field level needs a structural pass. Cody flagged background asteroids overlapping the playspace; APT confirmed the underlying behavior isn't what was described and the level wants a broader rework, not a spawn-range patch. Defer until the hazard rework slot opens.

## New 2026-05-25 (designer)

- [x] **Cull the sector V3 dev menu** — done in dev tooling cleanup (this commit). Also dropped WaveGeneratorV2 + dev/wave_tester + the old dev/ship_sizer in the same pass. Grid annotation pattern preserved in `scripts/dev/grid_overlay.gd` for the new UI Plotter.
- [x] **POI visited state — disable lights + decor on resolve** — `641cb79`. Completed POIs skip planet/asteroid/cluster decoration + pulse-glow / glitter / hover label.
- [x] **Grid-based screen designer** — shipped as `scripts/dev/ui_plotter.gd` + `scenes/dev/ui_plotter.tscn`. Pick a player screen from the modal, overlay 8/16/32px annotated grid (G/L hotkeys), live mouse-cell readout. Reuses the V3 sector map grid via `scripts/dev/grid_overlay.gd`.

## Outstanding 2026-05-25 (sweep)

Captured from research docs (`docs/*.md`), recent commit bodies, agent "Open" flags, and project memory. Existing entries above not duplicated.

### Bosses (`docs/boss_proposals_2026-05-24.md`)

- [ ] **Boss roster gaps — Spinwright + Conductor** — proposal's 7-boss roster ships 5 of 7 (`boss.gd` Commander, `boss_reaver.gd` → Lash, `boss_sentinel.gd` → Aegis, `boss_howler.gd`, `boss_voidmaw.gd`). Missing: **Spinwright** (transforming ring + beam-sweep, S2-3) and **Conductor** (final, mirror/predictive + transforming, S3 row-3). No `boss_spinwright*` / `boss_conductor*` files on disk. (Source: `docs/boss_proposals_2026-05-24.md` §4)
- [ ] **Tethered-orbit movement resource** — Conductor needs a `scripts/enemies/patterns/` movement resource (~50 lines) for satellites mirroring player X. (Source: `docs/boss_proposals_2026-05-24.md` §4 Conductor)
- [ ] **Biome reskins per boss** — palette + one attack tweak variants to double visual variety once base roster ships. (Source: `docs/boss_proposals_2026-05-24.md` §5)
- [ ] **Shared boss-enrage VFX helper** — phase-transition flash + screen-shake helper so HP-gate transitions read consistently across bosses. (Source: `docs/boss_proposals_2026-05-24.md` §6 open question 6)
- [ ] **Boss `conflict_tags` "never-pair" enforcement** — Voidmaw shouldn't pair with Commander; Howler shouldn't pair with Reaver/Lash; etc. (Source: `docs/boss_proposals_2026-05-24.md` §6 open question 4)
- [ ] **Bosses with omni-strafe** — designer-flagged variation idea, currently deferred. (Source: task list #12)

### Enemies / Bullets

- [ ] **Bullet library refactor (B2)** — `BulletVariant` Resource + 7 variants (Basic/Aimed Sniper/Heavy Slug/Spread Pellet/Plasma Orb/Tracker/Burst Round); APT sprite list ready. Currently every enemy bullet is one scene at 200 px/s. (Source: `docs/bullet_library_2026-05-24.md`; task #17 deferred. Already in Enemy rework backlog above — keeping single citation.)
- [ ] **Boss bullet primitives accept `bullet_variant`** — `boss_base.fire_aimed_burst` / `fire_ring` default to Basic; add optional variant param. (Source: `docs/bullet_library_2026-05-24.md` §6 open question 4)
- [ ] **Wave-gen `bullet_variant_override` knob** — themed waves force all enemies to fire variant X. Add if themed waves land. (Source: `docs/bullet_library_2026-05-24.md` §6 open question 2)
- [ ] **Per-pattern `bullet_speed` override** — `@export var bullet_speed: float = -1.0` on `shoot_pattern.gd` honored in `_spawn_bullet`. Cheapest path before the full bullet-library refactor; aimed shots want 300 not 200. (Source: `docs/enemy_speeds_2026-05-24.md` §3, §5)
- [ ] **Chaff-speed sector scaling** — `+5%/sector` cap `+25%` if player damage already scales. (Source: `docs/enemy_speeds_2026-05-24.md` §5 open question 4)
- [ ] **`AimedShot.lead_factor` on Skirmisher** — flip from 0 to ~0.15 for "experienced gunner" feel without raising bullet speed. (Source: `docs/enemy_speeds_2026-05-24.md` §4)
- [ ] **Hunter Drone kamikaze bounty cancel** — `enemy_roster.gd:97` lists 5 bounty; `enemy_hunter_drone.gd` says "no bounty for kamikaze hit" — verify the cancel-on-hit path actually fires. (Source: `docs/economy_2026-05-24.md` §5)

### Economy (`docs/economy_2026-05-24.md`)

- [ ] **Mk power asymmetry (P2)** — weapons scale 7-9× across Mk1-9; hull caps at 1.8×. Proposal: flatten `mark_multiplier()` to `1 + 0.25*(mark-1)` and raise base damage to compensate; hull `10 + 2*hull_mk`. (Source: `docs/economy_2026-05-24.md` §1.6, §4)
- [ ] **Boss bounty share is 72% (P3)** — combat nodes earn ~3× less than bosses. Either nerf boss payouts or add a combat-clear bonus (+20) / hazard-clear bonus (+25). (Source: `docs/economy_2026-05-24.md` §3 P3, §5)
- [ ] **Mk-Gating: asymmetric cannon vs upgrade caps** — Upgrade cap `min(9, 2 + sector*2)`, Cannon cap `min(9, sector*3)` so Mk 9 cannons become the run's identity moment. Currently both share `sector + 3`. (Source: `docs/economy_2026-05-24.md` §4)
- [ ] **Boss-clear unlock bumps** — each row-boss kill bumps remaining outpost Mk-cap floor in that sector. (Source: `docs/economy_2026-05-24.md` §4(b))
- [ ] **Smart Bomb auto-bomb has no economy cost (P10)** — free auto-bomb on lethal hit + free outpost refill. Pick a cost. (Source: `docs/economy_2026-05-24.md` §3 P10)
- [ ] **`wanted` / `dangerous` POI bounty multipliers** — modifier tags now generate (#76 shipped) but bounty effect (`wanted` +30%, `dangerous` +50%) not yet wired in. (Source: `docs/economy_2026-05-24.md` §5)
- [ ] **Outpost density too high (~3/sector)** — consider 1 outpost + 1 Junk Trader signal/sector to feel scarcer + more decisive. (Source: `docs/economy_2026-05-24.md` §5)
- [ ] **Asteroid 0-bounty default** — hazards are bounty deserts. Default `+1/asteroid` or flat hazard-completion bonus. (Source: `docs/economy_2026-05-24.md` §5)
- [ ] **Hull formula Mk-9 cliff** — `max_hull = 20 if Mk≥9 else 10+Mk` has odd cap jump; replace with `10 + 2*hull_mk` or `10 + 3*hull_mk`. (Source: `docs/economy_2026-05-24.md` §5)
- [ ] **Resale arbitrage** — outpost cannon 50%, signal-event part 30% (now 20% per #75?). Verify rates symmetric; otherwise player picks the better venue. (Source: `docs/economy_2026-05-24.md` §3 P6)
- [ ] **Manage Ship modal PartTier badges + 20% sell UI** — modal not yet using the shared `part_tier.gd` helper or the 20% resale. (Source: commit `cd71f44` open flag)
- [ ] **Outpost density hard clamp → probabilistic** — current sim: 2 outposts 51%, 3 outposts 23%, 4 outposts 26%; 0/1/5+ blocked. Designer flagged need for "rarely 1, super rarely 0" tail. (Source: commit `cd71f44` open flag)

### Visual / VFX

- [ ] **Dynamic animated nebula** — already in Cobalt 2026-05-21 backlog above; keep.
- [ ] **V3 parallax color sliders not working + blend-mode dropdown** — already in Cobalt 2026-05-21 backlog above; keep.
- [ ] **Galaxy Backdrop V3 missing debris sprite** — `scripts/parallax/galaxy_backdrop_v3.gd:392` `# TODO — needs a debris sprite`. (Source: `scripts/parallax/galaxy_backdrop_v3.gd:392`)
- [ ] **Moon vs planet wrap-around desync on >226s combats** — pre-existing flag carried across multiple agents. (Source: commits `2083c59` / `1532071` open flags)
- [ ] **`current_stellar` cleared per POI click** — combat backdrop will look uniform across a sector. Eyeball + decide. (Source: memory `project_sector_map_v3.md` §Known open issue 2)
- [ ] **Shadow shaders cluster — retire prototypes** — `graphics/masked_shadow.gdshader`, `graphics/topdown_shadow_outofbounds.gdshader`, `graphics/drop_shadow_canvas_group.gdshader` + 6 `tools/capture_shadow_*` drivers (a/b/iterate/mask/ray/test) are capture-only prototypes; oblique-shadow won. (Source: `docs/redundancy_audit_2026-05-21.md` §Shadow shaders — confirmed still on disk 2026-05-25)
- [ ] **Parallax shader cluster — retire** — `graphics/parallax_silhouette.gdshader`, `graphics/parallax_tint.gdshader` (+ `TINT_SHADER` preload const in `scripts/parallax/galaxy_backdrop_v3.gd`); both unused after V3 CanvasGroup removal. (Source: `docs/redundancy_audit_2026-05-21.md` §Parallax shaders — confirmed still on disk 2026-05-25)
- [ ] **`starstuff.gdshader` retire pending confirmation** — legacy fallback for V1's `use_starstuff` @export (default false). (Source: `docs/redundancy_audit_2026-05-21.md` §Parallax shaders)
- [ ] **Audit `particle_trail.gdshader` + `bloom.gdshader` references** — not preloaded anywhere visible; confirm via scene materials or retire. (Source: `docs/redundancy_audit_2026-05-21.md` §Other shaders)
- [ ] **NEBULA_SHADER preload dead in V3** — V3 uses NEBULA2; the V1 shader preload in `galaxy_backdrop_v3.gd` is dead in V3 specifically. (Source: `docs/redundancy_audit_2026-05-21.md` §Summary)

### Weapons / Architecture (`docs/weapon_architecture_2026-05-24.md`)

- [ ] **`scripts/bullet.gd` + `scripts/bullet_wave.gd` live at `scripts/` root** — siblings are in `scripts/projectiles/`. Move + update `.tscn` paths. (Source: `docs/weapon_architecture_2026-05-24.md` §5)
- [ ] **`drone_bits.apply()` doesn't snapshot prior `ship.drone_bits` array** — practical impact low (swarm drones self-manage lifecycle), flagged for designer awareness. (Source: commit `2083c59` open flag)
- [ ] **Heavy Blaster cooldown lerp 0.20 → 0.18 per Mk** — tiny per-Mk drift introduced by refactor; can be reverted by setting constant `0.20`. (Source: commit `2083c59` open flag)
- [ ] **basic_blaster + spread_cannon snapshot/restore asymmetry** — set `weapon_style`/`fire_sfx_kind` without symmetric restore in `unapply`. (Source: commit `2083c59` open follow-up)
- [ ] **`drone_bits.tres` + `drone_swarm.tres` stale defaults** — open in editor, re-save against current `.gd` defaults so Weapon Editor doesn't surface stale values. (Source: `docs/redundancy_audit_2026-05-21.md` §Weapons action items)
- [ ] **Weapon mounts: per-Part `fire_offset: Vector2`** — so wing-mounted vs nose-mounted weapons don't all spawn at `(0,-10)`. (Source: `docs/weapon_architecture_2026-05-24.md` §4 item 5)
- [ ] **`burst_shot.tres` — author designer instance** — `scripts/enemies/shoot_patterns/burst_shot.gd` has no `.tres` companion. (Source: `docs/redundancy_audit_2026-05-21.md` §Enemy shoot patterns)

### Dev tools

- [ ] **WaveGeneratorV2 + `scenes/dev/wave_tester.tscn` removal** — already in Follow-ups above; keep.
- [ ] **Old Ship Sizer scene + script** — already in Follow-ups above; keep.
- [ ] **`scenes/sector_map.tscn` orphan** — pre-existing, no V suffix, referenced by `feature_showcase.gd` + `tools/parse_check.ps1`. Clean once safe. (Source: memory `project_sector_map_v3.md` §Known open issue 3)
- [ ] **`SmokeTrail.new(palette)` factory** — consolidate `damage_smoke_trail.gd` + `missile_smoke_trail.gd` (~90% shared code) once a third smoke emitter appears. Not urgent. (Source: `docs/redundancy_audit_2026-05-21.md` §Particle effects)

## Faction gap units — sprites/enemies to commission (M6b, 2026-06-06)

End-state (Roman): each faction owns its FULL unit set; drop the universal-core stopgap.
The only thing truly cross-faction is **adding privateer units into another faction's pool**.
Below = the per-faction slots NOT yet covered by a faction-OWNED hull (currently filled by a
universal-core overlay). Each entry = **role / behavior @ size**. Get sprites worked up, then
they become data on the existing chassis/behavior/component/Weapon machinery (new art only).
Full context + the coverage matrix: `docs/m6b_faction_tagging_2026-06-06.md`.

> **STATUS 2026-06-07 (post-M6c):** three faction art packs + the gunship/interceptor
> move landed. Per-faction OWNED-exclusive counts now (on top of the 10 shared universal
> hulls): **supremacy 4, zealot 8, corporate 8, privateer 9.** ✓ = now covered by a
> faction-owned hull; remaining bullets still need art.

- [ ] **supremacy (Crimson Supremacy — faster fire)**
  - ✓ Charger (rush), ✓ Sweeper (plasma), ✓ Anchor (push — replaced frigate), ✓ fighter+Weaver (hotrod, dive/straight/weave; replaced strafer)
  - STILL: dedicated small **Drifter**, dedicated small **Crosser**, an **elite** event piece
  - (owns: Diver=bomb_drone, Holder=crystal, capital=cruiser, + rush/hotrod/plasma/push)
- [ ] **zealot (Evantian Theocracy — drops firecore)**
  - ✓ Holder + Skirmisher (retro), ✓ Drifter (manta — replaced drifter), ✓ Weaver-ish (run, unarmed weave), ✓ Crosser/pusher (sword)
  - STILL: a **non-elite Anchor @ medium**, a **non-elite capital @ large** (helix/beamers/burner are all RARE elites; sword is small)
  - (owns: Diver=spitter, pressure=firecore_drone(bloom), elite-capital=firecore_cruiser(helix), Sweepers=beamers, elite=burner, + retro/run/sword/manta)
- [ ] **privateer (Vertarine Armada — tough; the overlay faction)**
  - ✓ Weaver (green), ✓ medium Anchor (cannon / rocket / gunship), ✓ pressure (pulse), ✓ Dropper (drop), ✓ omni gunship + hold/weave/shift/skirmish variants
  - STILL: small **Holder** + small **Skirmisher** (only MEDIUM exist), a **large capital**, an **elite** event piece
  - (owns: Diver=dart, Crosser=cutter, Dropper=minelayer, Slider=interceptor[moved in], + green/gray/drop/cannon/pulse/gunship/rocket)
- [ ] **corporate (UltraGalactic — shielded)**
  - ✓ own Diver (gray), ✓ own chaff Weaver+Dropper (curve/drop), ✓ re-skinned Holder (hold — replaced hover)
  - **NEW GAPS from the M6c moves:** interceptor (Slider) + gunship (elite) LEFT for privateer; strafer (Striker) retired for supremacy hotrod. Corporate keeps Striker=hunter_drone, capital=bulwark, elite=drone_carrier — but lost its **Slider** role and one **elite**.
  - (owns: Weaver, Holder=hold, Skirmisher, Harrier=sapper[rare], Striker=hunter_drone, Anchor=bomber, capital=bulwark, elite=drone_carrier, + gray/curve/drop)

Also pending art/rename housekeeping: **spitter** (firecore popper rename, §12.5); a
**privateer/supremacy** large-capital silhouette if cruiser shouldn't be shared.

## Already-done (since this list was captured)

- Wave editor with full CRUD + playtest + state persistence.
- Movement Pattern Editor + Shoot Pattern Editor (reflection-driven, live preview).
- Weapon Editor (Mk slider, DPS readout, tracer preview).
- HD viewport pattern (`Window.content_scale_size` swap) for text-dense dev pages.
- Wave Editor → pattern editor round-trip via `pattern_editor_return_scene` meta.

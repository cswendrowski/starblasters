# Worklist

_Refreshed 2026-06-12: folded the open items from `TODO.md` into one curated working list, marked the
2026-06-11/12 VFX batch done, and added the **nebula investigation** (bottom). Deep specs still live in
`TODO.md` / `docs/` — this is the scannable index, not a re-paste._

---

## In-flight (this session — awaiting eyeball + commit)
- **`outline_1px` forward_plus crash fix** — removed the `check(sampler2D)` function-param that
  hard-faulted combat on Forward+; confirm asteroid + normal combat boot clean, then commit.
- **Progressive burn trails + torch precursors** (`ship_damage_tells.gd`) — multiple trails by ship
  size, torch→trail handoff, burst/scale-in intros. Tune in Shader Lab → Ship Dmg.
- **Ship-Dmg size filter fix** — bands re-tuned (small <1.5 / med <2.5 / large), categorized pool
  (no more wrong-size fallback). Verify each band spawns the right size.

## Shaders / VFX — DONE 2026-06-11/12 (awaiting eyeball)
- ✅ Centralized tunable explosion system (`play_config`: size/area/duration/density/type/glow/
  shockwave) + editor-tweakable ember/spark particle scenes.
- ✅ Ship damage-tell suite (overlay → marker sparks → burn → disintegrate, per-size tunable).
- ✅ Smoke trail rebuild + `spark_trail`/`burning_trail`; fire-comet shader scrapped.
- ✅ Sequence Lab (wreck / bomber / slow-death). Enemy Bench: full roster + faction tabs + mines disarmed.
- ✅ glow_effect_2d tuners, ember-smoke variant, debris-fire tuner, smoke orient-to-motion.

### Still open (eyeball)
- ✅ **Glow-halo redundancy (DONE 2026-06-12)** — pulled the `GlowShaderFx` halo off all 5 projectiles
  (player/enemy bullets, wave, shredder, swarm); env bloom glows the bolts directly, which also
  resolves the bullet glow-ghost residuals. Engines: enemy flame was already disabled (trails carry
  them); player GlowMask KEPT (Roman's call — it's the emissive source bloom amplifies, not a halo).
  Coupling: combat `glow_hdr_threshold` is 0.0 today so bolts still bloom; if lever A raises it to ~1.0,
  brighten bolt sprites HDR-additive (lever C) or they'll stop blooming.

## Nebula  *(rework DONE 2026-06-12 — awaiting eyeball; findings at bottom)*
- ✅ **Dynamic swirl + re-enabled per-POI.** Added `swirl_speed` to `nebula2.gdshader` (TIME-driven
  warp churn, default 0 = legacy); `sector_map_v3._compute_poi_stellar` now rolls a `nebula_band`/
  `nebula_tint` on ~40% of nodes; `backdrop_coordinator` enables + tints + swirls the stellar layers
  from it. Shader Lab → **Nebula** page added for live tuning. Verified wiring end-to-end.
- **Eyeball + tune:** review the in-combat look (GIF `captures/nebula_live.gif`), then set per-band
  alpha/density + the coordinator's `nebula_swirl` + `NEBULA_NODE_CHANCE` to taste.
- **Parallax tuner blend-mode dropdown** *(still open, separate)* — the Brightness/Contrast/Color
  sliders are VERIFIED WORKING on the live V4 backdrop (the old "not working" note was stale, from the
  V3/CanvasGroup era). Remaining ask = a Mix/Add/Multiply/Screen blend-mode option for the per-layer
  color. Non-trivial: `CanvasModulate` is multiply-only, so Add/Screen need a per-layer overlay or a
  grade shader — scope on its own. (`layer_base.gd` / `parallax_tuner.gd`)

## Audio
- **Corpo-wave audio restart** — music stops then restarts when a round begins (`music_manager.gd`).

## Weapons / data
- **Weapons 3b** — unify legacy SingleShot/AimedShot/SpreadShot/BurstShot onto the `Weapon` resource
  (folds in `burst_shot.tres`).
- **Dev bullet-speed editor** — edit enemy bullet speeds in absolute rungs (1–8 = 60–480 px/s,
  Clarity-snapped) and **save** to `data/bullets/*.tres`.
- **Codex label rename** — "Primary Cannons" → "Blaster" (`enemy_codex.gd:58`).
- **DPS report + `weapon_stats.csv`** — regen for Shredder + Pulse Laser; fix the `.import`
  (csv_translation → `.translation` junk) first; then the rebalance call (Energy Blaster top DPS as the
  free fallback, Minigun too weak, Autocannon scales backwards).
- Smaller bullet knobs: per-pattern `bullet_speed` override, boss primitives accept `bullet_variant`,
  wave-gen `bullet_variant_override`, chaff-speed sector scaling, `AimedShot.lead_factor`, verify
  hunter-drone kamikaze bounty-cancel.
- Architecture/cleanup: Muzzle-flash-as-scenes (optional), per-Part `fire_offset`, re-save
  `drone_bits.tres`/`drone_swarm.tres`, relocate `scripts/bullet.gd`/`bullet_wave.gd` to `projectiles/`.
- **Manage Ship modal** — PartTier badges + 20% sell UI.

## Big features (unbuilt)
- **Passive-Module bay** — 4-slot automatic-module axis + reify shields/regen/plating as Parts +
  ~10-module roster (Repair Nanites, Ablative Plating, Targeting Computer, Overclock, …). Largest item.
  (`TODO.md` §Supers/Modes/Modules)
- **Run summary Phases 2–3 + run timer** — shots/accuracy/bounty-spent instrumentation + the victory
  "patrol complete" path (Phase 1 + dated history already shipped).
- **Sector modifiers** — pulled (kill-switched); flagged for re-eval + reimplement.
- **Recycler — Pillar 2** — RecycleController + RecycleTuner + roster migration (playtest-gated).

## Enemies / waves  *(playtest-gated)*
- Cohesive chaff waves / bomb-drone walls / minefield real numerics + dense navigable patterns.
- Conductor no-repeat patterns + mix-and-match lane patterns.
- Speed audit to the 1–8 rungs (partial). Supremacy Push globbing (active lane selection).
- s_s_rush movement facing. Tracer doubled-glow art bug. 480-speed "Sprint Dart" variant.
- Mine hazards → 300-enemy density.

## Bosses
- Biome reskins per boss. Shared enrage-VFX helper. Bosses with omni-strafe.

## Renderer (`docs/renderer_audit_2026-06-11.md`)
- ✅ **Lever A** (`glow_hdr_threshold = 1.0`) + ✅ **Lever B** (color grade, contrast 1.08 / sat 1.12)
  — already LIVE in main.tscn (the audit doc's "0.0" was stale).
- ◑ **Lever C** (push FX into HDR-additive so they bloom): done for muzzle/explosion (1.9/2.1) +
  bullets (`base_bullet.BULLET_HDR_GAIN = 1.8`, after the glow-halo removal — **eyeball the gain**).
  Still want a >1.0 additive pass on **shield ring / beam cores / super flashes / engine GlowMask**.
- ☐ **Lever D** (screen-space sweeteners): heat-haze behind exhaust, ripple on big booms, damage CA.

## Art-gated (need sprites first)
- **Faction gap units** — per-faction role holes still on the universal-core stopgap: supremacy
  (drifter/crosser/elite), zealot (medium anchor / large capital), privateer (small holder/skirmisher,
  large capital, elite), corporate (slider + elite). (`docs/m6b_faction_tagging_2026-06-06.md`)
- **Overhaul Asteroid Hazard** — structural pass (bg asteroids overlapping playspace); hazard-slot.

## Cleanup
- `scenes/sector_map.tscn` orphan (flagged-for-later). `SmokeTrail.new(palette)` factory (not urgent).
- Shipyard stat editor / sprite picker. Gamepad rebind in-app. Backdrop V3 missing debris sprite.

---

## Nebula — investigation findings (2026-06-12)

**Live path:** combat Backdrop = `backdrop_coordinator.tscn` (coord_v4 in `main.tscn`) →
`LayerStellarFar/Mid/Near` (`scripts/parallax/layer_stellar.gd`) → `_spawn_nebula()` →
`graphics/nebula2.gdshader`.

**Headline — the nebula is DISABLED in combat.** `nebula_enabled = false` in all three
`scenes/parallax/layers/layer_stellar_*.tscn` (and the script default), and nothing flips it on at
runtime — the coordinator never reads the `nebula_band`/`nebula_tint` stellar data that `run_state`
already generates per node. So `_spawn_nebula()` never runs in-game. Git: it was enabled across all 3
layers (`cb2ed0c`) then turned **off in-editor** (preserved by `caa1f8f`) — i.e. deliberately parked
pending this rework, which is why the "dynamic animated nebula" item exists.

**The shader is a solid base.** `nebula2.gdshader` = procedural domain-warped FBM (curling-filament IQ
recipe) + a wisp/filament band + pixelation → seamless, noise-based, pixel-art-safe. Knobs:
scale/octaves/density/edge/warp_strength/warp_scale/wisp_strength/opacity/max_alpha/drift_speed.

**Animation today (when enabled):**
- **Parallax scroll** — `layer_stellar._on_scrolled` holds the rect screen-fixed (`position.y =
  -offset.y`) and drives the shader's `scroll_offset` from the layer's accumulated `offset.y` → the
  cloud scrolls past as you fly (3 stellar bands = parallax depth). ✓
- **Slow internal TIME drift** on Y (`drift_speed 0.004`). ✓ but very subtle.

**The gap → "fully animated swirl."** The domain-warp FIELD is static in shape — it only TRANSLATES
(scroll + drift); the filaments never curl/churn/morph in place, so it reads as a frozen texture
sliding by. Fix is cheap and needs **no new shader**: add a `swirl_speed` uniform to `nebula2.gdshader`
and feed `TIME` into the domain-warp sample coordinates (and optionally the wisp layer) so the curl
field evolves over time. Keep it slow (it's a backdrop) to avoid distracting from gameplay.

**Recommended sequence:**
1. Add TIME-driven swirl to `nebula2.gdshader` (`swirl_speed` uniform on the warp coords).
2. Re-enable via the coordinator: set `nebula_enabled` + tint per-POI from the existing
   `nebula_band`/`nebula_tint` stellar config (varies per node, respects the sector palette) rather
   than a blanket scene flag.
3. Capture with `tools/capture_nebula2.gd` → GIF for review **before** tuning alpha/density per band
   (max_alpha is intentionally low — 0.1/0.2/0.15 far/mid/near — so it stays a backdrop).
4. (Separate) fix the parallax-tuner color sliders + add the blend-mode dropdown.

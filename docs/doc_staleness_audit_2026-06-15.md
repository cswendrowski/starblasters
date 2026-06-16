# Documentation Staleness Audit — 2026-06-15

Status: **REPORT ONLY** — nothing in the repo was changed to produce this. It is a triage
sheet + recommended action plan. Verdicts were cross-checked against the live code by seven
parallel auditors; every "current reality" below is code-backed.

Source of truth for all judgements = the current code in `E:\Godot-Projects\starblasters`.

---

## 1. Executive summary

The docs are not randomly wrong — they drift along **~8 systemic fault lines**, almost all from
big migrations the docs never caught up with:

- the 2026-06-10 **Forward+ / Windows-only pivot** (Web/`gl_compatibility` retired),
- the 2026-05-26 **engine consolidation** (single Godot 4.6.3 standalone, no Mono),
- the 2026-06-14 **file reorg** (`scripts/X.gd` → subfolders; bosses → `scripts/enemies/bosses/`),
- the **slot → module-bay** redesign (2026-06-13),
- the **combat/economy overhaul** (lane conductor, factions, outpost-as-hub),
- the **weapon-data centralization** (2026-06-11, stats moved to `.tres`).

The staleness runs **both directions**:
- many docs say *"not built"* for things that **shipped**;
- a few say *"LOCKED / canonical"* for things that **never shipped**.

**Structural root cause:** nothing reliably distinguishes a *live spec* from a *historical
snapshot*. Dated filenames help, but authoritative-sounding docs (e.g. the undated
`enemy-pattern-analysis.md`, or `combat_lane_wave_bridge` which brands itself "CANONICAL /
THIS WINS") still get cited as current. The durable fix is a status-header convention + an
index of what is canonical — see §6.

---

## 2. The 8 drift axes (fix once, applies everywhere)

| # | Axis | Current truth (code) | Worst offenders |
|---|------|----------------------|-----------------|
| 1 | Renderer / target | `forward_plus`, Windows-only; Web/HTML5 **retired** 2026-06-10 | README, ONBOARDING, contributing/01 & /06, `publish-gate`, `smoke-runner`, `capture-scripter`, most superpowers docs |
| 2 | Engine version | Godot **4.6.3 standalone, no Mono** | `publish-gate` (4.4.1), `capture-scripter` (4.3 mono), `design-reviewer` (4.3/4.4.1 split) |
| 3 | 2026-06-14 file reorg | `scripts/X.gd` → `scripts/{autoload,game,hud,screens,parts,parallax,levels}/`; bosses → `scripts/enemies/bosses/` | ONBOARDING, contributing/06, `godot-explorer`, `enemy-design`, `boss-composer`, `economy-sim`; both `file_reorg_*` docs still say "not executed" |
| 4 | Slot model | Live axes: `CANNON` (primary), `HARDPOINT_WING` (secondary), `DEVICE_BAY_1` (Smart Bomb), `SHIFT_MODE` (Focus/Phase/Hyper), `MODULE` (6-slot **list** bay), `ENGINE`. Dead-no-part: `WING_LEFT/RIGHT`, `TAIL`, `SHIELD`, `HARDPOINT_WINGTIP`, `DEVICE_BAY_2` | contributing/04, `game-design`, `ux-design`, `godot-explorer`, `part-author`, economy & supers docs, `weapon_mk_progression` |
| 5 | Outpost: node → hub | Persistent boss-refreshed **hub button**, not a per-row POI node | contributing/02, `economy_2026-05-24`, `progression_3pick` |
| 6 | Viewport size | **480×270** (4× = 1920×1080) | `game-design`/`ux-design` (800×1000), `capture-scripter` (320×400) |
| 7 | Weapon stats location | Stats live in `.tres`, not the script (2026-06-11) | `weapon_architecture`, `weapon_mk_progression`, `bullet_library` |
| 8 | Phantom files cited as canonical | None exist | `drone.gd`, `enemy_firecore.gd`, `wave_generator_v2.gd`/`WaveGeneratorV2`, `wave_director.gd`, `level_builder.gd`, `boss_sentinel.gd` (script), `sector_map_v2.gd`, `basic_*.gd`, `heavy_cannon.gd`, `manage_ship.tscn`, `sector_map_hd_lab.tscn` |

Note: ENGINE is **live** (engines roll in the shop) — only `WING_LEFT/RIGHT`, `TAIL`, `SHIELD`,
`HARDPOINT_WINGTIP`, `DEVICE_BAY_2` are dead-but-present enum scaffolding (intentional save-compat;
see `vestigial_parts_cleanup_2026-06-03.md`, which executed correctly).

Action key for the tables: **KEEP** = current, leave it · **FIX** = edit in place (a live surface
that can't be archived) · **ARCHIVE** = move to `docs/archive/` with a superseded banner ·
★ = high priority.

---

## 3. Per-file findings

### 3a. Always-loaded / canonical surfaces (cannot archive — must fix in place)

| File | Verdict | Risk | Core issue | Action |
|------|---------|------|-----------|--------|
| `CLAUDE.md` | Current | L | Routes `sector_map_v3.tscn`; actual routed scene is `sector_map_hd.tscn` (wraps v3). It hedges, so low impact. | FIX (1 line) |
| `docs/contributing/README.md` | Current | L | Accurate; engine/folders correct. | KEEP |
| `docs/contributing/01-getting-started.md` | Partially stale | **H** | `gl_compatibility`; publish section exports **Web** preset to `../Starblasters_html/` / `cswendrowski:html`; binary path `C:\Users\Cody\...`; dev-menu button list drifted (Wave Editor/Shipyard gone). | FIX★ |
| `docs/contributing/02-architecture.md` | Partially stale | **H** | Scene-flow shows **Outpost as a per-row node** the player clicks; it's a persistent hub button now. Cites `sector_map_v3` as routed scene (it's wrapped by `sector_map_hd`). | FIX★ |
| `docs/contributing/03-combat-waves-enemies.md` | Current | L | Matches post-reorg architecture. | KEEP |
| `docs/contributing/04-player-parts-economy.md` | **Stale/misleading** | **H** | Describes the **deleted outpost "Upgrades column"** as live; **omits the entire passive Module bay**; weapons-column weighting misses `SHIFT_MODE`. Highest-priority rewrite. | FIX★ |
| `docs/contributing/05-projectiles-effects-visuals.md` | Current | L | Root-parenting + FX helpers + PixelPlanets parity all correct. | KEEP |
| `docs/contributing/06-conventions-and-gotchas.md` | Partially stale | M | DirAccess gotcha framed as "HTML5/web" (web retired; still true for embedded-pck); link to `scripts/director.gd` (now `scripts/levels/director.gd`); dead `boss_sentinel` anchor. | FIX |
| `README.md` | Contradicts code | M | "`gl_compatibility` renderer", "Target: Web (HTML5)", "gated Web export". Three one-line edits. | FIX |
| `ONBOARDING.md` | **Stale/misleading** | **H** | Inverted target (says ships Web, not Windows); `gl_compatibility`; pre-reorg flat paths throughout (`scripts/main.gd`, `scripts/player.gd`, `scripts/enemies/boss_*.gd`); boots `sector_map_v2.tscn` (doesn't exist); Web publish channel/path; stale dev-menu list. | FIX★ |

### 3b. Memory files (auto-loaded each session — fix in place, can't archive)

Located in `C:\Users\roman\.claude\projects\E--Godot-Projects-starblasters\memory\`.

| File | Verdict | Risk | Core issue | Action |
|------|---------|------|-----------|--------|
| `MEMORY.md` (index) | Partially stale | M | Index one-liners for the 4 status memories below carry drifted framing. All 16 links resolve. | FIX (4 lines) |
| `planet-pixel-parity-sigsegv.md` | Current | M | Fix present (`layer_planet.gd`). | KEEP |
| `publish-environment.md` | Current | **H** | Channel/paths/version (0.1.117) all match. | KEEP |
| `sprites-native-scale.md` | Current | M | Timeless convention. | KEEP |
| `dont-read-capture-frames.md` | Current | M | Timeless workflow rule. | KEEP |
| `capture-harness-recipe.md` | Current | M | Binary/ffmpeg paths valid. | KEEP |
| `run-summary-plan.md` | **Status drifted** | **H** | Says "scoped, NOT built" — RunStats + run-history **shipped** (`main.gd`, `run_history.gd`). Landmine #1 (no victory screen) still true. | FIX (flip status) |
| `recycling-system-direction.md` | **Status drifted** | **H** | Says Pillar 2 "NOT built" — RecycleController + RecycleTuner **built and wired into `enemy_core`**. | FIX (flip status) |
| `sector-gen-and-backdrop-row-bugs.md` | Current | M | Bare filenames, reorg didn't break refs. | KEEP |
| `ui-unification.md` | Partially stale | M | Cites dead `scenes/manage_ship.tscn` + `sector_map_hd_lab.tscn` as live; HD port is done. Long; trim to load-bearing rules. | FIX |
| `scope-verification-to-task.md` | Current | L | Timeless. | KEEP |
| `bullet-glow-ghost-audit.md` | Current | L | Halos confirmed removed. | KEEP |
| `combat-redesign-spec.md` | Partially stale | M | Wave/faction half **built**; only economy (two-currency, ace-chain) still unbuilt. Heavy overlap with `combat-overhaul-status`. | FIX/merge |
| `combat-overhaul-status.md` | Current | **H** | "DONE/merged" claims hold. Long resume-log. Top consolidation candidate with the above. | KEEP (trim) |
| `moving-uid-referenced-scripts.md` | Current | **H** | Procedure correct; the reorg relied on it. | KEEP |
| `weapons-balance-status.md` | Current | **H** | Guardrail ("don't resurface rebalance") still valid. | KEEP |
| `forward-plus-texture-shader-gotcha.md` | Current | **H** | `outline_fx.gd` + shader fix present. | KEEP |

Consolidation: `combat-redesign-spec` + `combat-overhaul-status` overlap heavily (merge the
unbuilt-economy note into the status log). `capture-harness-recipe` + `dont-read-capture-frames`
+ `scope-verification-to-task` could merge into one "capture & verification" memory (low urgency).

### 3c. File-structure / reorg docs

| File | Verdict | Risk | Core issue | Action |
|------|---------|------|-----------|--------|
| `docs/file-structure.md` | Current | **H** | "Reorg DONE 2026-06-14" matches the tree. Authoritative. | KEEP |
| `docs/file_reorg_audit_2026-06-14.md` | **Stale/misleading** | **H** | Header says "AUDIT ONLY — not executed"; the moves **happened**. Its §2 orphan list is the only still-live value (cull not done). | FIX header (keep §2) |
| `docs/file_reorg_changemap_2026-06-14.md` | **Stale/misleading** | **H** | Framed as "before moving anything"; all batches executed. Superseded by `file-structure.md`. | ARCHIVE (banner: DONE) |

### 3d. Agent + skill directives (`.claude/` — fix in place, can't archive)

| File | Verdict | Risk | Core issue | Action |
|------|---------|------|-----------|--------|
| `agents/godot-explorer.md` | Stale/misleading | **H** | Mental-model block wrong on nearly every path: `sector_map_v2.gd`, `wave_director.gd`, `drone.gd`, root `scripts/*.gd`, 10-slot. Its job is correct citations. | FIX★ (rewrite section) |
| `agents/publish-gate.md` | Contradicts code | **H** | "4.4.1", "Mono fails Web export", `Classic Shmup.pck`, whole "Web export sanity" check. Gates releases. | FIX★ (rewrite section) |
| `agents/enemy-design.md` | Stale/misleading | **H** | Cites nonexistent `enemy_firecore.gd`; "3 movement × 4 shoot" (really ~30 × 7); misses factions/roster. | FIX★ (rewrite section) |
| `agents/boss-composer.md` | Partially stale | M | Base `scripts/boss.gd` (now `bosses/boss_base.gd`); roster "Commander/Reaver/Sentinel" wrong; black-hole is Voidmaw's not Commander's; "Boss Fight" menu → Combat Lab. | FIX (rewrite section) |
| `agents/data-author.md` | Partially stale | M | `drone.gd`, `basic_*.gd`, `wave_spec.gd` (→ `wave_def.gd`), `aimed_shot` (→ `aimed_fire.gd`). | FIX |
| `agents/economy-sim.md` | Partially stale | M | `scripts/run_state.gd` (→ `autoload/`); `WaveGeneratorV2.build_combat` doesn't exist. | FIX |
| `agents/game-design.md` | Partially stale | M | "800×1000"; "10 slots" list missing MODULE/SHIFT_MODE; `level_builder.gd`; `scripts/main.gd`. | FIX |
| `agents/capture-scripter.md` | Stale/misleading | M | "Godot 4.3 mono headless"; "320×400 viewport" (really 480×270). Contradicts the /capture skill. | FIX |
| `agents/ux-design.md` | Partially stale | M | "800×1000", "16×16 sprites scaled 3×", "bullets scaled 2.5×", "bars top-left" — all contradict native-scale + gutter-HUD. | FIX |
| `agents/vfx-author.md` | Partially stale | L | `scripts/galaxy_backdrop.gd` path; "50% hull" threshold; "read 2 PNG frames" contradicts standing rule. | FIX |
| `agents/part-author.md` | Partially stale | L | `scripts/player_loadout.gd` (→ `weapons/`); "10-slot" (12 enum, list bay). | FIX |
| `agents/perf-runner.md` | Current | L | Two hot-path globs use `scripts/player.gd` / `wave_director.gd`. | FIX (2 paths) |
| `agents/design-reviewer.md` | Partially stale | L | "4.4.1 vs 4.3 mono" version-split framing (single 4.6.3 now). | FIX |
| `agents/tuner-builder.md` | Partially stale | L | `scripts/dev_menu.gd` (→ `dev/`); button-registration mechanism. | FIX |
| `agents/smoke-runner.md` | Partially stale | L | Project root `F:/Programming/Git/shmup/shmup`; "ignore gl_compatibility shader warnings" (under forward_plus those can be real breaks). | FIX |
| `agents/asset-importer.md` | Current | L | — | KEEP |
| `agents/capture-poster.md` | Current | L | Discord-retired correct. | KEEP |
| `agents/regression-bisect.md` | Current | L | Generic. | KEEP |
| `agents/code-editor.md` | Current | L | 9-line catch-all. | KEEP |
| `skills/add-enemy/SKILL.md` | Contradicts code | **H** | Says extend `scripts/enemy_core.gd` "(top-level, NOT scripts/enemies/)" — **backwards**; it's `scripts/enemies/enemy_core.gd`. | FIX★ (1 path) |
| `skills/capture/SKILL.md` | Current | L | Correct (~480 viewport, Discord-retired, GIF-not-frames). | KEEP |
| `skills/ship/SKILL.md` | Current | L | Reads godot path via parse_check.ps1. | KEEP |
| `skills/add-part/SKILL.md` | Current | L | Correct pointers. | KEEP |

The agent staleness is concentrated in the four oldest navigation/grounding files
(`godot-explorer`, `publish-gate`, `enemy-design`, `boss-composer`). Skills are in good shape
(3/4 fully current; `add-enemy` has one inverted path).

### 3e. Combat / enemies / waves / factions / bosses design docs

| File | Verdict | Risk | Core issue | Action |
|------|---------|------|-----------|--------|
| `enemy_density_research_2026-05-21.md` | Historical OK | L | "2–4 waves/node" (now 5–8 streaming). Reads as research. | ARCHIVE |
| `enemy_speeds_2026-05-24.md` | Historical OK | L | Has "MOSTLY SHIPPED" banner; pre-M6 roster/bullet paths. | ARCHIVE |
| `enemy-pattern-analysis.md` | **Superseded** | **M-H** | **Undated filename**, authoritative tone, describes **pre-M6** enemy model as "Current Architecture." Top citation-bait in the set. | ARCHIVE★ (banner → m6 design) |
| `boss_proposals_2026-05-24.md` | Partially stale | M | Banner *under-claims* ("Spinwright + Conductor not built") — all 7 bosses shipped. Records aliases: **Aegis = `boss_aegis.gd` / scene `boss_sentinel.tscn`**, **Lash = `boss_reaver.gd`**. | ARCHIVE (banner: all shipped + aliases) |
| `combat_construction_plan_2026-06-03.md` | Historical OK | L | Milestone log with ✅DONE markers; pre-reorg paths. | ARCHIVE |
| `combat_lane_wave_bridge_2026-06-03.md` | Partially stale | **M-H** | Brands itself "CANONICAL / THIS WINS" but header says "design / not built" — the system **shipped**. Mandates `row→route` rename that **never happened in code**. | ARCHIVE (banner: built; route rename NOT applied) |
| `lane_system_spec_2026-06-03.md` | Historical OK | L | Self-subordinates to the bridge ("not implemented yet"). | ARCHIVE |
| `wave_streaming_variety_spec_2026-06-03.md` | Historical OK | L | Proposes factions Military/Corporate/Supremacy/**Mercenary** (final: supremacy/privateer/corporate/zealot). Flagged PROPOSED. | ARCHIVE |
| `wave_composition_guide_2026-06-03.md` | Current | L | Evergreen authoring guidance; vocab matches `phrase.gd`. | KEEP (consider promoting) |
| `pattern_pass_2026-06-05.md` | Partially stale | M | Rename map (straight→Diver, etc.) marked ✅ but **files kept old names**; superseded by the 06-08 pattern set. | ARCHIVE (banner → pattern_eligibility) |
| `pattern_eligibility_2026-06-08.md` | Current | L-M | Describes a **built** system (`pattern_eligibility.gd` + editor). "Data model" key list partly retired-inline. | KEEP (light fix) |
| `m6_modular_enemies_design_2026-06-05.md` | Current (plan of record) | M | Header says "design/plot-out" but it's the **as-built** enemy system (CLAUDE-referenced). §12/§13 DRAFT tables superseded by m6b. | KEEP (flip header; point §12/13 → m6b) |
| `m6b_faction_tagging_2026-06-06.md` | Partially stale | M | "Master table (all 25 enemies)" — live `factions.gd` roster has grown past it. | KEEP (banner → factions.gd is source) |
| `wave_pattern_editor_design_2026-06-15.md` | Current | L | Accurate spec for **unbuilt** work; code anchors verified. | KEEP |

### 3f. Economy / parts / progression / meta design docs

| File | Verdict | Risk | Core issue | Action |
|------|---------|------|-----------|--------|
| `progression_3pick_proposal_2026-05-21.md` | Historical OK | L | Banner says ABANDONED (→ Sector Map V3). | ARCHIVE |
| `redundancy_audit_2026-05-21.md` | Historical OK | L | Partially-shipped sweep; outstanding items could fold into TODO. | ARCHIVE |
| `economy_2026-05-24.md` | Partially stale | M | Outpost-as-POI-node density math; single-currency framing; retired upgrade list. Has a 2026-06-08 re-audit banner. | ARCHIVE (strengthen banner) |
| `economy_spec_2026-06-03.md` | **Superseded/misleading** | **H** | Labels two-currency "bounty vs **station-supply**" + **ace kill-chain** as "**LOCKED**." Neither shipped (code: `bounty` + `Materials`, different model; ace-chain exists nowhere). Only the outpost-hub pillar shipped. | ARCHIVE★ (strong reality banner) |
| `vestigial_parts_cleanup_2026-06-03.md` | Current | L | Cleanup verified done (7 scripts gone). | ARCHIVE (keep-as-history) |
| `recycling_system_pillar2_2026-06-04.md` | Historical OK | L | Pillar 2 now **built** (per memory finding). Pre-reorg paths. | ARCHIVE (banner: built) |
| `supers_modes_modules_2026-06-05.md` | Superseded | M | Already has SUPERSEDED banner. "4 passive slots" (really 6-list); roster names drifted (Adrenal Surge → Critical System De-Limiter; Tractor Coil cut). | ARCHIVE (strengthen pointers) |
| `shift_mode_system_2026-06-08.md` | Current | L | Built as described; Phase added a shield-absorb tweak post-spec. | KEEP (1-line note) |
| `passive_module_bay_2026-06-13.md` | Current | L | Built. Internal inconsistency: intro prose says "5 slots", BUILT section + code say **6**. | KEEP (reconcile 5→6) |
| `signal_event_redesign_2026-06-08.md` | Current | L | Built (Phases A+B+C). | KEEP |
| `intercept-signal-events.md` | Historical OK | M | Two intercept events **never built** (status line says so). Reads as a ready-to-ship plan. | KEEP-or-ARCHIVE (clear NOT-BUILT banner) |
| `shield_unification_2026-06-08.md` | Current | L | Built (enemy shields → `ShieldComponent`). Distinct from player Shield Core. | KEEP |
| `run_summary_scope_2026-06-01.md` | Superseded | M | Says "scoped, not built" — **all built** except the victory screen. | ARCHIVE (banner: built; victory path open) |

### 3g. Weapons design docs

| File | Verdict | Risk | Core issue | Action |
|------|---------|------|-----------|--------|
| `weapon_architecture_2026-05-24.md` | Superseded | M | Class tree landed; inventory table (16 weapons, old names) + "stats in script" stale. | ARCHIVE (banner → data-centralization) |
| `weapon_mk_progression_2026-05-25.md` | **Stale/misleading** | **H** | Looks authoritative; every stat literal stale; files Hyper/Phase/Drone-Swarm under `DEVICE_BAY_1` (wrong). | ARCHIVE★ (banner → dps_report 06-13) |
| `bullet_library_2026-05-24.md` | Superseded | M | "DEFERRED" but built (8 indexed scenes + `bullet_catalog`). | ARCHIVE (banner → weapons_system) |
| `weapons_system_2026-06-05.md` | Current | **H** | Live **enemy-weapon** reference; index tables match `bullet_catalog.gd`. | KEEP |
| `weapon_data_centralization_2026-06-11.md` | Current | **H** | Authoritative player-weapon model, CLAUDE-cited; matches code exactly. | KEEP |
| `weapon_dps_report_2026-06-11.md` | Superseded | M | Fully subsumed by the 06-13 report (which says so). | ARCHIVE |
| `weapon_dps_report_2026-06-13.md` | Current | **H** | Live DPS reference (Scatter Blaster, Shredder, Pulse Laser); rebalance marked "NOT applied". | KEEP |
| `swarm_launcher_secondary_2026-06-08.md` | Superseded | M | "Scoped, not built" — **built** (`swarm_launcher.gd` + `swarm_missile.gd`). | ARCHIVE (banner: built) |
| `armory_string_expansion_2026-06-08.md` | Partially stale | M | Part 1 (`armory_strings.gd`) built; "today's reality" inventory stale; Part 2 (codex tab) unverified. | ARCHIVE (banner; verify Part 2) |

### 3h. UI / HUD / sector-map / visual / parallax / renderer + logs

| File | Verdict | Risk | Core issue | Action |
|------|---------|------|-----------|--------|
| `sector_map_hd_scope_2026-06-02.md` | Historical OK | M | Shipped; cites dead `sector_map_hd_lab.tscn` as the reference. | ARCHIVE (banner: port complete) |
| `sector_map_hd_PORT_HANDOFF.md` | **Superseded** | **H** | Reads as a live "do this next" spec; work is done. Tells you to lift code from a deleted lab; one item ("remove Manage Ship modal from `sector_map_v3`") is genuinely still-present dead code. | ARCHIVE★ (banner: DONE) |
| `sectormap_labels.md` | Partially stale | M | Describes native-480 pre-HD model; labels now re-hosted to HD overlay; `row_N_poi_M` markers dead (procedural POIs). | ARCHIVE (or fix HD-overlay note) |
| `ui_color_reference.md` | Current | L | Palette current; source path + line refs drifted (advisory). | KEEP |
| `renderer_audit_2026-06-11.md` | Partially stale | M | `glow_hdr_threshold` cited 0.0/1.0 (code: **1.5**); "bullet glow halos" pulled. | ARCHIVE (or fix threshold) |
| `shader_suite_status_2026-06-11.md` | Historical OK | L | Dated status snapshot; some items moved by later work. | ARCHIVE |
| `godot-patterns.md` | Current | L | Engine gotcha log; HDR-2D/Forward+ traps accurate. | KEEP |
| `godot-learnings-for-new-projects.md` | Current | L | Portable heuristics; one "(esp. web)" aside. | KEEP |
| `controller_support_plan_2026-06-05.md` | Partially stale | M | Thesis sound (no UI focus-nav, **unbuilt**); keys wrong (says Q/R, code G/A); pre-reorg paths. | KEEP (fix keys/paths) |
| `handoff_remaining_2026-06-11.md` | Partially stale | M | Threshold "1.0" (→1.5); weapon_stats.csv regenerated; DPS rebalance dropped. | ARCHIVE |
| `superpowers/.../marker-driven-hud` (plan+spec) | Superseded | M/L | HUD shipped (`hud/ui.gd`). Cody binary path; root `scripts/ui.gd`. | ARCHIVE |
| `superpowers/.../hud-light-patterns` (plan+spec) | Superseded | M/L | `HudLight` shipped. Plan Task 4 = "Post to Discord" (retired). | ARCHIVE |
| `superpowers/.../parallax-v4` (plan+spec) | Superseded | M | `backdrop_coordinator.gd` is live; `galaxy_backdrop.gd` dead. | ARCHIVE (banner → coordinator) |
| `superpowers/.../pause-menu` (plan+spec) | Superseded | M/L | Shipped exactly; "No Quit (web export)" rationale stale. | ARCHIVE |
| `TODO.md` | Partially stale | **H** | Reads as the live punch-list; module-bay/run-summary/sell-UI items done elsewhere, not checked off; sell-rate "20%" (→10%). Lags `Worklist.md`. | FIX (check off done) |
| `Worklog.md` | Historical OK | L | Dated run log. | KEEP |
| `Worklist.md` | Historical OK | L-M | The **most current** tracker (refreshed 2026-06-14); ahead of TODO.md. | KEEP (treat as canonical index) |
| `reports/combat_session_handoff.md` | Historical OK | L | Dated handoff, resolved. | KEEP |
| `reports/lead_session_report.md` | Historical OK | M | Big "Decisions I need" block, mostly resolved. | KEEP (note resolved) |
| `reports/autonomous_worklog.md` | Historical OK | L | Dated log. | KEEP |
| `reports/code_review_findings_2026-06-09.md` | Historical OK | M | Deferred list could read as open bugs; `bullet.gd` relocation since done. | KEEP |

---

## 4. Cross-doc contradictions (worth resolving explicitly)

1. **Renderer/target** — CLAUDE.md + `publish.ps1` + `project.godot` say forward_plus/Windows;
   README, ONBOARDING, contributing/01 & /06 say gl_compatibility/Web. Most pervasive rot.
2. **Publish channel** — live tooling = `tikibones/starblaster:windows`; stale docs =
   `cswendrowski/starblaster:html`. (Matches the known identity split.)
3. **Sector-map scene** — CLAUDE.md/contributing-02 say `sector_map_v3.tscn`; ONBOARDING says
   `sector_map_v2.tscn`; actual route = `sector_map_hd.tscn` (wrapping v3). Three answers, none exact.
4. **Outpost node vs hub** — contributing/02 + `economy_2026-05-24` (node) vs code + `economy_spec`
   (hub). Hub won.
5. **`glow_hdr_threshold`** — docs say 0.0 / 1.0; code = **1.5**.
6. **Keybinds** — docs say Q/E/R; code = **G / A** (CLAUDE.md already warns bindings drift).
7. **Module-bay status** — TODO.md (`[ ]` not started) vs Worklist.md (BUILT) vs autonomous_worklog
   (deferred). Worklist is correct.
8. **Sell-back rate** — TODO.md says 20%; code = 10%.
9. **Two-currency model** — `economy_spec` LOCKS bounty/station-supply; code has bounty/**Materials**
   (a power currency, not survival) + dice-rolled repair/ammo charges. The spec's model never shipped.

---

## 5. Genuine code/doc contradictions (may need a CODE decision, not just a doc edit)

These are the ones where the doc isn't just stale — the code itself is in a half-finished or
alias state. Flagging for your call:

- **`row` → `route` rename** declared "canonical" in `combat_lane_wave_bridge` but **never applied**;
  code still uses `is_row_pois_complete` (`scripts/autoload/run_state.gd`,
  `scripts/screens/sector_map_v3.gd`). Either apply the rename or strike it from the doc.
- **Boss name aliases** — player-facing **Aegis** ships as `boss_aegis.gd` but scene
  `boss_sentinel.tscn`; **Lash** ships as `boss_reaver.gd`. Grep traps; consider renaming files/scenes
  or documenting the aliases prominently.
- **Manage-Ship modal** — the HD `manage_ship` path shipped, but the old in-map modal
  (`_ms_*` / `_show_manage_ship_modal`) is still present in `sector_map_v3.gd` as dead code.
- **Vestigial slots** — `WING_LEFT/RIGHT`, `TAIL`, `SHIELD`, `HARDPOINT_WINGTIP`, `DEVICE_BAY_2`
  are enum entries with no Part. Intentional (save-compat), but worth a one-line code comment so
  they stop reading as "build axes."

---

## 6. Recommended action plan (archiving-first, preserve everything)

Two tracks, because ~half the corpus *can't* be archived (it's loaded/cited live) and the other
half is exactly what archiving is for.

### Track A — Fix the live surfaces in place (can't be archived)
The always-loaded / always-trusted files. Do these first; highest ROI:
- **CLAUDE.md** (tiny), **contributing/01, /02, /04, /06**, **README**, **ONBOARDING**.
- The 4 high-risk agents (**godot-explorer, publish-gate, enemy-design, boss-composer**) + the
  rest of the `.claude/agents` path/version fixes + **add-enemy** skill (1 path).
- The memory status flips (**run-summary-plan, recycling-system-direction, ui-unification,
  combat-redesign-spec**) + MEMORY.md index lines.
- **TODO.md** (check off done items) — or just declare **Worklist.md** the canonical tracker.

Most of these collapse to the 8 axis fixes (find/replace renderer, engine, paths, viewport, slots,
keybinds), so the edit count is smaller than the file count.

### Track B — Archive the historical design docs (your stated preference)
Create **`docs/archive/`** and move every doc marked ARCHIVE above into it, each getting a
one-line banner at the very top so the design is preserved but can't be mistaken for current:

```
> **ARCHIVED 2026-06-15 — historical snapshot. SUPERSEDED BY <doc/code>.**
> Status at the time of writing only; do not cite as current design.
```

For the few that flipped the *other* way (shipped but marked "not built"), the banner reads
`BUILT — see <code/doc>` instead. This keeps git history/blame intact (a move, not a delete) and
nothing is lost.

Candidates that are essentially 100%-subsumed (`weapon_dps_report_2026-06-11`,
`file_reorg_changemap`) still get archived rather than deleted, per your preserve-everything call.

A handful of dated docs are still **current** and should **stay in `docs/`** (not archived):
`weapon_data_centralization`, `weapons_system`, `passive_module_bay`, `shift_mode_system`,
`signal_event_redesign`, `shield_unification`, `wave_pattern_editor_design`, `pattern_eligibility`,
`wave_composition_guide`, `weapon_dps_report_2026-06-13`, `m6_modular_enemies_design` (+ `m6b`),
`godot-patterns`, `godot-learnings`, `ui_color_reference`, `file-structure`, `controller_support_plan`.

### Track C — The guardrail (so this doesn't silently rot again)
1. **Status-header convention**: every doc in `docs/` starts with one line —
   `Status: CURRENT` / `SUPERSEDED → <x>` / `SCOPED, NOT BUILT` / `BUILT <date>`. Cheap, and it's
   the missing signal that caused most mis-citation.
2. **Canonical index**: a short table in `docs/contributing/README.md` (or a new `docs/README.md`)
   listing the live reference doc per system, with everything else pointed at `docs/archive/`.
3. **Pin a memory** ("doc-canon map") recording which docs are canonical vs archived and the 8
   drift axes, so future sessions stop citing the dead designs — this directly addresses the
   recurring "I cited a badly out-of-date design" problem.

### Suggested phasing
- **Phase 1 (highest ROI, ~½ day):** Track A's HIGH-risk files (the 8 axis fixes) + create
  `docs/archive/` and move the ★ARCHIVE docs (`economy_spec`, `weapon_mk_progression`,
  `enemy-pattern-analysis`, `sector_map_hd_PORT_HANDOFF`).
- **Phase 2:** Remaining Track A (medium/low agents, memory flips) + the rest of Track B archiving.
- **Phase 3:** Track C convention + index + memory pin, and surface §5 to decide the code-level items.

---

## 7. Counts

- Audited: ~90 files (10 canonical surfaces, 17 memory, 3 file-structure/reorg, 23 agents+skills,
  ~50 design/log docs).
- **KEEP (current):** ~30 · **FIX in place (live surface):** ~28 · **ARCHIVE (historical):** ~30.
- HIGH citation-risk files needing attention first: ~14 (the ★ rows above).

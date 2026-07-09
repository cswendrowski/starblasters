# Dev Tool Unification Design (2026-07-07)

> One-line: Dev tools drift because each keeps a private copy of an option table (movement keys, payload names, bullet inventory) instead of enumerating the live production source; the fix is a small shared `DevData` enumeration layer + a default-vs-override display convention, phased so paths→eligibility/formation and bullets→bench/hangar land first. This is a DESIGN doc — no code was changed.

Audience: agents. Read the matrix (§1) first; it is the deliverable. All claims carry `file:line` citations verified against the tree at time of writing.

---

## 0. Problem statement (Roman)

> "There are many dev menus that let me tune/author things, but they don't talk to each other, pick up changes, or let me see the live game settings (default vs my adjustments). I authored new paths, they don't appear in the eligibility/formation tools. I edit bullets, those changes don't appear in the hangar/enemy bench. Unify these benches so they work together, especially if it reduces the places info is stored in favor of centralized sources of truth."

Three concrete symptoms, all confirmed below:
- **(a)** Authored paths (`authored_path_library.gd`) don't appear in the eligibility/formation tools.
- **(b)** Bullet edits (weapon lab / `data/bullets/*.tres`) don't fully appear in hangar/enemy bench.
- **(c)** Tuner-saved values vs baked production defaults are indistinguishable in tool UIs.

---

## 1. Data-store inventory & staleness matrix (CORE DELIVERABLE)

### 1.1 The three persistence patterns in this codebase

Every tool falls into one of three patterns. The pattern determines how it drifts.

| Pattern | Persist target | Production reads it? | Drift risk |
|---|---|---|---|
| **P-BAKE** — baked const + "Copy GDScript" | `user://tuners/<name>.json` (scratch) → human pastes a `const DATA` into a `.gd` | Reads the committed const only; **never** `user://` (contract) | Option TABLES that feed the tool go stale; the *authored data* is fine once pasted |
| **P-OVERRIDE** — live `user://` override | `user://tuners/<name>.json` | **Yes**, at runtime in DEBUG builds (release ignores it) | Low for the value itself; two tools can hold *different* pending saves |
| **P-TRES** — direct `.tres` edit | `data/…/*.tres` via `ResourceSaver` | Yes (everything `preload`s the same `.tres`) | New `.tres` files invisible to tools whose name→path table is hardcoded |

P-OVERRIDE is the healthiest (production and tool share one file). The pain is concentrated in **P-BAKE tools whose private option tables are hand-maintained copies of a production enumeration**.

### 1.2 Per-tool inventory

Enumerated from `scripts/dev/dev_menu.gd:88-123`. "LIVE?" = does the tool enumerate the current production source, or hold a stale private copy?

| Tool (`scripts/dev/…`) | Authors / tunes | Persists to | Production source of truth | LIVE? |
|---|---|---|---|---|
| `path_editor.gd` | Authored flight paths | `user://tuners/enemy_paths.json` (P-BAKE + P-OVERRIDE) | `authored_path_library.gd` `DATA` const (`:40`) + `OVERRIDE_PATH` live read (`:32`, `:182`) | **YES** — dogfoods `AuthoredPath` runtime |
| `pattern_eligibility_editor.gd` | Per-enemy movement identity + eligible set | `user://tuners/pattern_eligibility.json` (P-BAKE) | `scripts/levels/pattern_eligibility.gd` `DATA` (`:27`) | **NO** — hardcoded `MOVEMENT_KEYS` (`:27-40`), **no `path_*` keys** |
| `wave_pattern_editor.gd` (Formation Builder) | Formation-burst wave patterns | `user://tuners/wave_patterns.json` (P-BAKE) | `scripts/levels/authored_patterns.gd` `DATA` (`:16`) | **NO** — pulls movement list from the editor above (`:21`, `:97`), inherits its staleness |
| `enemy_bench.gd` | Per-enemy weapon/mounts/size/loco/traits/paths | `user://tuners/<enemy>.json` roster dicts (P-BAKE) | `scripts/levels/enemy_roster.gd` roster dicts | **PARTIAL** — paths read live (`:237-238`), but `PAYLOADS` (`:49-53`) + `PROJECTILES`/`EMITTER_PAYLOADS` (`:89-128`) hardcoded |
| `weapon_lab.gd` | Player weapon stats; enemy weapons; **bullet `.tres`** | `user://tuners/player_weapons.json` (`:110`); bullet tab writes `.tres` (P-TRES, `:986`) | Weapon `.tres`; enemy `PAYLOADS` via `EnemyRoster.BV_*` (`:51-57`) | **PARTIAL** — bullet tab scans `data/bullets/` dir live (`:859-864`); but enemy PAYLOADS uses **old** `BV_*` labels |
| `recycle_tuner.gd` | Recycle depth/chance | `user://tuners/recycle.json` (P-OVERRIDE) | `recycle_controller.gd` reads same file (`:23`) | **YES** |
| `parallax_tuner.gd` | Planet glow | `user://tuners/planet_glow.json` (P-OVERRIDE) | `planet_glow_config.gd` reads same file (`:33`) | **YES** |
| `shader_lab.gd` | Shader knobs, damage/burn/nebula/death | `user://tuners/shader_lab.json` (P-BAKE) | Live shader materials + effect scripts | Mixed (per-mode) |
| `nebula_lab.gd` | Nebula placement/colour | `user://tuners/nebula_lab.json` (P-BAKE) | Backdrop layer scripts | P-BAKE |
| `combat_lab.gd` | Encounter/ship config (test launcher) | `user://tuners/combat_lab.json` | `Run` meta; builds real loadout | n/a (launcher) |
| `director_lab.gd` / `battleship_lab.gd` | Boss maneuver knobs | `user://tuners/director.json` / `battleship.json` | Boss scripts | P-BAKE-ish |
| `smart_mount_lab.gd` | Turret knobs | `user://tuners/smart_mount_lab.json` | Mount/turret runtime | P-BAKE |
| `lane_visualizer.gd` | Pattern notes (annotation) | `user://tuners/pattern_notes.json` | none (notes only) | n/a |
| `hangar.gd` | Player loadout preview (test bench) | none | `PartCatalog` / weapon `.tres` (`:32`) | reads live `.tres` |
| asteroid_* / music_lab / player_fx_lab / loading_screen_lab / outpost_arrival_lab / sequence_lab / combat_vfx_lab | VFX/scene tuning | mostly P-BAKE or none | effect scripts | scoped, not implicated |

### 1.3 Worst offenders (the staleness the ticket is about)

**OFFENDER 1 — paths invisible to eligibility/formation (symptom a).**
- Production resolves `path_<name>` movement keys: `enemy_roster.gd:1639-1640` calls `AuthoredPathLibrary.is_path_key()/resolve_key()`.
- A live enumeration API **already exists**: `authored_path_library.gd:193 names()` and `:203 movement_keys()`, which merge baked `DATA` + live `user://` overrides.
- `enemy_bench.gd:237-238` correctly consumes it: *"Read live from the library (never cached) so a newly authored path shows up immediately."*
- BUT `pattern_eligibility_editor.gd:27 MOVEMENT_KEYS` is a hand-maintained list with **zero `path_*` entries** and never calls `AuthoredPathLibrary.movement_keys()` (grep for `path`/`AuthoredPath` in that file: only unrelated `_home_from_path`). So authored paths cannot be marked eligible there.
- `wave_pattern_editor.gd:21,97` imports that same `MOVEMENT_KEYS` — so the Formation Builder inherits the identical blind spot. **One stale table poisons two tools.**

**OFFENDER 2 — two divergent payload label tables (symptom b).**
- The bullet inventory is mid-migration to 5 frame-reskin families: `enemy_bench.gd:49-53 PAYLOADS` = `Ball/Bolt/Laser/Wave/Orb` → `data/bullets/{ball,bolt,laser,wave,orb}.tres`.
- `weapon_lab.gd:51-57 PAYLOADS` still exposes the **old** names `Basic/Spread Pellet/Aimed Sniper/Burst Round/Plasma Orb/Heavy Slug/Drop Pellet` via `EnemyRoster.BV_*`.
- Those `BV_*` consts are now **aliases** collapsing onto the same 5 files: `enemy_roster.gd:108-114` (`BV_Basic`, `BV_SpreadPellet`, `BV_BurstRound` all → `ball.tres`; `BV_AimedSniper`, `BV_HeavySlug` → `bolt.tres`; `BV_PlasmaOrb` → `wave.tres`).
- Net: **two tools present two different vocabularies for the same 5 physical bullets.** Bullet *stat* edits DO propagate (both preload the same `.tres`; weapon_lab writes them via `ResourceSaver`, `:986`), but a NEWLY added `.tres` appears in weapon_lab's dir-scan (`:859-864`) and NOT in enemy_bench's hardcoded `PAYLOADS`, and the label sets never reconcile.

**OFFENDER 3 — no default-vs-override display anywhere (symptom c).**
- P-BAKE tools load `user://tuners/*.json` into working state (e.g. `path_editor.gd:125 _load_library`, `pattern_eligibility_editor.gd:21 SAVE_PATH`) but the UI shows a **single merged value**. There is no widget convention that renders "baked production default = X / your pending tune = Y." Roman cannot tell, in any tool, whether a shown number is shipping or an un-pasted edit. (Confirmed: no shared "default vs override" widget exists — grep for `default.*override` / `baseline` across `scripts/dev/` returns nothing structural.)

### 1.4 The good pattern to generalize

Two exemplars already in-tree; the design generalizes both:

1. **`AuthoredPathLibrary` enumeration API** (`:193 names()`, `:203 movement_keys()`, `:181 _def_for()`): baked `DATA` + live `user://` override, deduped, with a `reload_overrides()` (`:175`) the editor calls after Save. This is exactly the "one live source, many consumers" shape — it just needs *more consumers*.

2. **`MOUNT_FIELDS` schema table** (`enemy_bench.gd:1155-1179`): ONE field-schema list drives serialize / copy-emit / roster→bench parse, *replacing four hand-synced copies that "drifted out of step and silently corrupted enemies on each roster→bench→Copy pass"* (`:1141-1142`). This is the pattern for lossless round-trip through a schema instead of parallel code. Generalize its shape to the bullet/payload and movement-key tables.

---

## 2. Root-cause patterns

Classified, with the file:line proof already cited above.

- **RC1 — Duplicated option tables (snapshot copies).** A tool hardcodes a `const` list that is a stale copy of a production enumeration. `pattern_eligibility_editor.gd:27 MOVEMENT_KEYS`, `enemy_bench.gd:49 PAYLOADS`, `weapon_lab.gd:51 PAYLOADS`. Fix: enumerate the live source.
- **RC2 — Transitive staleness.** One tool imports another's stale table, doubling the blast radius. `wave_pattern_editor.gd:21` imports `pattern_eligibility_editor.MOVEMENT_KEYS`.
- **RC3 — Divergent vocabularies for one asset.** Same 5 `.tres`, two label sets (old `BV_*` names vs new family names) that never reconcile (`enemy_roster.gd:108-114` aliasing).
- **RC4 — No default-vs-override display.** P-BAKE tools merge baked + pending into one value; no UI distinguishes them (§1.3 Offender 3).
- **RC5 — Mixed persistence contracts across sibling tools.** Some tools are P-OVERRIDE (production reads `user://`: `recycle_controller.gd:23`, `planet_glow_config.gd:33`), some are P-BAKE (production never reads `user://`: `pattern_eligibility.gd:13`), and one is P-TRES (`weapon_lab.gd:986`). This is *intentional and fine* per the tuner contract — but it means a tool can't assume a sibling's saves are live, so cross-tool "see each other's pending tunes" must be explicit, not assumed.

---

## 3. Unification design (incremental, low-risk)

Respects the tuner contract: **tools persist to `user://tuners/<name>.json`; every tuner keeps its "Copy GDScript"; the human pastes into production. No tool writes a production `.gd`/`.tres` it shouldn't.** (weapon_lab's `.tres` write stays — that's an established, accepted P-TRES exception, `:986`.)

### 3.1 Shared piece A — `DevData` enumeration registry

New file `scripts/dev/dev_data.gd` (`extends Object`, preload-referenced, headless-safe, mirroring `factions.gd`). A thin FACADE that returns the *live* production vocabulary so no tool hardcodes it:

- `movement_keys() -> Array` — shape keys (from a single canonical const, see §3.4) **+** `AuthoredPathLibrary.movement_keys()`. Solves Offender 1.
- `bullet_variants() -> Array[{name, path, variant}]` — scans `data/bullets/*.tres` (as `weapon_lab.gd:859` already does) and returns a uniform `{name, path}` list. Solves Offender 2's "new .tres invisible" half.
- `enemy_scenes()`, `projectile_scenes()`, `emitter_payloads()` — fold in `EnemyManifest` + the `PROJECTILES`/`EMITTER_PAYLOADS` tables so those become one enumeration.
- `eligibility_for(scene)`, `paths()` — passthroughs to production.

`DevData` reads; it never writes. Tools call it in `_ready()` instead of iterating a private `const`.

### 3.2 Shared piece B — default-vs-override widget convention

A tiny helper (e.g. `scripts/dev/dev_field.gd` or a convention on existing spin rows) that a tool feeds `(baked_default, current_value)`:
- Renders the control, and when `current != baked_default` shows a muted "was: <default>" affordance + a per-field "revert" affordance.
- "Baked default" = the value from the committed production const / `.tres` (NOT the `user://` save). Tools already have both in hand at load (they load `user://` over a base). Solves Offender 3 (symptom c).
- Non-invasive: opt-in per field; no tool is forced to adopt it at once.

### 3.3 Shared piece C — cross-tool pending-tune visibility (narrow)

Only where it reduces real pain, and only READ-side:
- `DevData.pending_paths()` / `pending_eligibility()` surface another tool's `user://tuners/*.json` so, e.g., the Formation Builder can show "3 paths pending in Path Editor (unpasted)." No tool writes another's file. This is a passive banner, not a data merge — respects RC5.

### 3.4 Single canonical movement-key list

Today the shape-key list lives in `pattern_eligibility_editor.gd:27`. Move the canonical const to a production-adjacent home (e.g. `pattern_eligibility.gd` or a small `movement_keys.gd`) so `DevData.movement_keys()` composes `canonical shapes + live paths`, and BOTH the eligibility editor and Formation Builder consume `DevData` — deleting the transitive import (RC2).

---

## 4. Phased plan

### Phase 1 — Paths → eligibility/formation (symptom a). HIGHEST PAIN, smallest blast radius.
- Add `DevData.movement_keys()` = canonical shapes + `AuthoredPathLibrary.movement_keys()`.
- `pattern_eligibility_editor.gd`: replace the `MOVEMENT_KEYS` iteration with `DevData.movement_keys()`; keep `KEY_REMAP` (`:47`) for legacy-save load. Authored paths now appear as eligible toggles.
- `wave_pattern_editor.gd:97`: consume `DevData.movement_keys()` instead of `MovementKeys.MOVEMENT_KEYS`.
- **Deletes:** the hardcoded, path-blind copy at `pattern_eligibility_editor.gd:27` (shapes move to canonical home) and the transitive import at `wave_pattern_editor.gd:21`.
- **Blast radius:** 2 dev tools + 1 new file. No production/runtime behavior changes (production already resolves `path_*` via `enemy_roster.gd:1639`). Verify via the existing eligibility Export round-trip.

### Phase 2 — Bullets → bench/hangar/weapon-lab (symptom b).
- `DevData.bullet_variants()` scans `data/bullets/*.tres` (one live list).
- `enemy_bench.gd:49 PAYLOADS` and `weapon_lab.gd:51 PAYLOADS` both consume it → **one vocabulary**. Reconcile on the new family names (`Ball/Bolt/Laser/Wave/Orb`), keeping a name-remap for old saved tuner files (mirrors the `MOUNT_FIELDS`/`KEY_REMAP` migration convention).
- **Deletes:** the divergent `PAYLOADS` literal in one of the two tools; the old `BV_*`-label table in weapon_lab collapses to the family list. `EnemyRoster.BV_*` aliases (`:108-114`) can be pruned once no tool references the old names (a later cleanup — note the migration is *in flight*, do not force-complete it here).
- **Blast radius:** 2 dev tools + `DevData`. Bullet *stats* already propagate via shared `.tres`; this only unifies the *inventory list*. Verify with weapon_lab bullet-tab save → enemy_bench payload dropdown shows the same set.

### Phase 3 — Default-vs-override widget (symptom c).
- Land shared piece B; adopt first in `pattern_eligibility_editor`, `enemy_bench` (size/loco/stat knobs), and `weapon_lab` (player stats), where "is this shipping or my edit?" bites most.
- **Blast radius:** additive UI only; per-field opt-in; zero data-model change.

### Phase 4 (optional) — cross-tool pending banners (§3.3) + canonical-list cleanup.
- Lowest priority; passive read-only banners. Prune dead `BV_*` aliases once the bullet migration settles.

---

## 5. Non-goals (stays as-is, and why)

- **The tuner contract itself.** Tools keep persisting to `user://tuners/*.json` + "Copy GDScript"; the human stays in the loop between tool and production. We are NOT making tools write production `.gd` files. (`pattern_eligibility.gd:13` "production never reads user://" stays true for P-BAKE tools.)
- **P-OVERRIDE tools** (recycle, planet_glow, vfx_glow, path override): already unified (production and tool share the file). No change.
- **weapon_lab's direct `.tres` write** (`:986`): an accepted, working P-TRES exception for bullet stats; keep it.
- **VFX/scene tuners** (shader/nebula/parallax/asteroid/music/player_fx/loading/outpost/sequence/combat_vfx labs): scoped to their own assets, not implicated in the drift the ticket describes. Leave them.
- **Test launchers** (combat_lab, battleship_lab, director_lab, hangar): they build real production state already; not data-store owners.
- **Completing the bullet migration.** It's in flight (`enemy_roster.gd:108` aliases + two payload label sets). Phase 2 unifies the tool VIEW of it; it does not force the underlying `.tres`/roster migration to finish — that's Roman's separate in-progress work.
- **Merging the tools into one mega-tool.** Out of scope and risky; the goal is shared DATA plumbing, not shared UI.

---

## 6. Summary for the maintainer

The drift is not "many tools" — it's **a handful of hardcoded option tables that are stale copies of live production enumerations**, plus the absence of any default-vs-override display.

Worst offenders:
1. `pattern_eligibility_editor.gd:27 MOVEMENT_KEYS` has no `path_*` keys and never calls the existing `AuthoredPathLibrary.movement_keys()` (`:203`) — and `wave_pattern_editor.gd:21` imports it, so authored paths are invisible in BOTH the eligibility and formation tools. `enemy_bench.gd:237` already does this right; copy that.
2. `enemy_bench.gd:49 PAYLOADS` (new `Ball/Bolt/…` names) and `weapon_lab.gd:51 PAYLOADS` (old `BV_*` names) describe the SAME 5 `.tres` with two divergent vocabularies (`enemy_roster.gd:108-114` aliasing); a new `.tres` only shows in weapon_lab's dir-scan.
3. No tool anywhere shows baked-default vs pending-tune, so a shown value could be shipping or an un-pasted edit.

Recommendation: a small read-only `DevData` facade (generalizing the `AuthoredPathLibrary` enumeration + `MOUNT_FIELDS` schema patterns already in-tree) + a default-vs-override widget, rolled out in 3 phases — **Phase 1 (paths→eligibility/formation) first** (2 tools, no runtime change, deletes the stale `MOVEMENT_KEYS` copy), then **Phase 2 (bullet inventory)**, then **Phase 3 (default-vs-override UI)**. Non-goals: the tuner contract, the working P-OVERRIDE/P-TRES tools, and finishing the separate in-flight bullet migration.

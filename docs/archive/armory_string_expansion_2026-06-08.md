**✅ ARCHIVED 2026-06-15 — this shipped; historical design doc.** Current behavior: Part 1 built: scripts/strings/armory_strings.gd.
Do not cite as a to-do.
> Part 2 (Armory codex tab) status unverified.

# Armory Tab + Item String Expansion — Scoping

**Date:** 2026-06-08
**Status:** Scoped, not built.

## Goal
Two linked deliverables:
1. **Centralized display + codex strings** for every player item — primary cannons, secondaries,
   the super, the Shift modes, and (when built) passive modules. Today each part hardcodes its
   `display_name`/`description` inline in `_init()`; nothing is sourced from a strings file.
2. A new **Armory** codex tab (mirroring the enemy codex) where these items are shown with a
   slow-rotating sprite + dropshadow + glowmap, the display name, and the codex blurb — pulled from
   the game, authoring nothing of its own.

## Today's reality (from the codebase)
- **Every part sets `display_name` + `description` literally in its own `_init()`** — zero come from
  `strings.gd`/`codex_strings.gd`. Full set: 7 cannons, 7 secondaries, 1 super (Smart Bomb), 3 modes
  (Focus/Phase/Hyper), 2 engines (`scripts/parts/*.gd`). The `@export`s are on `part.gd:6-7`.
- **`.tres` gotcha:** `.tres`-loaded weapons skip `_init`, so `PartCatalog._build_weapon`
  (`part_catalog.gd:176-183`) + `PartFactory._load_or_default` (`part_factory.gd:54-57`) re-copy
  name/description from a fresh `script.new()`. Any string-centralization must account for this.
- **Roster enumeration:** `PartCatalog._all_pool()` (`part_catalog.gd:40-73`) + `_make_by_name`
  (`:106-155`). **Focus is NOT in `_all_pool`** (default-only) — the Armory must add it explicitly.
- **The codex** (`scripts/enemy_codex.gd` + `scenes/enemy_codex.tscn`) is fully procedural: a left
  nav `VBox` of categories (`_cats`, `:49-54`) + a right content panel rebuilt per nav
  (`_render_right`, `:192`). The rotating-sprite entry is `_add_preview(scene_path, hull, glow, frame)`
  (`:290-327`) — instantiates a scene WITHOUT adding to tree, grabs its `Sprite2D` + glow, clones into
  a spinning holder. The **Starblaster entry already previews `player.tscn`'s `Ship` node** (`:266`),
  proving the player-side preview path.
- **Strings convention:** `codex_strings.gd` / `enemy_strings.gd` are `extends Object`,
  **preload-referenced NOT `class_name`** (headless class-cache safety), with `const` dicts +
  `static` lookup helpers + safe fallbacks. `enemy_strings.gd` is keyed by **scene path**.

## Part 1 — String centralization
New file **`scripts/armory_strings.gd`** (mirror `codex_strings.gd`: `extends Object`, preload-not-
class_name). A `const ITEMS := {}` keyed by **part factory-name** (e.g. `"_make_seeking_missile"`)
→ `{ "name": String, "codex": String, "icon_scene": String (optional) }`, plus
`static func item_name(factory)` / `item_codex(factory)` / `item_icon(factory)` with derived
fallbacks (factory→Title Case, like `enemy_strings`).

Author entries for the full constructible roster = `_all_pool()` ∪ `_make_focus_mode`: 7 cannons +
7 secondaries + Smart Bomb + Focus/Phase/Hyper + 2 engines (≈20 entries; the future passive modules
slot in here too).

**OPEN DECISION — strings-authoritative vs. mirror:**
- (a) **Mirror (cheaper, recommended first pass):** keep the inline `display_name`/`description` in
  each part's `_init` (they're load-bearing for the `.tres` copy-back + the shop/HUD); `armory_strings`
  holds the *codex blurb* (net-new) + a display name that should MATCH the part's. The Armory reads
  `armory_strings`; gameplay reads the part. Slight duplication of the display name.
- (b) **Authoritative (bigger):** reroute each part's `_init` to read `ArmoryStrings.item_name(factory)`
  + the copy-back blocks (`part_catalog.gd:176-183`, `part_factory.gd:54-57`) too, so the strings file
  is the single source. Cleaner long-term; touches every part + both copy-back sites.

Recommend (a) for the first pass (the codex blurbs are the genuinely-missing content), with (b) as a
follow-up if the duplication bites.

## Part 2 — The Armory tab
Smallest surface = **same screen, new top-level category** (don't fork a new scene):
- Add an `{"kind":"armory"}` category (or one per item-class: Primary / Secondary / Super / Mode /
  Module) to `enemy_codex.gd:49-54` `_cats`.
- Add an armory branch to `_render_right` (`:192-204`) + clones of `_render_category_list` /
  `_render_enemy_detail` (`:207-263`) that iterate the part roster instead of enemies.
- **Reuse `_add_preview` as-is** for items with a sprite; pass the projectile scene path.

**Sprite-per-item-type (the art gap):**
- **Cannons + bullet-secondaries** → preview the **projectile sprite** (the `bullet_scene` const in
  `part_catalog.gd:27-36`) — `_add_preview` grabs its first `Sprite2D` for free.
- **Particle Beam / Drone Swarm** → no bullet scene; drones can preview `player_drone.tscn`, the beam
  has no projectile sprite.
- **Modes / Super** → no projectile sprite at all. **These need an explicit `icon_scene` (or icon
  texture) in `armory_strings`** — a small placeholder until art lands.

**Discovered-state:** the enemy codex gates on `Run.encountered_enemies`. The Armory could show all
owned/seen items, or everything (simpler). OPEN: gate on owned/seen vs. show-all.

## Build surface
- **New** `scripts/armory_strings.gd` (~20 entries + helpers).
- `scripts/enemy_codex.gd:49-54` (categories), `:192-204` (dispatch), `:207-263` (part-list +
  detail render), `:290-327` (`_add_preview` reuse + icon path for modes/super/beam).
- `scripts/parts/part_catalog.gd:40-73,106-155` — the enumeration the Armory iterates.
- (Option b only) each `scripts/parts/*.gd` `_init` + the copy-back blocks.
- (Optional) `scripts/main_menu.gd:221-234` only if a separate Armory button/scene is chosen.

## Open decisions
1. Strings **authoritative vs. mirror** (Part 1) — recommend mirror first.
2. **Icon art** for modes/super/beam (no projectile sprite) — placeholder vs. commission.
3. Armory category granularity — one "Armory" tab vs. per-slot tabs (Primary/Secondary/Super/Mode/Module).
4. Show **all** items vs. **owned/discovered** only.

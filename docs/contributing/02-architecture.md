# 02 · Architecture

This is the mental model. You don't need to understand every system in detail—just enough to know where things go and why moving code from one place to another matters.

---

## The Playfield Coordinate Space

The game renders at an internal **480×270** and displays at 4× (1920×1080). That gives you one pixel per screen pixel at the default zoom. But *gameplay* doesn't use the full 480-wide viewport. It lives in a **216-wide band** running down the middle:

```
X:   0 .... 132          348 .... 480
     └──────┘ └─────────┬────────┘ └──────┘
     Left     Playfield  Playfield  Right
     gutter   band       band       gutter
     (HUD)    (gameplay) (reserved) (HUD)
```

The band is **X 132–348**, centered at **X 240, Y 135**. The side gutters (0–132 and 348–480) are reserved for the HUD and glass panels.

**Why?** The original game was 320×400 with an 0.8:1 aspect ratio. When resizing to 480×270, we kept that aspect by confining gameplay to 216×270. This way:

1. Waves/patterns authored against the original bounds still work without rewriting logic.
2. The widescreen format gets HUD panels on the sides instead of stretching the playfield.

**Rule: use `Playfield`, NOT `get_viewport_rect()`.**

The `Playfield` class (`scripts/systems/playfield.gd:1-30`) exports these constants:

| Member | Value | Use |
|--------|-------|-----|
| `Playfield.W` | 216.0 | Playfield width |
| `Playfield.H` | 270.0 | Playfield height |
| `Playfield.X_MIN` | 132.0 | Left playfield edge |
| `Playfield.X_MAX` | 348.0 | Right playfield edge |
| `Playfield.Y_MIN` | 0.0 | Top edge |
| `Playfield.Y_MAX` | 270.0 | Bottom edge |
| `Playfield.CENTER` | (240, 135) | Playfield center |
| `Playfield.clamp_pos(p, inset)` | — | Clamp a position to the band (with optional padding) |

**Every script that spawns, moves, or bounds a game object must import `scripts/systems/playfield.gd` and use these constants.** `get_viewport_rect()` returns the full 480 width and will let enemies and the player drift into the HUD gutters—a visual nightmare.

Example: clamping the player's position each frame.

```gdscript
var clamped_pos = Playfield.clamp_pos(new_position)
```

---

## The CanvasLayer Frame

Godot renders in layers. On top of the 2D world, a **CanvasLayer** bypasses normal transform hierarchy and renders in viewport space—perfect for UI that needs to stay still while the camera moves.

Starblaster uses three CanvasLayers:

| Layer | Z-depth | Contents | Purpose |
|-------|---------|----------|---------|
| **Glass** | 1 | Side gutter panels, borders | Surrounds the gameplay area |
| **HUD** | 5 | Score, health bars, wave info | On top of gameplay, stays visible |
| **Outline** | 10 | Left/right viewport borders | Drawn last, topmost |

**Note on backdrop/parallax:** The backdrop is a parallax stack (stars, nebula, planets, etc.) that must render *below* the UI. All backdrop CanvasLayers use **negative Z-depths** (−10 through −1) to stay under the menus and HUD. This is a Godot quirk: see `docs/godot-patterns.md` → "Backdrop CanvasLayers must be negative to stay below UI" for the gotcha.

---

## Autoloads (Global State)

An **autoload** is a script that Godot instantiates once and keeps alive for the entire game session, available as `/root/ScriptName` (or just `ScriptName` from anywhere). They're the mechanism for state that must survive scene changes.

In this project, four autoloads are registered in `project.godot:26–31`:

### `Run` (`scripts/autoload/run_state.gd`)

The run-wide **state machine**. Anything that persists across scenes (combat → sector map → outpost → combat) lives here.

**Owns:**
- **Bounty** — in-game currency. Earned from killing enemies/hazards, spent at shops.
- **Hull/shield** — ship durability. Hull = health; shield = charge pool (one charge per hit, then hull damage). Both persist between scenes (combat → map → outpost → combat).
- **Loadout snapshot** — the set of Parts (upgrades) currently equipped. Read by combat on entry, written by shops/outposts on exit.
- **Sector progress** — current node ID and type (combat/hazard/boss/shop), sector modifiers (difficulty tags), current hazard subtype.
- **Inventory** — uninstalled Parts the player is carrying (cargo hold).
- **Run seed** — pseudo-random seed for reproducible waves.
- **Sector map cache** — the current sector's graph (3 rows of POI nodes + a boss each), used to draw the map and navigate between nodes.
- **One-shot config** — via `Run.set_meta(key, value)`, for test launchers and dev tools to override defaults (e.g., `forced_boss_scene`).

**Key methods:**
- `Run.new_run()` — reset everything for a fresh run.
- `Run.bounty`, `Run.current_hull`, `Run.max_hull`, `Run.current_shield`, `Run.max_shield` — game stat properties (some emit signals on change).
- `Run.loadout_snapshot` — dict of `SlotType (int) -> Part (Resource)`.

When combat ends, `main.gd` writes the player's surviving hull and shield back to `Run` so they carry into the next node. When the player clicks a node on the map, `sector_map_v3.gd` writes the node type/ID to `Run` before calling the next scene.

### `Dbg` (`scripts/autoload/dbg.gd`)

Debug helpers and dev-time shortcuts. Not relevant to shipped gameplay logic.

### `Music` (`scripts/autoload/music_manager.gd`)

Context-aware background music. Has a `set_context(string)` method to switch between "menu", "combat", "boss", "sector". Plays the appropriate track and cross-fades between contexts.

### `Settings` (`scripts/autoload/settings.gd`)

Persisted user preferences (audio levels, input rebinds, etc.). Loads from and saves to the user's local store on startup/shutdown.

---

## Scene Flow

Here's how a run progresses through scenes:

```
main_menu.tscn
    ↓  (Play)
main.tscn (combat) ←──────────────────────┐
    ↓  (level_cleared signal)            │
cleared_summary.tscn (results screen)    │
    ↓  (auto-transition)                 │
sector_map_hd.tscn (wraps sector_map_v3) │
    ├─ Player clicks Combat node         │
    │   → sector_map writes Run.current_node_id/type
    │   → calls get_tree().change_scene("res://scenes/main.tscn")
    │   → goes back to main.tscn ────────┘
    │
    ├─ Player clicks Outpost (persistent hub button, always available)
    │   → opens outpost.tscn
    │   → buys/sells/refills Parts + Modules
    │   → returns to sector_map_hd.tscn (does NOT advance progress)
    │
    ├─ Player clicks Hazard node (minefield/asteroid field)
    │   → opens main.tscn in hazard mode
    │   → returns to sector_map_hd.tscn
    │
    ├─ Player clicks Boss node
    │   → opens main.tscn in boss mode
    │   → boss dies → returns to sector_map_hd.tscn
    │
    ├─ Player clicks Signal Event node
    │   → opens signal_event.tscn (narrative choice)
    │   → choice outcome modifies Run state
    │   → returns to sector_map_hd.tscn
    │
    ├─ Patrol complete (all 3 rows' POIs cleared + all 3 row bosses dead)
    │   → cleared_summary.tscn flags victory ("PATROL COMPLETE")
    │   → run_summary.tscn (final score, stats) → main_menu.tscn
    │
    └─ Run ends (player dies)
        → run_summary.tscn (final score, stats)
        → return to main_menu.tscn
```

**Run shape:** a run is **one sector of 3 rows**; each row is a string of POIs (combat / hazard /
signal) ending in a **boss** at the right edge — so a run has **3 bosses**, one per row, drawn at
random from the boss pool. Clearing all three rows (POIs + boss) completes the patrol = victory.
(`run_state.gd` still carries multi-sector scaffolding — `TOTAL_SECTORS`, per-sector boss pools,
sector advancement — left over from an earlier 3-sector design; a run is one sector.)

**Key pattern:** Scenes read/write `Run` to pass state. The sector map doesn't *own* the run; it's a navigator that reads the current node, writes the next destination, and calls `get_tree().change_scene()`.

---

## Run Lifecycle & State Threading

When a run starts:

1. **main_menu.tscn** is loaded. Player presses "Play".
2. **main_menu.gd** calls `Run.new_run()`, which:
   - Zeros bounty, hull, shield.
   - Clears loadout and inventory.
   - Generates a new `sector_map_cache` (one sector: 3 rows, each a line of POIs ending in a boss).
   - Sets `current_node_id` to the root node (always a combat arena).
3. **main_menu.gd** transitions to `sector_map_v3.tscn`.
4. **sector_map_v3.gd** reads `Run.current_node_id` in `_ready()`, draws the map, and highlights the starting node.

When the player clicks a node:

5. **sector_map_v3.gd** writes `Run.current_node_id`, `Run.current_node_type`, and `Run.sector_modifiers`.
6. **sector_map_v3.gd** calls `SceneTransition.change_scene(...)` with the destination scene path.
7. The destination scene (e.g., `main.tscn`) reads `Run.current_node_id` and `Run.loadout_snapshot` in `_ready()` to set up gameplay.

When combat ends:

8. **main.gd** (on `level_cleared` signal) writes the player's surviving hull/shield back to `Run`.
9. **main.gd** transitions to `cleared_summary.tscn`.
10. **cleared_summary.gd** displays results and auto-transitions back to `sector_map_v3.tscn` after a few seconds.

The loop repeats until the run ends — player death, or all 3 rows cleared (POIs + bosses) = victory — at which point the flow transitions to `run_summary.tscn` and back to `main_menu.tscn`.

---

## Summary

**Three big takeaways:**

1. **Playfield bounds are constants.** Import `scripts/systems/playfield.gd` everywhere you write a position. `get_viewport_rect()` is for backdrop/despawn margins, not gameplay.

2. **Autoloads are the nervous system.** `Run` threads state through scene changes. When you transition scenes, you're not carrying objects—you're writing to `Run` and letting the next scene read it.

3. **Scene flow is linear (mostly).** You go main menu → combat loop → sector map → next combat (or outro). The sector map is the hub that reads the current node and spawns the right scene. No scene owns the run; they're all peers reading/writing shared state.

---

## Next Steps

- **Combat internals** (wave spawning, enemy behavior, director loop) → Doc 03
- **Player, Parts, and the economy** (health/damage/upgrades/shops) → Doc 04
- **Projectiles, effects, and visuals** (bullets, explosions, backdrop) → Doc 05
- **Conventions and gotchas** (the checklist) → Doc 06
